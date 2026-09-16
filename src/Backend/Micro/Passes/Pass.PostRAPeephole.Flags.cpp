#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool isCompareInstruction(MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::CmpRegImm:
                case MicroInstrOpcode::CmpMemReg:
                case MicroInstrOpcode::CmpMemImm:
                    return true;

                default:
                    return false;
            }
        }
    }

    namespace
    {
        // ALU ops that set ZF/SF/PF from their register result exactly as
        // `cmp result, 0` would. add/sub/and/or/xor all qualify. Multiply
        // (imul leaves SF/ZF/PF undefined on x64) and shifts (flags depend on
        // the count, undefined for count 0) are intentionally excluded.
        bool isFlagReuseSafeMicroOp(MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                    return true;
                default:
                    return false;
            }
        }

        // Conditions whose truth depends only on ZF/SF/PF, which the reused
        // arithmetic flags reproduce identically. Carry/overflow-sensitive
        // orderings (Above/Below/Greater/Less/Overflow) are NOT reusable: a
        // `cmp r, 0` clears CF/OF whereas the producing add/sub may set them.
        bool isFlagReuseSafeCond(MicroCond cond)
        {
            switch (cond)
            {
                case MicroCond::Equal:
                case MicroCond::NotEqual:
                case MicroCond::Zero:
                case MicroCond::NotZero:
                case MicroCond::Sign:
                case MicroCond::Parity:
                case MicroCond::NotParity:
                case MicroCond::EvenParity:
                case MicroCond::NotEvenParity:
                    return true;
                default:
                    return false;
            }
        }

        bool flagConsumerCond(const MicroInstr& inst, const MicroInstrOperand* ops, MicroCond& out)
        {
            if (!ops)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::JumpCond:
                case MicroInstrOpcode::JumpCondImm:
                    out = ops[0].cpuCond;
                    return true;
                case MicroInstrOpcode::SetCondReg:
                    out = ops[1].cpuCond;
                    return true;
                case MicroInstrOpcode::LoadCondRegReg:
                    out = ops[2].cpuCond;
                    return true;
                default:
                    return false;
            }
        }

        // If `inst` produces its register result together with reusable
        // ZF/SF/PF flags, report the destination register and the width those
        // flags were computed at.
        bool flagSettingResultDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg& outReg, MicroOpBits& outBits)
        {
            if (!ops)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::OpBinaryRegImm:
                    // [dst, opBits, microOp, imm]
                    if (!isFlagReuseSafeMicroOp(ops[2].microOp))
                        return false;
                    outReg  = ops[0].reg;
                    outBits = ops[1].opBits;
                    return true;

                case MicroInstrOpcode::OpBinaryRegReg:
                    // [dst, rhs, opBits, microOp]
                    if (!isFlagReuseSafeMicroOp(ops[3].microOp))
                        return false;
                    outReg  = ops[0].reg;
                    outBits = ops[2].opBits;
                    return true;

                default:
                    return false;
            }
        }

        // Nearest preceding instruction that actually does something. Only
        // no-effect fillers (nop, redundant self-copy) are skipped; those
        // touch neither registers nor CPU flags, so skipping them preserves
        // the "nothing happened between producer and compare" invariant.
        const MicroInstr* previousMeaningfulInstr(const Context& ctx, MicroInstrRef fromRef, MicroInstrRef& outRef)
        {
            for (MicroInstrRef cur = ctx.previousRef(fromRef); cur.isValid(); cur = ctx.previousRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return nullptr;
                if (isTriviallyErasableNoEffect(*inst, inst->ops(*ctx.operands)))
                    continue;
                outRef = cur;
                return inst;
            }
            return nullptr;
        }
    }

    // Drop a `cmp reg, 0` when the immediately preceding ALU instruction
    // already produced `reg` and left ZF/SF/PF describing it. The branch /
    // setcc consumers read the arithmetic flags directly:
    //
    //     sub  reg, x          sub  reg, x
    //     cmp  reg, 0    ->     (erased)
    //     je   .L              je   .L      ; tests ZF set by sub
    //
    // Only fires when every flag consumer uses a ZF/SF/PF-only condition.
    bool tryReuseFlagsForCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (cmpInst.op != MicroInstrOpcode::CmpRegImm || ctx.isClaimed(cmpRef))
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps)
            return false;
        if (cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0)
            return false;

        const MicroReg    cmpReg  = cmpOps[0].reg;
        const MicroOpBits cmpBits = cmpOps[1].opBits;
        if (!cmpReg.isAnyInt())
            return false;

        MicroInstrRef     prevRef = MicroInstrRef::invalid();
        const MicroInstr* prev    = previousMeaningfulInstr(ctx, cmpRef, prevRef);
        if (!prev)
            return false;

        MicroReg    prodReg;
        MicroOpBits prodBits;
        if (!flagSettingResultDef(*prev, prev->ops(*ctx.operands), prodReg, prodBits))
            return false;
        if (prodReg != cmpReg || prodBits != cmpBits)
            return false;

        // Validate every consumer that observes our flags before they are
        // overwritten. Anything that uses an unsafe condition, or any flags
        // user we don't recognize, aborts the rewrite.
        for (MicroInstrRef scanRef = ctx.nextRef(cmpRef); scanRef.isValid(); scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;

            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);
            if (isTriviallyErasableNoEffect(*scanInst, scanOps))
                continue;

            if (instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            {
                MicroCond cond;
                if (!flagConsumerCond(*scanInst, scanOps, cond))
                    return false;
                if (!isFlagReuseSafeCond(cond))
                    return false;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                if (!ctx.builder || !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*ctx.builder, scanRef))
                    return false;
                break;
            }
            if (MicroPassHelpers::instructionOverwritesCpuFlags(*scanInst, scanOps) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                break;
        }

        if (!ctx.claimAll({cmpRef}))
            return false;

        ctx.emitErase(cmpRef);
        return true;
    }

    namespace
    {
        struct CarryBoolean
        {
            MicroInstrRef clearRef;
            MicroInstrRef compareRef;
            MicroInstrRef setRef;
            MicroReg      reg;
        };

        // A cleared register followed by SETB contains exactly the incoming CF.
        // Keep the flag producer explicit so another queued rewrite cannot move it.
        bool findCarryBoolean(const Context& ctx, MicroInstrRef ref, CarryBoolean& out)
        {
            if (!ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
                return false;
            out.setRef            = ctx.previousRef(ref);
            const MicroInstr* set = ctx.instruction(out.setRef);
            if (!set || set->op != MicroInstrOpcode::SetCondReg)
                return false;
            const auto* setOps = set->ops(*ctx.operands);
            if (!setOps || !setOps[0].reg.isInt() || setOps[1].cpuCond != MicroCond::Below)
                return false;
            out.reg = setOps[0].reg;
            if (ctx.isPrivateFrameBase(out.reg))
                return false;
            out.compareRef            = ctx.previousRef(out.setRef);
            const MicroInstr* compare = ctx.instruction(out.compareRef);
            if (!compare || (compare->op != MicroInstrOpcode::CmpRegReg && compare->op != MicroInstrOpcode::CmpRegImm))
                return false;
            const auto* compareOps = compare->ops(*ctx.operands);
            if (!compareOps || !compareOps[0].reg.isInt() ||
                (compare->op == MicroInstrOpcode::CmpRegReg && !compareOps[1].reg.isInt()))
                return false;
            out.clearRef            = ctx.previousRef(out.compareRef);
            const MicroInstr* clear = ctx.instruction(out.clearRef);
            if (!clear || clear->op != MicroInstrOpcode::ClearReg)
                return false;
            const auto* clearOps = clear->ops(*ctx.operands);
            return clearOps && clearOps[0].reg == out.reg &&
                   (clearOps[1].opBits == MicroOpBits::B32 || clearOps[1].opBits == MicroOpBits::B64);
        }

        bool claimCarryBoolean(Context& ctx, MicroInstrRef ref, const CarryBoolean& value)
        {
            return MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) &&
                   ctx.claimAll({value.clearRef, value.compareRef, value.setRef, ref});
        }
    }

    // SBB computes the same all-zero/all-one mask while consuming CF directly.
    // Its use/def destination keeps the preceding clear to break the dependency.
    bool tryFoldCarryMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || ops[2].microOp != MicroOp::Negate ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64))
            return false;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value) || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
            return false;
        const MicroInstrOperand subtract[3] = {ops[0], ops[0], ops[1]};
        ctx.emitRewrite(value.setRef, MicroInstrOpcode::SubtractBorrowRegReg, subtract, true);
        ctx.emitErase(ref);
        return true;
    }

    bool tryFoldCarryAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || ops[3].microOp != MicroOp::Add || !ops[0].reg.isInt() || !ops[1].reg.isInt() ||
            ops[0].reg == ops[1].reg || ctx.isPrivateFrameBase(ops[0].reg) ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
            return false;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value) || (value.reg != ops[0].reg && value.reg != ops[1].reg))
            return false;
        if (value.reg != ops[0].reg && !ctx.isRegDeadAfterCurrent(value.reg))
            return false;
        if (!claimCarryBoolean(ctx, ref, value))
            return false;
        if (value.reg == ops[0].reg)
        {
            const MicroInstrOperand copy[3] = {ops[0], ops[1], ops[2]};
            ctx.emitRewrite(value.setRef, MicroInstrOpcode::LoadRegReg, copy, true);
        }
        else
            ctx.emitErase(value.setRef);
        MicroInstrOperand add[3] = {};
        add[0].reg               = ops[0].reg;
        add[1].opBits            = ops[2].opBits;
        add[2].valueU64          = 0;
        ctx.emitRewrite(ref, MicroInstrOpcode::AddCarryRegImm, add);
        // The copy or existing addend supplies every result bit now. Retain
        // the old clear only if the comparison itself reads that zero value.
        const MicroInstr*      compare       = ctx.instruction(value.compareRef);
        const MicroInstrUseDef compareUseDef = compare->collectUseDef(*ctx.operands, ctx.encoder);
        if (!microRegSpanContains(compareUseDef.uses.span(), value.reg))
            ctx.emitErase(value.clearRef);
        return true;
    }

    bool tryFoldCarryOffset(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;
        MicroOpBits bits;
        if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
        {
            if (ops[0].reg != ops[1].reg)
                return false;
            bits = ops[2].opBits;
        }
        else
        {
            if (ops[2].microOp != MicroOp::Add || ops[3].hasWideImmediateValue())
                return false;
            bits = ops[1].opBits;
        }
        if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
            return false;
        const uint64_t offset       = ops[3].valueU64;
        const uint64_t signedOffset = static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(offset)));
        if ((signedOffset & getBitsMask(bits)) != (offset & getBitsMask(bits)))
            return false;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value) || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
            return false;
        MicroInstrOperand add[3] = {};
        add[0].reg               = ops[0].reg;
        add[1].opBits            = bits;
        add[2].valueU64          = signedOffset;
        ctx.emitRewrite(ref, MicroInstrOpcode::AddCarryRegImm, add);
        ctx.emitErase(value.setRef);
        return true;
    }

    // With one input already in the result register, ADD is one byte shorter
    // than an unscaled LEA. The newly written flags must be unobserved.
    bool tryShortenAddressAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isInt() || !ops[1].reg.isInt() || !ops[2].reg.isInt() ||
            (ops[3].opBits != MicroOpBits::B32 && ops[3].opBits != MicroOpBits::B64) ||
            ops[4].opBits != MicroOpBits::B64 || ops[5].valueU64 != 1 || ops[6].valueU64 != 0 ||
            ctx.isPrivateFrameBase(ops[0].reg))
            return false;
        const MicroReg other = ops[0].reg == ops[1].reg ? ops[2].reg : ops[1].reg;
        if ((ops[0].reg != ops[1].reg && ops[0].reg != ops[2].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) || !ctx.claimAll({ref}))
            return false;
        MicroInstrOperand add[4] = {};
        add[0].reg               = ops[0].reg;
        add[1].reg               = other;
        add[2].opBits            = ops[3].opBits;
        add[3].microOp           = MicroOp::Add;
        ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, add);
        return true;
    }

    // A zero-extended byte/word shifted entirely within the low dword needs
    // no 64-bit shift. Keep flags out of the rewrite: SF/OF may differ.
    bool tryNarrowZeroExtendedShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64 ||
            ops[2].microOp != MicroOp::ShiftLeft || ops[3].hasWideImmediateValue() || ops[3].valueU64 >= 32)
            return false;
        const MicroInstrRef extRef = ctx.previousRef(ref);
        const MicroInstr*   ext    = ctx.instruction(extRef);
        if (!ext || ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* extOps = ext->ops(*ctx.operands);
        if (!extOps || extOps[0].reg != ops[0].reg ||
            (extOps[2].opBits != MicroOpBits::B32 && extOps[2].opBits != MicroOpBits::B64) ||
            (extOps[3].opBits != MicroOpBits::B8 && extOps[3].opBits != MicroOpBits::B16) ||
            getNumBits(extOps[3].opBits) + ops[3].valueU64 > 32 ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({extRef, ref}))
            return false;
        MicroInstrOperand rewritten[4] = {ops[0], ops[1], ops[2], ops[3]};
        rewritten[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(ref, inst.op, rewritten);
        return true;
    }

    // Initialize a value-or-zero selection with XOR before its compare.
    // Postpone the old zero load until after CMOV so both registers retain
    // their original final values, even when it overwrites the input.
    bool tryInvertZeroSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* copy = inst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        MicroInstrRef     cmpRef       = ctx.nextRef(ref);
        const MicroInstr* cmp          = ctx.instruction(cmpRef);
        bool              compareFirst = false;
        if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegReg && cmp->op != MicroInstrOpcode::CmpRegImm))
        {
            cmpRef       = ctx.previousRef(ref);
            cmp          = ctx.instruction(cmpRef);
            compareFirst = true;
        }
        if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegReg && cmp->op != MicroInstrOpcode::CmpRegImm))
            return false;
        const MicroInstrUseDef cmpUseDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        for (const MicroReg reg : cmpUseDef.uses)
            if (reg == copy[0].reg)
                return false;
        const MicroInstrRef zeroRef = ctx.nextRef(compareFirst ? ref : cmpRef);
        const MicroInstr*   zero    = ctx.instruction(zeroRef);
        if (!zero || zero->op != MicroInstrOpcode::LoadRegImm)
            return false;
        const auto* zeroOps = zero->ops(*ctx.operands);
        if (!zeroOps || !zeroOps[0].reg.isInt() || zeroOps[0].reg == copy[0].reg || zeroOps[2].hasWideImmediateValue() ||
            zeroOps[2].valueU64 != 0 || (zeroOps[1].opBits != MicroOpBits::B32 && zeroOps[1].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef selectRef = ctx.nextRef(zeroRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const auto* selectOps = select->ops(*ctx.operands);
        MicroCond   inverted;
        if (!selectOps || selectOps[0].reg != copy[0].reg || selectOps[1].reg != zeroOps[0].reg ||
            selectOps[3].opBits != copy[2].opBits || !MicroPassHelpers::invertCondition(inverted, selectOps[2].cpuCond) ||
            !ctx.claimAll({ref, cmpRef, zeroRef, selectRef}))
            return false;
        MicroInstrOperand clear[2] = {};
        clear[0].reg               = copy[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand move[4]  = {selectOps[0], copy[1], selectOps[2], selectOps[3]};
        move[2].cpuCond            = inverted;
        if (compareFirst)
        {
            ctx.emitRewrite(cmpRef, MicroInstrOpcode::ClearReg, clear);
            ctx.emitRewrite(ref, cmp->op, std::span{cmp->ops(*ctx.operands), cmp->numOperands}, true);
        }
        else
            ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(zeroRef, select->op, move, true);
        ctx.emitRewrite(selectRef, zero->op, std::span{zeroOps, zero->numOperands});
        return true;
    }

    // A selected value copied back over its zero register can select directly
    // into that register. Keep the reverse copy until DCE proves it unnecessary.
    bool tryInvertResultZeroSelect(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef selectRef = ctx.previousRef(copyRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const auto* selectOps = select->ops(*ctx.operands);
        MicroCond   inverted;
        if (!selectOps || selectOps[0].reg != copy[1].reg || selectOps[1].reg != copy[0].reg ||
            selectOps[3].opBits != copy[2].opBits || !MicroPassHelpers::invertCondition(inverted, selectOps[2].cpuCond))
            return false;
        const MicroInstrRef zeroRef = ctx.previousRef(selectRef);
        const MicroInstr*   zero    = ctx.instruction(zeroRef);
        if (!zero || zero->op != MicroInstrOpcode::LoadRegImm)
            return false;
        const auto* zeroOps = zero->ops(*ctx.operands);
        if (!zeroOps || zeroOps[0].reg != copy[0].reg || zeroOps[2].hasWideImmediateValue() || zeroOps[2].valueU64 != 0 ||
            (zeroOps[1].opBits != MicroOpBits::B32 && zeroOps[1].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef cmpRef = ctx.previousRef(zeroRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegReg && cmp->op != MicroInstrOpcode::CmpRegImm))
            return false;
        const MicroInstrUseDef useDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        for (const MicroReg reg : useDef.uses)
            if (reg == copy[0].reg)
                return false;
        if (!ctx.claimAll({cmpRef, zeroRef, selectRef, copyRef}))
            return false;
        MicroInstrOperand clear[2]         = {};
        clear[0].reg                       = copy[0].reg;
        clear[1].opBits                    = MicroOpBits::B32;
        MicroInstrOperand selected[4]      = {copy[0], copy[1], selectOps[2], copy[2]};
        selected[2].cpuCond                = inverted;
        const MicroInstrOperand reverse[3] = {copy[1], copy[0], copy[2]};
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(zeroRef, cmp->op, std::span{cmp->ops(*ctx.operands), cmp->numOperands}, true);
        ctx.emitRewrite(selectRef, select->op, selected);
        ctx.emitRewrite(copyRef, copyInst.op, reverse);
        return true;
    }

    // When only SUB's flags reach a widened boolean, replace its copied
    // result with CMP and clear the boolean destination before that compare.
    bool tryFoldSubtractBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* result = inst.ops(*ctx.operands);
        if (!result || !result[0].reg.isInt() || result[0].reg != result[1].reg || result[3].opBits != MicroOpBits::B8 ||
            (result[2].opBits != MicroOpBits::B32 && result[2].opBits != MicroOpBits::B64) || ctx.isPrivateFrameBase(result[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != result[0].reg)
            return false;
        const MicroInstrRef subRef = ctx.previousRef(setRef);
        const MicroInstr*   sub    = ctx.instruction(subRef);
        if (!sub || sub->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* subOps = sub->ops(*ctx.operands);
        if (!subOps || subOps[0].reg != result[0].reg || !subOps[1].reg.isInt() || subOps[3].microOp != MicroOp::Subtract ||
            (subOps[2].opBits != MicroOpBits::B32 && subOps[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef copyRef = ctx.previousRef(subRef);
        const MicroInstr*   copy    = ctx.instruction(copyRef);
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* copyOps = copy->ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg != result[0].reg || !copyOps[1].reg.isInt() || copyOps[1].reg == result[0].reg ||
            copyOps[2].opBits != subOps[2].opBits || !ctx.claimAll({copyRef, subRef, setRef, ref}))
            return false;
        MicroInstrOperand clear[2]   = {};
        clear[0].reg                 = result[0].reg;
        clear[1].opBits              = MicroOpBits::B32;
        MicroInstrOperand compare[3] = {copyOps[1], subOps[1], subOps[2]};
        if (compare[1].reg == result[0].reg)
            compare[1].reg = copyOps[1].reg;
        ctx.emitRewrite(copyRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(subRef, MicroInstrOpcode::CmpRegReg, compare);
        ctx.emitErase(ref);
        return true;
    }

    // Fold zero-extend; compare; SETcc; zero-extend into a narrow compare
    // with a pre-cleared boolean destination. Unsigned/equality conditions
    // survive narrowing when the immediate fits the source width.
    bool tryFoldZeroExtendedBooleanCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* result = inst.ops(*ctx.operands);
        if (!result || !result[0].reg.isInt() || result[0].reg != result[1].reg || result[3].opBits != MicroOpBits::B8 ||
            (result[2].opBits != MicroOpBits::B32 && result[2].opBits != MicroOpBits::B64) || ctx.isPrivateFrameBase(result[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != result[0].reg)
            return false;
        switch (setOps[1].cpuCond)
        {
            case MicroCond::Equal:
            case MicroCond::NotEqual:
            case MicroCond::Zero:
            case MicroCond::NotZero:
            case MicroCond::Above:
            case MicroCond::AboveOrEqual:
            case MicroCond::Below:
            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove:
                break;
            default:
                return false;
        }
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || cmpOps[0].reg != result[0].reg || cmpOps[2].hasWideImmediateValue())
            return false;
        const MicroInstrRef sourceRef = ctx.previousRef(cmpRef);
        const MicroInstr*   source    = ctx.instruction(sourceRef);
        if (!source || source->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* sourceOps = source->ops(*ctx.operands);
        if (!sourceOps || sourceOps[0].reg != result[0].reg || !sourceOps[1].reg.isInt() || sourceOps[1].reg == result[0].reg ||
            (sourceOps[2].opBits != MicroOpBits::B32 && sourceOps[2].opBits != MicroOpBits::B64) ||
            (sourceOps[3].opBits != MicroOpBits::B8 && sourceOps[3].opBits != MicroOpBits::B16) ||
            getNumBits(cmpOps[1].opBits) < getNumBits(sourceOps[3].opBits) ||
            cmpOps[2].valueU64 > getBitsMask(sourceOps[3].opBits) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({sourceRef, cmpRef, setRef, ref}))
            return false;
        MicroInstrOperand clear[2]  = {};
        clear[0].reg                = result[0].reg;
        clear[1].opBits             = MicroOpBits::B32;
        MicroInstrOperand narrow[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
        narrow[0].reg               = sourceOps[1].reg;
        narrow[1].opBits            = sourceOps[3].opBits;
        ctx.emitRewrite(sourceRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(cmpRef, cmp->op, narrow);
        ctx.emitErase(ref);
        return true;
    }

    // The legacy high-byte registers can replace a shift plus byte extraction.
    // Ask the encoder before forming one: a REX prefix makes them unavailable.
    bool tryExtractHighByte(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ctx.encoder || ext[3].opBits != MicroOpBits::B8 ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            ctx.isPrivateFrameBase(ext[0].reg) || ctx.isPrivateFrameBase(ext[1].reg) ||
            !ctx.encoder->supportsHighByteExtract(ext[0].reg, ext[1].reg))
            return false;
        const MicroInstrRef shiftRef = ctx.previousRef(ref);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        const auto* ops = shift->ops(*ctx.operands);
        if (!ops || ops[0].reg != ext[1].reg ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64) ||
            (ops[2].microOp != MicroOp::ShiftRight && ops[2].microOp != MicroOp::ShiftArithmeticRight) || ops[3].hasWideImmediateValue() || ops[3].valueU64 != 8 ||
            (ext[0].reg != ext[1].reg && !ctx.isRegDeadAfterCurrent(ext[1].reg)) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({shiftRef, ref}))
            return false;
        const MicroInstrOperand extract[3] = {ext[0], ext[1], ext[2]};
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadHighByteRegReg, extract);
        ctx.emitErase(shiftRef);
        return true;
    }

    // If only a low byte/word of a logical right shift survives, perform the
    // shift in 32 bits when all bits contributing to that slice are below bit 32.
    bool tryNarrowTruncatedRightShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ext[0].reg.isInt() || !ext[1].reg.isInt() ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            (ext[3].opBits != MicroOpBits::B8 && ext[3].opBits != MicroOpBits::B16))
            return false;
        const MicroInstrRef shiftRef = ctx.previousRef(ref);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        const auto* ops = shift->ops(*ctx.operands);
        if (!ops || ops[0].reg != ext[1].reg || ops[1].opBits != MicroOpBits::B64 ||
            ops[2].microOp != MicroOp::ShiftRight || ops[3].hasWideImmediateValue() ||
            ops[3].valueU64 == 0 || ops[3].valueU64 >= 32 || ops[3].valueU64 + getNumBits(ext[3].opBits) > 32 ||
            ctx.isPrivateFrameBase(ops[0].reg) ||
            (ext[0].reg != ext[1].reg && !ctx.isRegDeadAfterCurrent(ext[1].reg)) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({shiftRef, ref}))
            return false;
        MicroInstrOperand narrowed[4] = {ops[0], ops[1], ops[2], ops[3]};
        narrowed[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(shiftRef, shift->op, narrowed);
        return true;
    }

    // A signed comparison against zero exposes the sign bit directly. Keep
    // the original full-width source and define every result bit with a shift.
    bool tryExtractSignBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ext[0].reg.isInt() || ext[0].reg != ext[1].reg ||
            ext[3].opBits != MicroOpBits::B8 ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            ctx.isPrivateFrameBase(ext[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != ext[0].reg)
            return false;
        const MicroCond condition = setOps[1].cpuCond;
        if (condition != MicroCond::Less && condition != MicroCond::Sign)
            return false;
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || !cmpOps[0].reg.isInt() || cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0 ||
            (cmpOps[1].opBits != MicroOpBits::B32 && cmpOps[1].opBits != MicroOpBits::B64) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({cmpRef, setRef, ref}))
            return false;
        MicroInstrOperand copy[3] = {};
        copy[0].reg               = ext[0].reg;
        copy[1].reg               = cmpOps[0].reg;
        copy[2].opBits            = cmpOps[1].opBits;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::LoadRegReg, copy);
        MicroInstrOperand shift[4] = {};
        shift[0].reg               = ext[0].reg;
        shift[1].opBits            = cmpOps[1].opBits;
        shift[2].microOp           = MicroOp::ShiftRight;
        shift[3].valueU64          = getNumBits(cmpOps[1].opBits) - 1;
        ctx.emitRewrite(setRef, MicroInstrOpcode::OpBinaryRegImm, shift, true);
        ctx.emitErase(ref);
        return true;
    }

    // Zero the full result before its flag producer instead of extending
    // SETcc's byte afterward. The producer must not read that result register.
    bool tryClearBeforeSetCondition(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ext[0].reg.isInt() || ext[0].reg != ext[1].reg ||
            ext[3].opBits != MicroOpBits::B8 ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            ctx.isPrivateFrameBase(ext[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != ext[0].reg)
            return false;
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || !cmpOps[0].reg.isInt())
            return false;
        if (cmp->op == MicroInstrOpcode::CmpRegReg)
        {
            if (!cmpOps[1].reg.isInt())
                return false;
        }
        else if (cmp->op != MicroInstrOpcode::CmpRegImm)
        {
            // These integer ALU producers overwrite the incoming flags and
            // read their destination, so the use check also protects its result.
            MicroReg    resultReg;
            MicroOpBits resultBits;
            if (!flagSettingResultDef(*cmp, cmpOps, resultReg, resultBits))
                return false;
        }
        const MicroInstrUseDef useDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        for (const MicroReg reg : useDef.uses)
            if (reg == ext[0].reg)
                return false;
        if (!ctx.claimAll({cmpRef, setRef, ref}))
            return false;
        MicroInstrOperand clear[2] = {};
        clear[0].reg               = ext[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setRef, cmp->op, std::span{cmpOps, cmp->numOperands}, true);
        ctx.emitRewrite(ref, set->op, std::span{setOps, set->numOperands});
        return true;
    }

    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!isCompareInstruction(inst.op))
            return false;

        for (MicroInstrRef scanRef = ctx.nextRef(ref); scanRef.isValid(); scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;

            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);
            if (isTriviallyErasableNoEffect(*scanInst, scanOps))
                continue;

            if (instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            {
                if (isRedundantFallthroughJumpToNextLabel(ctx, scanRef, *scanInst, scanOps))
                    continue;

                return false;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            if (info.flags.has(MicroInstrFlagsE::JumpInstruction) && (!ctx.builder || !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*ctx.builder, scanRef)))
                return false;
            if (MicroPassHelpers::instructionOverwritesCpuFlags(*scanInst, scanOps) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                if (!ctx.claimAll({ref}))
                    return false;

                ctx.emitErase(ref);
                return true;
            }
        }

        if (!ctx.claimAll({ref}))
            return false;

        ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();

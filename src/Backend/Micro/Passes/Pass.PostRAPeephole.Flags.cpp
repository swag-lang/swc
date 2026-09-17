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
                case MicroInstrOpcode::TestRegReg:
                case MicroInstrOpcode::TestRegImm:
                case MicroInstrOpcode::TestMemReg:
                case MicroInstrOpcode::TestMemImm:
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::CmpRegImm:
                case MicroInstrOpcode::CmpMemReg:
                case MicroInstrOpcode::CmpMemImm:
                case MicroInstrOpcode::CmpAmcImm:
                    return true;

                default:
                    return false;
            }
        }

        bool canMoveComparisonForSelect(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (!isCompareInstruction(inst.op) || !ops)
                return false;
            // A RIP-relative memory comparison can own a relocation tied to
            // its instruction reference. Keep such comparisons in place.
            return (inst.op != MicroInstrOpcode::CmpMemReg && inst.op != MicroInstrOpcode::CmpMemImm &&
                    inst.op != MicroInstrOpcode::TestMemReg && inst.op != MicroInstrOpcode::TestMemImm) ||
                   !ops[0].reg.isInstructionPointer();
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

        // The producer is claimed with the compare: a rule of the same sweep
        // that rewrites it into a flag-free form (`mov r, a; add r, b` into a
        // `lea`, relying on this very compare to redefine the flags) would
        // leave the consumers reading nothing.
        if (!ctx.claimAll({cmpRef, prevRef}))
            return false;

        ctx.emitErase(cmpRef);
        return true;
    }

    // (a == 0) * (b == 0) is (a | b) == 0. At this late stage the first
    // source may be destroyed only when physical liveness proves that it is
    // dead after the original product.
    bool tryFoldZeroBooleanProduct(Context& ctx, MicroInstrRef multiplyRef, const MicroInstr& multiplyInst)
    {
        if (ctx.isClaimed(multiplyRef) || multiplyInst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* product = multiplyInst.ops(*ctx.operands);
        if (!product || product[3].microOp != MicroOp::MultiplySigned)
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(multiplyRef);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        const MicroInstrRef setSecondRef = ctx.previousRef(extFirstRef);
        const MicroInstr*   setSecond    = ctx.instruction(setSecondRef);
        const MicroInstrRef cmpSecondRef = ctx.previousRef(setSecondRef);
        const MicroInstr*   cmpSecond    = ctx.instruction(cmpSecondRef);
        const MicroInstrRef setFirstRef  = ctx.previousRef(cmpSecondRef);
        const MicroInstr*   setFirst     = ctx.instruction(setFirstRef);
        const MicroInstrRef cmpFirstRef  = ctx.previousRef(setFirstRef);
        const MicroInstr*   cmpFirst     = ctx.instruction(cmpFirstRef);
        if (!cmpFirst || !setFirst || !cmpSecond || !setSecond || !extFirst || !extSecond ||
            cmpFirst->op != MicroInstrOpcode::CmpRegImm || setFirst->op != MicroInstrOpcode::SetCondReg ||
            cmpSecond->op != MicroInstrOpcode::CmpRegImm ||
            setSecond->op != MicroInstrOpcode::SetCondReg ||
            extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg || extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;

        const auto* firstCmp  = cmpFirst->ops(*ctx.operands);
        const auto* firstSet  = setFirst->ops(*ctx.operands);
        const auto* secondCmp = cmpSecond->ops(*ctx.operands);
        const auto* secondSet = setSecond->ops(*ctx.operands);
        const auto* firstExt  = extFirst->ops(*ctx.operands);
        const auto* secondExt = extSecond->ops(*ctx.operands);
        if (!firstCmp || !firstSet || !secondCmp || !secondSet || !firstExt || !secondExt ||
            !firstCmp[0].reg.isInt() || !secondCmp[0].reg.isInt() || secondCmp[0].reg == firstCmp[0].reg ||
            firstCmp[2].hasWideImmediateValue() || firstCmp[2].valueU64 != 0 ||
            (firstCmp[1].opBits != MicroOpBits::B32 && firstCmp[1].opBits != MicroOpBits::B64) ||
            secondCmp[2].hasWideImmediateValue() || secondCmp[2].valueU64 != 0 || secondCmp[1].opBits != firstCmp[1].opBits ||
            firstSet[0].reg != firstExt[0].reg || firstExt[0].reg != firstExt[1].reg ||
            secondSet[0].reg != secondExt[0].reg || secondExt[0].reg != secondExt[1].reg ||
            (firstSet[1].cpuCond != MicroCond::Equal && firstSet[1].cpuCond != MicroCond::Zero) ||
            (secondSet[1].cpuCond != MicroCond::Equal && secondSet[1].cpuCond != MicroCond::Zero) ||
            firstExt[3].opBits != MicroOpBits::B8 || secondExt[3].opBits != MicroOpBits::B8 ||
            firstExt[2].opBits != secondExt[2].opBits ||
            (firstExt[2].opBits != MicroOpBits::B32 && firstExt[2].opBits != MicroOpBits::B64) ||
            product[0].reg != firstExt[0].reg || product[1].reg != secondExt[0].reg ||
            product[2].opBits != firstExt[2].opBits ||
            firstExt[0].reg == firstCmp[0].reg || firstExt[0].reg == secondCmp[0].reg ||
            !ctx.isRegDeadAfterCurrent(firstCmp[0].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, multiplyRef, ctx.builder) ||
            !ctx.claimAll({cmpFirstRef, setFirstRef, cmpSecondRef, setSecondRef, extFirstRef, extSecondRef, multiplyRef}))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = firstExt[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand either[4] = {};
        either[0].reg               = firstCmp[0].reg;
        either[1].reg               = secondCmp[0].reg;
        either[2].opBits            = firstCmp[1].opBits;
        either[3].microOp           = MicroOp::Or;
        MicroInstrOperand set[2] = {};
        set[0].reg               = firstExt[0].reg;
        set[1].cpuCond           = MicroCond::Equal;
        ctx.emitRewrite(cmpFirstRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setFirstRef, MicroInstrOpcode::OpBinaryRegReg, either, true);
        ctx.emitRewrite(cmpSecondRef, MicroInstrOpcode::SetCondReg, set);
        ctx.emitErase(setSecondRef);
        ctx.emitErase(extFirstRef);
        ctx.emitErase(extSecondRef);
        ctx.emitErase(multiplyRef);
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
            bool          inverse = false;
        };

        // A cleared register followed by SETB or SETAE contains CF or its inverse.
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
            if (!setOps || !setOps[0].reg.isInt() || (setOps[1].cpuCond != MicroCond::Below && setOps[1].cpuCond != MicroCond::AboveOrEqual))
                return false;
            out.reg     = setOps[0].reg;
            out.inverse = setOps[1].cpuCond == MicroCond::AboveOrEqual;
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

        bool findZeroBoolean(const Context& ctx, MicroInstrRef ref, CarryBoolean& out)
        {
            if (!ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
                return false;
            out.setRef            = ctx.previousRef(ref);
            const MicroInstr* set = ctx.instruction(out.setRef);
            if (!set || set->op != MicroInstrOpcode::SetCondReg)
                return false;
            const auto* setOps = set->ops(*ctx.operands);
            if (!setOps || !setOps[0].reg.isInt() ||
                (setOps[1].cpuCond != MicroCond::Equal && setOps[1].cpuCond != MicroCond::Zero))
                return false;
            out.reg     = setOps[0].reg;
            out.inverse = false;
            if (ctx.isPrivateFrameBase(out.reg))
                return false;

            out.compareRef            = ctx.previousRef(out.setRef);
            const MicroInstr* compare = ctx.instruction(out.compareRef);
            if (!compare || compare->op != MicroInstrOpcode::CmpRegImm)
                return false;
            const auto* compareOps = compare->ops(*ctx.operands);
            if (!compareOps || !compareOps[0].reg.isInt() || compareOps[0].reg == out.reg ||
                compareOps[2].hasWideImmediateValue() || compareOps[2].valueU64 != 0)
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
        if (!findCarryBoolean(ctx, ref, value) || value.inverse || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
            return false;
        const MicroInstrOperand subtract[3] = {ops[0], ops[0], ops[1]};
        ctx.emitRewrite(value.setRef, MicroInstrOpcode::SubtractBorrowRegReg, subtract, true);
        ctx.emitErase(ref);
        return true;
    }

    // Zero/nonzero masks can consume CF directly. For nonzero, NEG establishes
    // CF while destroying a source only when that physical value is dead.
    bool tryFoldZeroComparisonMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic() || !ops ||
            ops[2].microOp != MicroOp::Negate || !ops[0].reg.isInt() || ctx.isPrivateFrameBase(ops[0].reg) ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != ops[0].reg ||
            (setOps[1].cpuCond != MicroCond::Equal && setOps[1].cpuCond != MicroCond::NotEqual))
            return false;
        const MicroInstrRef compareRef = ctx.previousRef(setRef);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        if (!compare || compare->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmp = compare->ops(*ctx.operands);
        if (!cmp || !cmp[0].reg.isInt() || cmp[0].reg == ops[0].reg || ctx.isPrivateFrameBase(cmp[0].reg) ||
            cmp[2].hasWideImmediateValue() || cmp[2].valueU64 != 0)
            return false;
        const bool nonzero = setOps[1].cpuCond == MicroCond::NotEqual;
        if (nonzero && !ctx.isRegDeadAfterCurrent(cmp[0].reg))
            return false;
        const MicroInstrRef clearRef = ctx.previousRef(compareRef);
        const MicroInstr*   clear    = ctx.instruction(clearRef);
        if (!clear || clear->op != MicroInstrOpcode::ClearReg)
            return false;
        const auto* cleared = clear->ops(*ctx.operands);
        if (!cleared || cleared[0].reg != ops[0].reg ||
            (cleared[1].opBits != MicroOpBits::B32 && cleared[1].opBits != MicroOpBits::B64) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({clearRef, compareRef, setRef, ref}))
            return false;
        MicroInstrOperand producer[3];
        producer[0] = cmp[0];
        producer[1] = cmp[1];
        if (nonzero)
        {
            producer[2].microOp = MicroOp::Negate;
            ctx.emitRewrite(compareRef, MicroInstrOpcode::OpUnaryReg, producer);
        }
        else
        {
            producer[2].valueU64 = 1;
            ctx.emitRewrite(compareRef, MicroInstrOpcode::CmpRegImm, producer);
        }
        const MicroInstrOperand subtract[3] = {ops[0], ops[0], ops[1]};
        ctx.emitRewrite(setRef, MicroInstrOpcode::SubtractBorrowRegReg, subtract, true);
        ctx.emitErase(ref);
        return true;
    }

    bool tryFoldCarryArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || (ops[3].microOp != MicroOp::Add && ops[3].microOp != MicroOp::Subtract) || !ops[0].reg.isInt() || !ops[1].reg.isInt() ||
            ops[0].reg == ops[1].reg || ctx.isPrivateFrameBase(ops[0].reg) ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
            return false;
        const bool   subtract = ops[3].microOp == MicroOp::Subtract;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value) || (value.reg != ops[0].reg && value.reg != ops[1].reg))
            return false;
        if (subtract && value.reg != ops[1].reg)
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
        add[2].valueU64          = value.inverse ? getBitsMask(ops[2].opBits) : 0;
        const auto opcode        = subtract != value.inverse ? MicroInstrOpcode::SubtractBorrowRegImm : MicroInstrOpcode::AddCarryRegImm;
        ctx.emitRewrite(ref, opcode, add);
        // The copy or existing addend supplies every result bit now. Retain
        // the old clear only if the comparison itself reads that zero value.
        const MicroInstr*      compare       = ctx.instruction(value.compareRef);
        const MicroInstrUseDef compareUseDef = compare->collectUseDef(*ctx.operands, ctx.encoder);
        if (!microRegSpanContains(compareUseDef.uses.span(), value.reg))
            ctx.emitErase(value.clearRef);
        return true;
    }

    // Sum two unsigned comparisons without widening both byte booleans. The
    // second SETB is the carry flag itself, so ADC can consume it directly.
    bool tryFoldCarryComparisonSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
            return false;
        const auto* add = inst.ops(*ctx.operands);
        if (!add || add[3].microOp != MicroOp::Add || !add[0].reg.isInt() || !add[1].reg.isInt() ||
            add[0].reg == add[1].reg || ctx.isPrivateFrameBase(add[0].reg) ||
            (add[2].opBits != MicroOpBits::B32 && add[2].opBits != MicroOpBits::B64) ||
            !ctx.isRegDeadAfterCurrent(add[1].reg))
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(ref);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        const MicroInstrRef setSecondRef = ctx.previousRef(extFirstRef);
        const MicroInstr*   setSecond    = ctx.instruction(setSecondRef);
        const MicroInstrRef cmpSecondRef = ctx.previousRef(setSecondRef);
        const MicroInstr*   cmpSecond    = ctx.instruction(cmpSecondRef);
        const MicroInstrRef setFirstRef  = ctx.previousRef(cmpSecondRef);
        const MicroInstr*   setFirst     = ctx.instruction(setFirstRef);
        const MicroInstrRef cmpFirstRef  = ctx.previousRef(setFirstRef);
        const MicroInstr*   cmpFirst     = ctx.instruction(cmpFirstRef);
        if (!extFirst || !extSecond || !setFirst || !setSecond || !cmpFirst || !cmpSecond ||
            extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg || extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg ||
            setFirst->op != MicroInstrOpcode::SetCondReg || setSecond->op != MicroInstrOpcode::SetCondReg ||
            cmpFirst->op != MicroInstrOpcode::CmpRegReg || cmpSecond->op != MicroInstrOpcode::CmpRegReg)
            return false;

        const auto* firstExt  = extFirst->ops(*ctx.operands);
        const auto* secondExt = extSecond->ops(*ctx.operands);
        const auto* firstSet  = setFirst->ops(*ctx.operands);
        const auto* secondSet = setSecond->ops(*ctx.operands);
        const auto* firstCmp  = cmpFirst->ops(*ctx.operands);
        const auto* secondCmp = cmpSecond->ops(*ctx.operands);
        if (!firstExt || !secondExt || !firstSet || !secondSet || !firstCmp || !secondCmp ||
            firstExt[0].reg != add[0].reg || firstExt[1].reg != add[0].reg ||
            secondExt[0].reg != add[1].reg || secondExt[1].reg != add[1].reg ||
            firstExt[2].opBits != add[2].opBits || secondExt[2].opBits != add[2].opBits ||
            firstExt[3].opBits != MicroOpBits::B8 || secondExt[3].opBits != MicroOpBits::B8 ||
            firstSet[0].reg != add[0].reg || secondSet[0].reg != add[1].reg ||
            firstSet[1].cpuCond != MicroCond::Below || secondSet[1].cpuCond != MicroCond::Below ||
            firstCmp[2].opBits != add[2].opBits || secondCmp[2].opBits != add[2].opBits ||
            !firstCmp[0].reg.isInt() || !firstCmp[1].reg.isInt() ||
            !secondCmp[0].reg.isInt() || !secondCmp[1].reg.isInt() ||
            firstCmp[0].reg == add[0].reg || firstCmp[1].reg == add[0].reg ||
            secondCmp[0].reg == add[0].reg || secondCmp[1].reg == add[0].reg ||
            !ctx.claimAll({cmpFirstRef, setFirstRef, cmpSecondRef, setSecondRef, extFirstRef, extSecondRef, ref}))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = add[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand addCarry[3] = {};
        addCarry[0].reg               = add[0].reg;
        addCarry[1].opBits            = add[2].opBits;
        addCarry[2].valueU64          = 0;
        ctx.emitRewrite(cmpFirstRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setFirstRef, cmpFirst->op, std::span{firstCmp, cmpFirst->numOperands}, true);
        ctx.emitRewrite(cmpSecondRef, setFirst->op, std::span{firstSet, setFirst->numOperands});
        ctx.emitRewrite(setSecondRef, cmpSecond->op, std::span{secondCmp, cmpSecond->numOperands}, true);
        ctx.emitRewrite(extFirstRef, MicroInstrOpcode::AddCarryRegImm, addCarry);
        ctx.emitErase(extSecondRef);
        ctx.emitErase(ref);
        return true;
    }

    // Two zero/nonzero comparisons can share one full-width boolean destination.
    // Comparing unsigned x with one exposes x == 0 as carry; SBB by -1 exposes
    // its inverse. Reusing the existing instruction slots also moves the clear
    // before the first SETcc, so neither byte result needs a MOVZX.
    bool tryFoldZeroTestBooleanSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
            return false;
        const auto* add = inst.ops(*ctx.operands);
        if (!add || add[3].microOp != MicroOp::Add || !add[0].reg.isInt() || !add[1].reg.isInt() ||
            add[0].reg == add[1].reg || ctx.isPrivateFrameBase(add[0].reg) ||
            (add[2].opBits != MicroOpBits::B32 && add[2].opBits != MicroOpBits::B64) ||
            !ctx.isRegDeadAfterCurrent(add[1].reg))
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(ref);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        if (!extFirst || !extSecond || extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg ||
            extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* firstExt  = extFirst->ops(*ctx.operands);
        const auto* secondExt = extSecond->ops(*ctx.operands);
        if (!firstExt || !secondExt ||
            firstExt[0].reg != add[0].reg || firstExt[1].reg != add[0].reg ||
            secondExt[0].reg != add[1].reg || secondExt[1].reg != add[1].reg ||
            firstExt[2].opBits != add[2].opBits || secondExt[2].opBits != add[2].opBits ||
            firstExt[3].opBits != MicroOpBits::B8 || secondExt[3].opBits != MicroOpBits::B8)
            return false;

        const MicroInstrRef setSecondRef = ctx.previousRef(extFirstRef);
        const MicroInstr*   setSecond    = ctx.instruction(setSecondRef);
        const MicroInstrRef cmpSecondRef = ctx.previousRef(setSecondRef);
        const MicroInstr*   cmpSecond    = ctx.instruction(cmpSecondRef);
        const MicroInstrRef setFirstRef  = ctx.previousRef(cmpSecondRef);
        const MicroInstr*   setFirst     = ctx.instruction(setFirstRef);
        const MicroInstrRef cmpFirstRef  = ctx.previousRef(setFirstRef);
        const MicroInstr*   cmpFirst     = ctx.instruction(cmpFirstRef);
        if (!setFirst || !setSecond || !cmpFirst || !cmpSecond ||
            setFirst->op != MicroInstrOpcode::SetCondReg || setSecond->op != MicroInstrOpcode::SetCondReg ||
            cmpFirst->op != MicroInstrOpcode::CmpRegImm || cmpSecond->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* firstSet  = setFirst->ops(*ctx.operands);
        const auto* secondSet = setSecond->ops(*ctx.operands);
        const auto* firstCmp  = cmpFirst->ops(*ctx.operands);
        const auto* secondCmp = cmpSecond->ops(*ctx.operands);
        const bool  firstZero    = firstSet && (firstSet[1].cpuCond == MicroCond::Equal || firstSet[1].cpuCond == MicroCond::Zero);
        const bool  firstNonzero = firstSet && (firstSet[1].cpuCond == MicroCond::NotEqual || firstSet[1].cpuCond == MicroCond::NotZero);
        const bool  secondZero   = secondSet && (secondSet[1].cpuCond == MicroCond::Equal || secondSet[1].cpuCond == MicroCond::Zero);
        const bool  secondNonzero = secondSet && (secondSet[1].cpuCond == MicroCond::NotEqual || secondSet[1].cpuCond == MicroCond::NotZero);
        if (!firstSet || !secondSet || !firstCmp || !secondCmp ||
            firstSet[0].reg != add[0].reg || secondSet[0].reg != add[1].reg ||
            (!firstZero && !firstNonzero) || (!secondZero && !secondNonzero) ||
            !firstCmp[0].reg.isInt() || !secondCmp[0].reg.isInt() ||
            firstCmp[0].reg == add[0].reg || secondCmp[0].reg == add[0].reg ||
            firstCmp[2].hasWideImmediateValue() || secondCmp[2].hasWideImmediateValue() ||
            firstCmp[2].valueU64 != 0 || secondCmp[2].valueU64 != 0 ||
            (secondNonzero && !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder)) ||
            !ctx.claimAll({cmpFirstRef, setFirstRef, cmpSecondRef, setSecondRef, extFirstRef, extSecondRef, ref}))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = add[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand compareFirst[3] = {firstCmp[0], firstCmp[1], firstCmp[2]};
        MicroInstrOperand set[2]          = {firstSet[0], firstSet[1]};
        MicroInstrOperand compareSecond[3] = {secondCmp[0], secondCmp[1], secondCmp[2]};
        compareSecond[2].valueU64          = 1;
        MicroInstrOperand addCarry[3] = {};
        addCarry[0].reg               = add[0].reg;
        addCarry[1].opBits            = add[2].opBits;
        addCarry[2].valueU64          = secondNonzero ? getBitsMask(add[2].opBits) : 0;
        ctx.emitRewrite(cmpFirstRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setFirstRef, MicroInstrOpcode::CmpRegImm, compareFirst, true);
        ctx.emitRewrite(cmpSecondRef, MicroInstrOpcode::SetCondReg, set);
        ctx.emitRewrite(setSecondRef, MicroInstrOpcode::CmpRegImm, compareSecond, true);
        ctx.emitRewrite(extFirstRef, secondNonzero ? MicroInstrOpcode::SubtractBorrowRegImm : MicroInstrOpcode::AddCarryRegImm, addCarry);
        ctx.emitErase(extSecondRef);
        ctx.emitErase(ref);
        return true;
    }

    // Compute a bitwise operation before widening two byte values. The final
    // flags differ for arbitrary values because B8 and B32/B64 have different
    // sign bits, so only fold when those flags are dead.
    bool tryNarrowBitwiseZeroExtensions(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || inst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* binary = inst.ops(*ctx.operands);
        if (!binary || (binary[3].microOp != MicroOp::And && binary[3].microOp != MicroOp::Or && binary[3].microOp != MicroOp::Xor) ||
            (binary[2].opBits != MicroOpBits::B32 && binary[2].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(ref);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        if (!extFirst || !extSecond || extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg ||
            extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* first  = extFirst->ops(*ctx.operands);
        const auto* second = extSecond->ops(*ctx.operands);
        if (!first || !second || first[0].reg != binary[0].reg || second[0].reg != binary[1].reg ||
            first[0].reg != first[1].reg || second[0].reg != second[1].reg || first[0].reg == second[0].reg ||
            first[2].opBits != binary[2].opBits || second[2].opBits != binary[2].opBits ||
            first[3].opBits != MicroOpBits::B8 || second[3].opBits != MicroOpBits::B8 ||
            !ctx.isRegDeadAfterCurrent(second[0].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({extFirstRef, extSecondRef, ref}))
            return false;

        MicroInstrOperand narrow[4] = {};
        narrow[0].reg               = second[0].reg;
        narrow[1].reg               = first[0].reg;
        narrow[2].opBits            = MicroOpBits::B8;
        narrow[3].microOp           = binary[3].microOp;
        MicroInstrOperand extend[4] = {};
        extend[0].reg               = first[0].reg;
        extend[1].reg               = second[0].reg;
        extend[2].opBits            = binary[2].opBits;
        extend[3].opBits            = MicroOpBits::B8;
        ctx.emitRewrite(extFirstRef, MicroInstrOpcode::OpBinaryRegReg, narrow);
        ctx.emitRewrite(extSecondRef, MicroInstrOpcode::LoadZeroExtRegReg, extend);
        ctx.emitErase(ref);
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
        if (!findCarryBoolean(ctx, ref, value))
        {
            if (!findZeroBoolean(ctx, ref, value) || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
                return false;
            const MicroInstr* compare = ctx.instruction(value.compareRef);
            const auto*       cmpOps  = compare->ops(*ctx.operands);
            MicroInstrOperand compareOne[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
            compareOne[2].valueU64           = 1;
            MicroInstrOperand add[3]         = {};
            add[0].reg                       = ops[0].reg;
            add[1].opBits                    = bits;
            add[2].valueU64                  = offset;
            ctx.emitRewrite(value.compareRef, compare->op, compareOne, true);
            ctx.emitRewrite(value.setRef, MicroInstrOpcode::AddCarryRegImm, add);
            ctx.emitErase(ref);
            return true;
        }
        if (value.inverse || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
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

    // A selection between x and -x can use the flags from NEG itself.
    // At INT_MIN both choices are identical, so NEG overflow does not change
    // either absolute-value result, including its wrapped negative form.
    bool tryReuseNegationForSignSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* select = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !select || !select[0].reg.isInt() || !select[1].reg.isInt() ||
            select[0].reg == select[1].reg || ctx.isPrivateFrameBase(select[0].reg) ||
            (select[3].opBits != MicroOpBits::B32 && select[3].opBits != MicroOpBits::B64))
            return false;
        const MicroCond condition = select[2].cpuCond;
        if (condition != MicroCond::GreaterOrEqual && condition != MicroCond::Greater &&
            condition != MicroCond::Less && condition != MicroCond::LessOrEqual)
            return false;
        const MicroInstrRef compareRef = ctx.previousRef(ref);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        if (!compare || compare->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmp = compare->ops(*ctx.operands);
        if (!cmp || cmp[0].reg != select[1].reg || cmp[1].opBits != select[3].opBits ||
            cmp[2].hasWideImmediateValue() || cmp[2].valueU64 != 0)
            return false;
        const MicroInstrRef negateRef = ctx.previousRef(compareRef);
        const MicroInstr*   negate    = ctx.instruction(negateRef);
        if (!negate || negate->op != MicroInstrOpcode::OpUnaryReg)
            return false;
        const auto* neg = negate->ops(*ctx.operands);
        if (!neg || neg[0].reg != select[0].reg || neg[1].opBits != select[3].opBits || neg[2].microOp != MicroOp::Negate)
            return false;
        const MicroInstrRef copyRef = ctx.previousRef(negateRef);
        const MicroInstr*   copy    = ctx.instruction(copyRef);
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* copied = copy->ops(*ctx.operands);
        if (!copied || copied[0].reg != select[0].reg || copied[1].reg != select[1].reg || copied[2].opBits != select[3].opBits ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({copyRef, negateRef, compareRef, ref}))
            return false;
        MicroInstrOperand rewritten[4] = {select[0], select[1], select[2], select[3]};
        rewritten[2].cpuCond           = condition == MicroCond::GreaterOrEqual || condition == MicroCond::Greater ? MicroCond::Sign : MicroCond::Greater;
        ctx.emitRewrite(ref, inst.op, rewritten);
        ctx.emitErase(compareRef);
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
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
        {
            cmpRef       = ctx.previousRef(ref);
            cmp          = ctx.instruction(cmpRef);
            compareFirst = true;
        }
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
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
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
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
        if (isCompareInstruction(cmp->op))
        {
            if (!canMoveComparisonForSelect(*cmp, cmpOps))
                return false;
        }
        else
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

    bool tryUseTestForDeadMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || ops[2].microOp != MicroOp::And || !ops[0].reg.isInt() ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64) ||
            ops[3].hasWideImmediateValue() || ops[3].valueU64 > 0x7F ||
            ctx.isPrivateFrameBase(ops[0].reg) || !ctx.isRegDeadAfterCurrent(ops[0].reg))
            return false;

        // With bit 7 clear, both widths produce SF=0 and the same ZF/PF;
        // AND and TEST also clear CF/OF. No result value survives the mask.
        MicroInstrOperand test[3] = {};
        test[0]                   = ops[0];
        test[1].opBits            = MicroOpBits::B8;
        test[2]                   = ops[3];
        MicroInstr probe          = inst;
        probe.op                  = MicroInstrOpcode::TestRegImm;
        probe.numOperands         = 3;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, test)) || !ctx.claimAll({ref}))
            return false;
        ctx.emitRewrite(ref, probe.op, test);
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

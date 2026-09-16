#include "pch.h"
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

    // Zero the full result before the compare instead of extending SETcc's
    // byte afterward. The compare must not read that result register.
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
        // Register compares have no immediate/relocation binding to move.
        if (!cmp || cmp->op != MicroInstrOpcode::CmpRegReg)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || !cmpOps[0].reg.isInt() || !cmpOps[1].reg.isInt())
            return false;
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

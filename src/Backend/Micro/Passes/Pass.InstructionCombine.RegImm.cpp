#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// OpBinaryRegImm combiner: identity / absorbing element / reassociation.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        bool emitClearReg(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits)
        {
            if (!ctx.claimAll({ref}))
                return false;
            MicroInstrOperand clearOps[2];
            clearOps[0].reg    = dst;
            clearOps[1].opBits = opBits;
            ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
            return true;
        }

        bool emitLoadRegImm(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits, uint64_t value)
        {
            if (!ctx.claimAll({ref}))
                return false;
            MicroInstrOperand loadOps[3];
            loadOps[0].reg      = dst;
            loadOps[1].opBits   = opBits;
            loadOps[2].valueU64 = value;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegImm, loadOps);
            return true;
        }

        bool tryReassociateWithPrevious(Context& ctx, MicroInstrRef ref, MicroReg dst, MicroOpBits opBits, MicroOp op, uint64_t imm)
        {
            const auto reaching = ctx.ssa->reachingDef(dst, ref);
            if (!reaching.valid() || reaching.isPhi || !reaching.inst)
                return false;
            if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* prevOps = reaching.inst->ops(*ctx.operands);
            if (!prevOps || prevOps[0].reg != dst || !isSameOpBitsInt(prevOps[1].opBits, opBits))
                return false;

            const auto* valueInfo = ctx.ssa->valueInfo(reaching.valueId);
            if (!valueInfo || valueInfo->uses.size() != 1)
                return false;

            auto     combinedOp  = MicroOp::Add;
            uint64_t combinedImm = 0;
            if (!tryReassociate(prevOps[2].microOp, prevOps[3].valueU64, op, imm, opBits, combinedOp, combinedImm))
                return false;
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref))
                return false;

            if (!ctx.claimAll({ref, reaching.instRef}))
                return false;

            MicroInstrOperand rewritten[4];
            rewritten[0].reg      = dst;
            rewritten[1].opBits   = opBits;
            rewritten[2].microOp  = combinedOp;
            rewritten[3].valueU64 = combinedImm;
            ctx.emitRewrite(reaching.instRef, MicroInstrOpcode::OpBinaryRegImm, rewritten);
            ctx.emitErase(ref);
            return true;
        }
    }

    bool tryOpBinaryRegImm(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt())
            return false;

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[1].opBits;
        const MicroOp     op     = ops[2].microOp;
        const uint64_t    imm    = ops[3].valueU64;

        if (isRightIdentity(op, opBits, imm) && ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
        {
            if (!ctx.claimAll({ref}))
                return false;
            ctx.emitErase(ref);
            return true;
        }

        uint64_t absorbed = 0;
        if (isRightAbsorbing(op, opBits, imm, absorbed))
        {
            if (absorbed == 0)
                return emitClearReg(ctx, ref, dst, opBits);
            return emitLoadRegImm(ctx, ref, dst, opBits, absorbed);
        }

        if (!ctx.ssa)
            return false;

        return tryReassociateWithPrevious(ctx, ref, dst, opBits, op, imm);
    }

    // (x & C) << s  ==  x << s   when the low (width - s) bits of C are all set.
    //
    // Those low bits are exactly the ones the left shift keeps; every bit the
    // mask clears is shifted out anyway, so the AND is dead. Frontends emit this
    // shape whenever source masks a value before a left shift (e.g. wrap-safe
    // arithmetic). The AND (and its materialized mask constant, removed later by
    // DCE) is pure overhead the shift makes redundant. Anchored on the shift.
    bool tryFoldRedundantMaskBeforeShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroOp op = ops[2].microOp;
        if (op != MicroOp::ShiftLeft && op != MicroOp::ShiftArithmeticLeft)
            return false;

        const MicroReg dst = ops[0].reg;
        if (!dst.isVirtualInt())
            return false;

        const MicroOpBits opBits = ops[1].opBits;
        const unsigned    width  = static_cast<uint8_t>(opBits);
        if (width == 0 || width > 64)
            return false;

        const uint64_t shift = ops[3].valueU64;
        if (shift == 0 || shift >= width)
            return false;

        const unsigned keptBits = width - static_cast<unsigned>(shift);
        const uint64_t keptMask = keptBits >= 64 ? ~0ull : ((1ull << keptBits) - 1);

        // Walk back from the shifted register to the AND that produced it. The
        // value typically reaches the shift through one or more value-preserving
        // copies (the builder materializes each step into a fresh temp), so the
        // AND is rarely the direct reaching def. Every hop must be single-use so
        // that dropping the mask cannot perturb another consumer.
        // Exactly one real instruction consumer (dead loop-header phis ignored, as
        // in tryFuseInPlaceUpdate) so dropping the mask cannot perturb anyone else.
        const auto singleRealUse = [&](MicroReg reg, MicroInstrRef defRef) {
            uint32_t vId = 0;
            return ctx.ssa->defValue(reg, defRef, vId) && ctx.ssa->transitiveInstructionUseCount(vId, 2) == 1;
        };

        MicroReg      cur    = dst;
        MicroInstrRef curRef = ref;
        for (int depth = 0; depth < 8; ++depth)
        {
            const auto reach = ctx.ssa->reachingDef(cur, curRef);
            if (!reach.valid() || reach.isPhi || !reach.inst)
                return false;
            if (!singleRealUse(cur, reach.instRef))
                return false;

            const MicroInstr*        defInst = reach.inst;
            const MicroInstrOperand* defOps  = defInst->ops(*ctx.operands);
            if (!defOps)
                return false;

            // Skip a value-preserving copy `cur = src`.
            if (defInst->op == MicroInstrOpcode::LoadRegReg && defOps[0].reg == cur)
            {
                const MicroReg src = defOps[1].reg;
                if (!src.isVirtualInt() || !isSameOpBitsInt(defOps[2].opBits, opBits))
                    return false;
                cur    = src;
                curRef = reach.instRef;
                continue;
            }

            // Otherwise this must be the in-place `cur &= C` we want to drop.
            if (defOps[0].reg != cur)
                return false;

            uint64_t mask = 0;
            if (defInst->op == MicroInstrOpcode::OpBinaryRegImm)
            {
                if (defOps[2].microOp != MicroOp::And || !isSameOpBitsInt(defOps[1].opBits, opBits))
                    return false;
                mask = defOps[3].valueU64;
            }
            else if (defInst->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                if (defOps[3].microOp != MicroOp::And || !isSameOpBitsInt(defOps[2].opBits, opBits))
                    return false;
                const MicroReg maskReg = defOps[1].reg;
                if (!maskReg.isVirtualInt())
                    return false;
                const auto reachMask = ctx.ssa->reachingDef(maskReg, reach.instRef);
                if (!reachMask.valid() || reachMask.isPhi || !reachMask.inst || reachMask.inst->op != MicroInstrOpcode::LoadRegImm)
                    return false;
                const MicroInstrOperand* maskOps = reachMask.inst->ops(*ctx.operands);
                if (!maskOps)
                    return false;
                mask = maskOps[2].valueU64;
            }
            else
                return false;

            if ((mask & keptMask) != keptMask)
                return false;

            // The AND's flag write must be dead (the shift redefines flags).
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reach.instRef))
                return false;

            // Drop the AND; `cur` keeps its pre-mask value, which the shift needs.
            if (!ctx.claimAll({reach.instRef}))
                return false;
            ctx.emitErase(reach.instRef);
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();

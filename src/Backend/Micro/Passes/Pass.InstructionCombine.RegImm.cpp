#include "pch.h"
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

            MicroOp  combinedOp  = MicroOp::Add;
            uint64_t combinedImm = 0;
            if (!tryReassociate(prevOps[2].microOp, prevOps[3].valueU64, op, imm, opBits, combinedOp, combinedImm))
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
}

SWC_END_NAMESPACE();

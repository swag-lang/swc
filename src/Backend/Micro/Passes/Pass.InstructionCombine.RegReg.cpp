#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// OpBinaryRegReg combiner: idempotent self-ops (v op v).

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    bool tryOpBinaryRegReg(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[0].reg != ops[1].reg || !ops[0].reg.isVirtualInt())
            return false;

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[2].opBits;
        const MicroOp     op     = ops[3].microOp;

        switch (op)
        {
            case MicroOp::And:
            case MicroOp::Or:
                // v op v == v. Rewriting to a self-copy buys nothing pre-RA,
                // so only drop when the result is unused afterward.
                if (ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
                {
                    if (!ctx.claimAll({ref}))
                        return false;
                    ctx.emitErase(ref);
                    return true;
                }
                return false;

            case MicroOp::Subtract:
            case MicroOp::Xor:
            {
                if (!ctx.claimAll({ref}))
                    return false;
                MicroInstrOperand clearOps[2];
                clearOps[0].reg    = dst;
                clearOps[1].opBits = opBits;
                ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
                return true;
            }

            default:
                return false;
        }
    }
}

SWC_END_NAMESPACE();

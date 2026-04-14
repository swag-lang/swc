#include "pch.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    bool tryForwardCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg copyDst = copyOps[0].reg;
        const MicroReg copySrc = copyOps[1].reg;
        if (copyDst == copySrc || !copyDst.isVirtual() || !copySrc.isVirtual() || !copyDst.isSameClass(copySrc))
            return false;

        const MicroInstrRef consumerRef = ctx.nextRef(copyRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        Action rewrite;
        if (!buildUseOnlyRegRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), copyDst, copySrc))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        rewrite.ref = consumerRef;
        ctx.actions.push_back(rewrite);
        return true;
    }
}

SWC_END_NAMESPACE();

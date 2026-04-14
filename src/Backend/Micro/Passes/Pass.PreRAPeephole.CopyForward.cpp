#include "pch.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        std::array<MicroInstrRegMode, 3> resolveRegModes(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            const MicroInstrDef& info  = MicroInstr::info(inst.op);
            auto                 modes = info.regModes;
            if (!ops)
                return modes;

            switch (info.special)
            {
                case MicroInstrRegSpecial::OpBinaryRegReg:
                    if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                    {
                        modes[0] = MicroInstrRegMode::UseDef;
                        modes[1] = MicroInstrRegMode::UseDef;
                    }
                    break;

                case MicroInstrRegSpecial::OpBinaryMemReg:
                    if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                        modes[1] = MicroInstrRegMode::UseDef;
                    break;

                default:
                    break;
            }

            return modes;
        }

        bool buildRewrite(Action& outAction, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg copyDst, MicroReg copySrc)
        {
            if (!ops || consumer.numOperands == 0 || consumer.numOperands > Action::K_MAX_OPS)
                return false;

            outAction.newOp  = consumer.op;
            outAction.numOps = consumer.numOperands;
            for (uint8_t idx = 0; idx < consumer.numOperands; ++idx)
                outAction.ops[idx] = ops[idx];

            bool       changed = false;
            const auto modes   = resolveRegModes(consumer, ops);
            for (size_t idx = 0; idx < modes.size() && idx < consumer.numOperands; ++idx)
            {
                if (modes[idx] != MicroInstrRegMode::Use)
                    continue;
                if (outAction.ops[idx].reg != copyDst)
                    continue;

                outAction.ops[idx].reg = copySrc;
                changed                = true;
            }

            return changed;
        }
    }

    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3 || ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg copyDst = copyOps[0].reg;
        const MicroReg copySrc = copyOps[1].reg;
        if (!copyDst.isVirtual() || !copySrc.isVirtual() || !copyDst.isSameClass(copySrc))
            return false;

        const MicroInstrRef consumerRef = ctx.nextRef(copyRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        Action rewrite;
        if (!buildRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), copyDst, copySrc))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        rewrite.ref = consumerRef;
        ctx.actions.push_back(rewrite);
        return true;
    }
}

SWC_END_NAMESPACE();

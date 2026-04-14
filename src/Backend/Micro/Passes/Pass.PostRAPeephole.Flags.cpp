#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRAPeephole
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
            if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags) ||
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

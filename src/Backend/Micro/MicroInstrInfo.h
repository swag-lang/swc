#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstrInfo
{
    inline bool isTerminatorInstruction(const MicroInstr& inst)
    {
        return MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::TerminatorInstruction);
    }

    inline bool isUnconditionalJumpInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (!info.flags.has(MicroInstrFlagsE::JumpInstruction))
            return false;
        if (info.flags.has(MicroInstrFlagsE::ConditionalJump))
            return ops && ops[0].cpuCond == MicroCond::Unconditional;
        return true;
    }

    inline bool hasObservableSideEffect(const MicroInstr& inst)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        return inst.op == MicroInstrOpcode::Label ||
               info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
               info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
               info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
               info.flags.has(MicroInstrFlagsE::WritesMemory) ||
               info.flags.has(MicroInstrFlagsE::DefinesCpuFlags);
    }

    inline bool isLocalDataflowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef)
    {
        return inst.op == MicroInstrOpcode::Label || useDef.isCall || isTerminatorInstruction(inst);
    }
}

SWC_END_NAMESPACE();

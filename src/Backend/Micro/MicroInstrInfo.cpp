#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"

SWC_BEGIN_NAMESPACE();

bool MicroInstrInfo::isTerminatorInstruction(const MicroInstr& inst)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    return info.flags.has(MicroInstrFlagsE::TerminatorInstruction);
}

bool MicroInstrInfo::isUnconditionalJumpInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    if (!info.flags.has(MicroInstrFlagsE::JumpInstruction))
        return false;

    if (info.flags.has(MicroInstrFlagsE::ConditionalJump))
        return ops && ops[0].cpuCond == MicroCond::Unconditional;

    return true;
}

bool MicroInstrInfo::isLocalDataflowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef)
{
    if (inst.op == MicroInstrOpcode::Label)
        return true;
    if (useDef.isCall || isTerminatorInstruction(inst))
        return true;
    return false;
}

bool MicroInstrInfo::usesCpuFlags(const MicroInstr& inst)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    return info.flags.has(MicroInstrFlagsE::UsesCpuFlags);
}

bool MicroInstrInfo::definesCpuFlags(const MicroInstr& inst)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    return info.flags.has(MicroInstrFlagsE::DefinesCpuFlags);
}

bool MicroInstrInfo::getMemBaseOffsetOperandIndices(uint8_t& outBaseIndex, uint8_t& outOffsetIndex, const MicroInstr& inst)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    if (!info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return false;

    outBaseIndex   = info.memBaseOperandIndex;
    outOffsetIndex = info.memOffsetOperandIndex;
    return true;
}

SWC_END_NAMESPACE();

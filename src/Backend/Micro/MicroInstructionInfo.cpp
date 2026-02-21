#include "pch.h"
#include "Backend/Micro/MicroInstructionInfo.h"

SWC_BEGIN_NAMESPACE();

bool MicroInstructionInfo::isTerminatorInstruction(const MicroInstr& inst)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::JumpCond:
        case MicroInstrOpcode::JumpCondImm:
        case MicroInstrOpcode::JumpReg:
        case MicroInstrOpcode::JumpTable:
        case MicroInstrOpcode::Ret:
            return true;
        default:
            return false;
    }
}

bool MicroInstructionInfo::isSameRegisterClass(MicroReg leftReg, MicroReg rightReg)
{
    if (leftReg.isInt() && rightReg.isInt())
        return true;
    if (leftReg.isFloat() && rightReg.isFloat())
        return true;
    if (leftReg.isVirtualInt() && rightReg.isVirtualInt())
        return true;
    if (leftReg.isVirtualFloat() && rightReg.isVirtualFloat())
        return true;
    return false;
}

bool MicroInstructionInfo::isLocalDataflowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef)
{
    if (inst.op == MicroInstrOpcode::Label)
        return true;
    if (useDef.isCall || isTerminatorInstruction(inst))
        return true;
    return false;
}

SWC_END_NAMESPACE();

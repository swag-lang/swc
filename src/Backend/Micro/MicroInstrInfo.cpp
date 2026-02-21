#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"

SWC_BEGIN_NAMESPACE();

bool MicroInstrInfo::isTerminatorInstruction(const MicroInstr& inst)
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

bool MicroInstrInfo::isUnconditionalJumpInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!ops)
        return false;

    if (inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm)
        return ops[0].cpuCond == MicroCond::Unconditional;
    if (inst.op == MicroInstrOpcode::JumpReg || inst.op == MicroInstrOpcode::JumpTable)
        return true;
    return false;
}

bool MicroInstrInfo::isSameRegisterClass(MicroReg leftReg, MicroReg rightReg)
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
    switch (inst.op)
    {
        case MicroInstrOpcode::JumpCond:
        case MicroInstrOpcode::JumpCondImm:
        case MicroInstrOpcode::SetCondReg:
        case MicroInstrOpcode::LoadCondRegReg:
            return true;
        default:
            return false;
    }
}

bool MicroInstrInfo::definesCpuFlags(const MicroInstr& inst)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::CmpRegReg:
        case MicroInstrOpcode::CmpRegZero:
        case MicroInstrOpcode::CmpRegImm:
        case MicroInstrOpcode::CmpMemReg:
        case MicroInstrOpcode::CmpMemImm:
        case MicroInstrOpcode::ClearReg:
        case MicroInstrOpcode::OpUnaryMem:
        case MicroInstrOpcode::OpUnaryReg:
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::OpBinaryRegImm:
        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryMemReg:
        case MicroInstrOpcode::OpBinaryMemImm:
            return true;
        default:
            return false;
    }
}

bool MicroInstrInfo::getMemBaseOffsetOperandIndices(uint8_t& outBaseIndex, uint8_t& outOffsetIndex, const MicroInstr& inst)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegMem:
            outBaseIndex   = 1;
            outOffsetIndex = 3;
            return true;
        case MicroInstrOpcode::LoadMemReg:
            outBaseIndex   = 0;
            outOffsetIndex = 3;
            return true;
        case MicroInstrOpcode::LoadMemImm:
            outBaseIndex   = 0;
            outOffsetIndex = 2;
            return true;
        case MicroInstrOpcode::LoadSignedExtRegMem:
            outBaseIndex   = 1;
            outOffsetIndex = 4;
            return true;
        case MicroInstrOpcode::LoadZeroExtRegMem:
            outBaseIndex   = 1;
            outOffsetIndex = 4;
            return true;
        case MicroInstrOpcode::LoadAddrRegMem:
            outBaseIndex   = 1;
            outOffsetIndex = 3;
            return true;
        case MicroInstrOpcode::CmpMemReg:
            outBaseIndex   = 0;
            outOffsetIndex = 3;
            return true;
        case MicroInstrOpcode::CmpMemImm:
            outBaseIndex   = 0;
            outOffsetIndex = 2;
            return true;
        case MicroInstrOpcode::OpUnaryMem:
            outBaseIndex   = 0;
            outOffsetIndex = 3;
            return true;
        case MicroInstrOpcode::OpBinaryRegMem:
            outBaseIndex   = 1;
            outOffsetIndex = 4;
            return true;
        case MicroInstrOpcode::OpBinaryMemReg:
            outBaseIndex   = 0;
            outOffsetIndex = 4;
            return true;
        case MicroInstrOpcode::OpBinaryMemImm:
            outBaseIndex   = 0;
            outOffsetIndex = 3;
            return true;
        default:
            return false;
    }
}

SWC_END_NAMESPACE();

#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstructionInfo
{
    bool isTerminatorInstruction(const MicroInstr& inst);
    bool isSameRegisterClass(MicroReg leftReg, MicroReg rightReg);
    bool isLocalDataflowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef);
}

SWC_END_NAMESPACE();

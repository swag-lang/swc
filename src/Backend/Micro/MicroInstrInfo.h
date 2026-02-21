#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstrInfo
{
    bool isTerminatorInstruction(const MicroInstr& inst);
    bool isUnconditionalJumpInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool isLocalDataflowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef);
    bool usesCpuFlags(const MicroInstr& inst);
    bool definesCpuFlags(const MicroInstr& inst);
    bool getMemBaseOffsetOperandIndices(uint8_t& outBaseIndex, uint8_t& outOffsetIndex, const MicroInstr& inst);
}

SWC_END_NAMESPACE();

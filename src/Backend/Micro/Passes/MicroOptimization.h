#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace MicroOptimization
{
    bool isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
}

SWC_END_NAMESPACE();

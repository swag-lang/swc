#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroOptimization
{
    bool isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
}

SWC_END_NAMESPACE();

#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroPassHelpers
{
    bool violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
}

SWC_END_NAMESPACE();

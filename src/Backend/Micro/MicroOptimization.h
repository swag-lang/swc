#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroOptimization
{
    uint64_t normalizeToOpBits(uint64_t value, MicroOpBits opBits);
    bool     foldBinaryImmediate(uint64_t& outValue, uint64_t inValue, uint64_t immediate, MicroOp microOp, MicroOpBits opBits);
    bool     isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool     violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
}

SWC_END_NAMESPACE();

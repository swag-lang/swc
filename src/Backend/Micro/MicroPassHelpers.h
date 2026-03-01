#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Support/Core/Result.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroPassHelpers
{
    uint64_t         normalizeToOpBits(uint64_t value, MicroOpBits opBits);
    int64_t          toSignedValue(uint64_t value, MicroOpBits opBits);
    std::optional<bool> evaluateCondition(MicroCond condition, uint64_t lhs, uint64_t rhs, MicroOpBits opBits);
    bool             tryFoldAddSubSignedNoOverflow(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits);
    bool             isAddOrSubMicroOp(MicroOp op);
    Math::FoldStatus foldBinaryImmediate(uint64_t& outValue, uint64_t inValue, uint64_t immediate, MicroOp microOp, MicroOpBits opBits);
    Result           raiseFoldSafetyError(const MicroPassContext& context, MicroInstrRef instructionRef, Math::FoldStatus status);
    bool             isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool             violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
}

SWC_END_NAMESPACE();

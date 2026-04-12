#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/Result.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroPassHelpers
{
    bool violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);

    // Replace all uses of 'fromReg' with 'toReg' in instructions after 'afterInstRef',
    // within the same local flow region (stops at redefinition of either register, calls,
    // labels, branches). Returns the number of uses replaced.
    uint32_t replaceRegInLocalUses(MicroStorage&        storage,
                                   MicroOperandStorage& operands,
                                   MicroInstrRef        afterInstRef,
                                   MicroReg             fromReg,
                                   MicroReg             toReg);

    // Fold a binary integer operation on two immediate values.
    // Maps MicroOp to Math::FoldBinaryOp and delegates to Math::foldBinaryInt.
    // Returns Math::FoldStatus::Unsupported if the MicroOp has no fold mapping.
    Math::FoldStatus foldBinaryImmediate(uint64_t&   outValue,
                                         uint64_t    lhs,
                                         uint64_t    rhs,
                                         MicroOp     op,
                                         MicroOpBits opBits);
}

SWC_END_NAMESPACE();

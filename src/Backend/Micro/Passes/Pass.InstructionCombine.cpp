#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Support/Memory/MemoryProfile.h"

// Combines nearby immediate ops on the same destination into one op.
// Example: add r1, 2; add r1, 3  ->  add r1, 5.
// Example: xor r1, 7; xor r1, 7  ->  <remove both or replace with no-op>.
// Looks through intervening instructions that don't touch the target register.

SWC_BEGIN_NAMESPACE();

namespace
{
    void canonicalizeAddSubImmediate(MicroOp& outOp, uint64_t& outValue, const MicroOpBits opBits)
    {
        outValue = MicroPassHelpers::normalizeToOpBits(outValue, opBits);
        if (outValue == 0)
        {
            outOp = MicroOp::Add;
            return;
        }

        const uint32_t numBits = getNumBits(opBits);
        if (!numBits)
        {
            outOp = MicroOp::Add;
            return;
        }

        const uint64_t signBitMask = static_cast<uint64_t>(1) << (numBits - 1);
        if (!(outValue & signBitMask))
        {
            outOp = MicroOp::Add;
            return;
        }

        outOp    = MicroOp::Subtract;
        outValue = MicroPassHelpers::normalizeToOpBits((~outValue) + 1, opBits);
    }

    bool combineArithmetic(MicroOp& outOp, uint64_t& outValue, MicroOp firstOp, uint64_t firstValue, MicroOp secondOp, uint64_t secondValue, MicroOpBits opBits)
    {
        const bool firstArithmetic  = firstOp == MicroOp::Add || firstOp == MicroOp::Subtract;
        const bool secondArithmetic = secondOp == MicroOp::Add || secondOp == MicroOp::Subtract;
        if (!firstArithmetic || !secondArithmetic)
            return false;

        uint64_t combined = 0;
        combined          = firstOp == MicroOp::Add ? combined + firstValue : combined - firstValue;
        combined          = secondOp == MicroOp::Add ? combined + secondValue : combined - secondValue;
        outValue          = combined;
        canonicalizeAddSubImmediate(outOp, outValue, opBits);
        return true;
    }

    bool combineBitwise(MicroOp& outOp, uint64_t& outValue, MicroOp firstOp, uint64_t firstValue, MicroOp secondOp, uint64_t secondValue, MicroOpBits opBits)
    {
        if (firstOp != secondOp)
            return false;

        switch (firstOp)
        {
            case MicroOp::And:
                outOp    = MicroOp::And;
                outValue = MicroPassHelpers::normalizeToOpBits(firstValue & secondValue, opBits);
                return true;
            case MicroOp::Or:
                outOp    = MicroOp::Or;
                outValue = MicroPassHelpers::normalizeToOpBits(firstValue | secondValue, opBits);
                return true;
            case MicroOp::Xor:
                outOp    = MicroOp::Xor;
                outValue = MicroPassHelpers::normalizeToOpBits(firstValue ^ secondValue, opBits);
                return true;
            default:
                return false;
        }
    }

    bool combineShift(MicroOp& outOp, uint64_t& outValue, MicroOp firstOp, uint64_t firstValue, MicroOp secondOp, uint64_t secondValue, MicroOpBits opBits)
    {
        if (firstOp != secondOp)
            return false;

        if (firstOp != MicroOp::ShiftLeft &&
            firstOp != MicroOp::ShiftRight &&
            firstOp != MicroOp::ShiftArithmeticRight)
        {
            return false;
        }

        const uint32_t numBits = getNumBits(opBits);
        if (!numBits)
            return false;

        const uint64_t maxShift = numBits - 1;
        const uint64_t sumShift = firstValue + secondValue;

        outOp    = firstOp;
        outValue = std::min(sumShift, maxShift);
        return true;
    }

    bool combineImmediateOperations(MicroOp& outOp, uint64_t& outValue, MicroOp firstOp, uint64_t firstValue, MicroOp secondOp, uint64_t secondValue, MicroOpBits opBits)
    {
        if (combineArithmetic(outOp, outValue, firstOp, firstValue, secondOp, secondValue, opBits))
            return true;

        if (combineBitwise(outOp, outValue, firstOp, firstValue, secondOp, secondValue, opBits))
            return true;

        if (combineShift(outOp, outValue, firstOp, firstValue, secondOp, secondValue, opBits))
            return true;

        return false;
    }
}

Result MicroInstructionCombinePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/InstCombine");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const MicroInstr& first = *it;
        if (first.op != MicroInstrOpcode::OpBinaryRegImm)
        {
            ++it;
            continue;
        }

        MicroInstrOperand* firstOps   = first.ops(operands);
        const MicroReg     targetReg  = firstOps[0].reg;
        const MicroOpBits  targetBits = firstOps[1].opBits;

        // Search forward for the next OpBinaryRegImm on the same register,
        // skipping instructions that don't touch it.
        constexpr uint32_t kMaxLookahead = 8;
        uint32_t           lookahead     = 0;
        bool               combined      = false;
        auto               scanIt        = it;
        ++scanIt;

        for (; scanIt != storage.view().end() && lookahead < kMaxLookahead; ++scanIt, ++lookahead)
        {
            const MicroInstr& candidate = *scanIt;

            // Found a combinable instruction.
            if (candidate.op == MicroInstrOpcode::OpBinaryRegImm)
            {
                const MicroInstrOperand* candidateOps = candidate.ops(operands);
                if (candidateOps[0].reg == targetReg && candidateOps[1].opBits == targetBits)
                {
                    MicroOp  combinedOp    = firstOps[2].microOp;
                    uint64_t combinedValue = firstOps[3].valueU64;
                    if (combineImmediateOperations(combinedOp, combinedValue, firstOps[2].microOp, firstOps[3].valueU64, candidateOps[2].microOp, candidateOps[3].valueU64, targetBits))
                    {
                        firstOps[2].microOp  = combinedOp;
                        firstOps[3].valueU64 = combinedValue;
                        storage.erase(scanIt.current);
                        context.passChanged = true;
                        combined            = true;
                    }
                    break;
                }
            }

            // Stop if the intervening instruction touches our target register.
            const MicroInstrUseDef useDef = candidate.collectUseDef(operands, context.encoder);
            if (MicroPassHelpers::touchesReg(useDef, targetReg))
                break;

            // Stop at control flow barriers.
            if (MicroInstrInfo::isLocalDataflowBarrier(candidate, useDef))
                break;
        }

        if (!combined)
            ++it;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Backend/Micro/Passes/MicroInstructionCombinePass.h"

// Combines consecutive immediate ops on the same destination into one op.
// Example: add r1, 2; add r1, 3  ->  add r1, 5.
// Example: xor r1, 7; xor r1, 7  ->  <remove both or replace with no-op>.
// This reduces instruction count and pressure on later passes.

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t normalizeToOpBits(uint64_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B64)
            return value;

        const uint64_t mask = getOpBitsMask(opBits);
        return value & mask;
    }

    bool combineArithmetic(MicroOp& outOp, uint64_t& outValue, MicroOp firstOp, uint64_t firstValue, MicroOp secondOp, uint64_t secondValue, MicroOpBits opBits)
    {
        const bool firstArithmetic  = firstOp == MicroOp::Add || firstOp == MicroOp::Subtract;
        const bool secondArithmetic = secondOp == MicroOp::Add || secondOp == MicroOp::Subtract;
        if (!firstArithmetic || !secondArithmetic)
            return false;

        uint64_t combined = 0;
        combined = firstOp == MicroOp::Add ? combined + firstValue : combined - firstValue;
        combined = secondOp == MicroOp::Add ? combined + secondValue : combined - secondValue;
        combined = normalizeToOpBits(combined, opBits);

        outOp    = MicroOp::Add;
        outValue = combined;
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
                outValue = normalizeToOpBits(firstValue & secondValue, opBits);
                return true;
            case MicroOp::Or:
                outOp    = MicroOp::Or;
                outValue = normalizeToOpBits(firstValue | secondValue, opBits);
                return true;
            case MicroOp::Xor:
                outOp    = MicroOp::Xor;
                outValue = normalizeToOpBits(firstValue ^ secondValue, opBits);
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

bool MicroInstructionCombinePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                 changed  = false;
    MicroStorage&        storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        MicroInstr& first = *it;
        if (first.op != MicroInstrOpcode::OpBinaryRegImm)
        {
            ++it;
            continue;
        }

        auto nextIt = it;
        ++nextIt;
        if (nextIt == storage.view().end())
        {
            ++it;
            continue;
        }

        MicroInstr& second = *nextIt;
        if (second.op != MicroInstrOpcode::OpBinaryRegImm)
        {
            ++it;
            continue;
        }

        MicroInstrOperand* firstOps  = first.ops(operands);
        MicroInstrOperand* secondOps = second.ops(operands);
        if (firstOps[0].reg != secondOps[0].reg || firstOps[1].opBits != secondOps[1].opBits)
        {
            ++it;
            continue;
        }

        MicroOp  combinedOp    = firstOps[2].microOp;
        uint64_t combinedValue = firstOps[3].valueU64;
        if (!combineImmediateOperations(combinedOp, combinedValue, firstOps[2].microOp, firstOps[3].valueU64, secondOps[2].microOp, secondOps[3].valueU64, firstOps[1].opBits))
        {
            ++it;
            continue;
        }

        firstOps[2].microOp  = combinedOp;
        firstOps[3].valueU64 = combinedValue;
        storage.erase(nextIt.current);
        changed = true;
    }

    return changed;
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA strength reduction on virtual registers.
// Replaces expensive arithmetic with cheaper equivalent forms.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool canRewriteShift(MicroOpBits opBits, uint64_t immediate)
    {
        const uint32_t bitCount = getNumBits(opBits);
        if (!bitCount)
            return false;
        if (!Math::isPowerOfTwo(immediate))
            return false;
        return Math::integerLog2(immediate) < bitCount;
    }

    bool tryReduceMultiplyToShift(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (!canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::ShiftLeft;
        ops[3].valueU64 = Math::integerLog2(immediate);
        return true;
    }

    bool tryReduceMultiplyByZero(MicroInstrOperand* ops, uint64_t immediate)
    {
        if (immediate != 0)
            return false;

        ops[2].microOp  = MicroOp::And;
        ops[3].valueU64 = 0;
        return true;
    }

    bool tryReduceMultiplyByOne(MicroInstrOperand* ops, uint64_t immediate)
    {
        if (immediate != 1)
            return false;

        ops[2].microOp  = MicroOp::Add;
        ops[3].valueU64 = 0;
        return true;
    }

    bool tryReduceAddSubZero(const MicroInstrOperand* ops, uint64_t immediate, MicroStorage& storage, MicroInstrRef instRef, const MicroSsaState* ssaState)
    {
        if (immediate != 0)
            return false;

        if (ssaState && !ssaState->isRegUsedAfter(ops[0].reg, instRef))
        {
            storage.erase(instRef);
            return true;
        }

        return false;
    }
}

Result MicroStrengthReductionPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/StrengthReduce");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);

    const auto view  = storage.view();
    const auto endIt = view.end();
    for (auto it = view.begin(); it != endIt;)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        ++it;

        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            continue;

        MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;

        if (!ops[0].reg.isAnyInt())
            continue;

        const MicroOpBits opBits    = ops[1].opBits;
        const MicroOp     microOp   = ops[2].microOp;
        const uint64_t    immediate = ops[3].valueU64;

        bool changed = false;
        switch (microOp)
        {
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                changed = tryReduceMultiplyByZero(ops, immediate) ||
                          tryReduceMultiplyByOne(ops, immediate) ||
                          tryReduceMultiplyToShift(ops, opBits, immediate);
                break;

            case MicroOp::Add:
            case MicroOp::Subtract:
                changed = tryReduceAddSubZero(ops, immediate, storage, instRef, ssaState);
                break;

            default:
                break;
        }

        if (changed)
            context.passChanged = true;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();

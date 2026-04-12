#include "pch.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroUseDefMap.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA strength reduction on virtual registers.
// Replaces expensive arithmetic with cheaper equivalent forms.
// Uses the shared UseDefMap for reaching-definition queries.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isPowerOfTwo(uint64_t value)
    {
        return value != 0 && (value & (value - 1)) == 0;
    }

    uint32_t integerLog2(uint64_t value)
    {
        SWC_ASSERT(isPowerOfTwo(value));
        uint32_t index = 0;
        while (value > 1)
        {
            value >>= 1;
            ++index;
        }

        return index;
    }

    bool canRewriteShift(MicroOpBits opBits, uint64_t immediate)
    {
        const uint32_t bitCount = getNumBits(opBits);
        if (!bitCount)
            return false;
        if (!isPowerOfTwo(immediate))
            return false;
        return integerLog2(immediate) < bitCount;
    }

    // Rewrite multiply-by-power-of-two to shift left.
    bool tryReduceMultiplyToShift(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (!canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::ShiftLeft;
        ops[3].valueU64 = integerLog2(immediate);
        return true;
    }

    // Rewrite multiply-by-zero to and-with-zero (zeroes the register).
    bool tryReduceMultiplyByZero(MicroInstrOperand* ops, uint64_t immediate)
    {
        if (immediate != 0)
            return false;

        ops[2].microOp  = MicroOp::And;
        ops[3].valueU64 = 0;
        return true;
    }

    // Rewrite multiply-by-one to add-zero (identity, removable by later passes).
    bool tryReduceMultiplyByOne(MicroInstrOperand* ops, uint64_t immediate)
    {
        if (immediate != 1)
            return false;

        ops[2].microOp  = MicroOp::Add;
        ops[3].valueU64 = 0;
        return true;
    }

    // Rewrite add/sub of zero — identity operation, removable by later passes.
    bool tryReduceAddSubZero(const MicroInstr& inst, MicroInstrOperand* ops, uint64_t immediate, MicroStorage& storage, MicroInstrRef instRef, const MicroUseDefMap* useDefMap)
    {
        if (immediate != 0)
            return false;

        // If the result is unused, erase the instruction.
        if (useDefMap && !useDefMap->isRegUsedAfter(ops[0].reg, instRef))
        {
            storage.erase(instRef);
            return true;
        }

        // Otherwise leave as add r, 0 — a no-op that later passes can remove.
        SWC_UNUSED(inst);
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
    const MicroUseDefMap* useDefMap = context.useDefMap;

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

        // Only reduce integer operations.
        if (!ops[0].reg.isInt() && !ops[0].reg.isVirtualInt())
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
                changed = tryReduceAddSubZero(inst, ops, immediate, storage, instRef, useDefMap);
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

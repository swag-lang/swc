#include "pch.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Support/Memory/MemoryProfile.h"

// Replaces expensive arithmetic with cheaper equivalent forms.
// Example: mul r1, 8 -> shl r1, 3.
// Example: div r1, 4 -> shr/sar r1, 2 (when semantics allow).
// This reduces latency and often improves code size.

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

    bool canRewriteShift(const MicroInstrOperand* ops)
    {
        const uint32_t bitCount = getNumBits(ops[1].opBits);
        if (!bitCount)
            return false;

        const uint64_t immediate = ops[3].valueU64;
        if (!isPowerOfTwo(immediate))
            return false;

        return integerLog2(immediate) < bitCount;
    }
}

Result MicroStrengthReductionPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/StrengthReduce");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroOperandStorage& operands = *context.operands;
    for (const MicroInstr& inst : context.instructions->view())
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            continue;

        MicroInstrOperand* ops = inst.ops(operands);
        if (!ops[0].reg.isInt())
            continue;

        const uint64_t immediate = ops[3].valueU64;

        switch (ops[2].microOp)
        {
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                // mul r, 0 -> and r, 0 (zero the register)
                if (immediate == 0)
                {
                    ops[2].microOp      = MicroOp::And;
                    ops[3].valueU64     = 0;
                    context.passChanged = true;
                    break;
                }
                // mul r, 1 -> add r, 0 (identity, removed by peephole)
                if (immediate == 1)
                {
                    ops[2].microOp      = MicroOp::Add;
                    ops[3].valueU64     = 0;
                    context.passChanged = true;
                    break;
                }
                if (!canRewriteShift(ops))
                    break;
                ops[2].microOp      = MicroOp::ShiftLeft;
                ops[3].valueU64     = integerLog2(ops[3].valueU64);
                context.passChanged = true;
                break;

            case MicroOp::DivideUnsigned:
                // div r, 1 -> add r, 0 (identity, removed by peephole)
                if (immediate == 1)
                {
                    ops[2].microOp      = MicroOp::Add;
                    ops[3].valueU64     = 0;
                    context.passChanged = true;
                    break;
                }
                if (!canRewriteShift(ops))
                    break;
                ops[2].microOp      = MicroOp::ShiftRight;
                ops[3].valueU64     = integerLog2(ops[3].valueU64);
                context.passChanged = true;
                break;

            case MicroOp::DivideSigned:
                // div_signed r, 1 -> add r, 0 (identity, removed by peephole)
                if (immediate == 1)
                {
                    ops[2].microOp      = MicroOp::Add;
                    ops[3].valueU64     = 0;
                    context.passChanged = true;
                }
                break;

            case MicroOp::ModuloUnsigned:
                if (!canRewriteShift(ops))
                    break;
                ops[2].microOp      = MicroOp::And;
                ops[3].valueU64     = ops[3].valueU64 - 1;
                context.passChanged = true;
                break;

            case MicroOp::ModuloSigned:
                // mod_signed r, 1 -> and r, 0 (result always 0)
                if (immediate == 1)
                {
                    ops[2].microOp      = MicroOp::And;
                    ops[3].valueU64     = 0;
                    context.passChanged = true;
                }
                break;

            default:
                break;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();

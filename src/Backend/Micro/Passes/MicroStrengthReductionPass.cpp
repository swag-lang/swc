#include "pch.h"
#include "Backend/Micro/Passes/MicroStrengthReductionPass.h"

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

bool MicroStrengthReductionPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                 changed = false;
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
    for (MicroInstr& inst : context.instructions->view())
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            continue;

        MicroInstrOperand* ops = inst.ops(operands);
        if (!ops[0].reg.isInt())
            continue;

        switch (ops[2].microOp)
        {
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                if (!canRewriteShift(ops))
                    break;
                ops[2].microOp  = MicroOp::ShiftLeft;
                ops[3].valueU64 = integerLog2(ops[3].valueU64);
                changed         = true;
                break;

            case MicroOp::DivideUnsigned:
                if (!canRewriteShift(ops))
                    break;
                ops[2].microOp  = MicroOp::ShiftRight;
                ops[3].valueU64 = integerLog2(ops[3].valueU64);
                changed         = true;
                break;

            case MicroOp::ModuloUnsigned:
                if (!canRewriteShift(ops))
                    break;
                ops[2].microOp  = MicroOp::And;
                ops[3].valueU64 = ops[3].valueU64 - 1;
                changed         = true;
                break;

            default:
                break;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();

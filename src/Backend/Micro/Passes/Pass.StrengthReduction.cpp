#include "pch.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA strength reduction on virtual registers.
//
// Rewrites OpBinaryRegImm into a cheaper form when the immediate exposes a
// pattern the target can encode in fewer / faster instructions:
//
//   v *  0    -> v &  0          (Multiply by zero  -> bitwise mask zero)
//   v *  1    -> v +  0          (Multiply by one   -> identity, dropped by InstCombine)
//   v *  pow2 -> v << log2       (Multiply by power of two -> shift left)
//   v /u pow2 -> v >> log2       (Unsigned divide by pow2 -> logical shift right)
//   v %u pow2 -> v &  (pow2-1)   (Unsigned modulo by pow2 -> bitwise mask)
//   v +/- 0   -> erase if dead   (handled defensively; InstCombine also matches it)
//
// Signed division/modulo by a power of two is intentionally NOT reduced here:
// the correct lowering needs a sign-bias step (`sar+sub`) that is not strictly
// cheaper than the original idiv on modern hardware and is better expressed by
// the legalizer.

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

    bool tryReduceUnsignedDivideToShift(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (immediate == 0 || !canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::ShiftRight;
        ops[3].valueU64 = Math::integerLog2(immediate);
        return true;
    }

    bool tryReduceUnsignedModuloToMask(MicroInstrOperand* ops, MicroOpBits opBits, uint64_t immediate)
    {
        if (immediate == 0 || !canRewriteShift(opBits, immediate))
            return false;

        ops[2].microOp  = MicroOp::And;
        ops[3].valueU64 = immediate - 1;
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

            case MicroOp::DivideUnsigned:
                changed = tryReduceUnsignedDivideToShift(ops, opBits, immediate);
                break;

            case MicroOp::ModuloUnsigned:
                changed = tryReduceUnsignedModuloToMask(ops, opBits, immediate);
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

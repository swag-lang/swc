#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        bool isFoldableImmediateBits(const MicroOpBits bits)
        {
            return bits != MicroOpBits::Zero && bits != MicroOpBits::B128;
        }

        bool buildAdjacentRegImmRewrite(Action& out, const MicroInstr& firstInst, const MicroInstrOperand* firstOps, const MicroInstr& secondInst, const MicroInstrOperand* secondOps)
        {
            if (!firstOps || !secondOps)
                return false;
            if (firstInst.op != MicroInstrOpcode::OpBinaryRegImm || secondInst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;
            if (firstOps[3].hasWideImmediateValue() || secondOps[3].hasWideImmediateValue())
                return false;

            const MicroReg reg = firstOps[0].reg;
            if (!reg.isVirtualInt() || secondOps[0].reg != reg)
                return false;
            if (firstOps[1].opBits != secondOps[1].opBits || !isFoldableImmediateBits(firstOps[1].opBits))
                return false;

            auto     combinedOp  = MicroOp::Add;
            uint64_t combinedImm = 0;
            if (!MicroPassHelpers::tryReassociateBinaryImmediate(firstOps[2].microOp, firstOps[3].valueU64, secondOps[2].microOp, secondOps[3].valueU64, firstOps[1].opBits, combinedOp, combinedImm))
                return false;

            out.newOp  = MicroInstrOpcode::OpBinaryRegImm;
            out.numOps = 4;
            for (uint8_t idx = 0; idx < out.numOps; ++idx)
                out.ops[idx] = firstOps[idx];
            out.ops[2].microOp = combinedOp;
            setMaskedImmediateValue(out.ops[3], combinedImm, firstOps[1].opBits);
            return true;
        }
    }

    bool tryCombineAdjacentRegImm(Context& ctx, const MicroInstrRef firstRef, const MicroInstr& firstInst)
    {
        return tryFoldAdjacentPair(ctx, firstRef, firstInst, buildAdjacentRegImmRewrite);
    }
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroReg.h"

// Forward a LoadRegImm into its consumer so the materializing register
// disappears. We rewrite only the consumer; when every use of the
// LoadRegImm has been forwarded its result becomes dead and the
// companion DeadCodeElimination pass removes the LoadRegImm itself on
// the next iteration of the pre-RA optimization loop.
//
//   LoadRegImm    vt, bitsImm, imm
//   LoadMemReg    [base], vt, storeBits, off    -> LoadMemImm      [base], storeBits, off, imm
//   CmpRegReg     a, vt, bits                   -> CmpRegImm       a, bits, imm
//   OpBinaryRegReg dst, vt, bits, microOp       -> OpBinaryRegImm  dst, bits, microOp, imm
//   LoadRegReg    dst, vt, bits                 -> LoadRegImm      dst, bits, imm

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        bool findImmDef(uint64_t& outImm, const Context& ctx, MicroReg useReg, MicroInstrRef useRef)
        {
            if (!useReg.isVirtualInt())
                return false;

            const auto rd = ctx.ssa->reachingDef(useReg, useRef);
            if (!rd.valid() || rd.isPhi || !rd.inst)
                return false;
            if (rd.inst->op != MicroInstrOpcode::LoadRegImm)
                return false;
            if (rd.inst->numOperands < 3)
                return false;

            const MicroInstrOperand* immOps = rd.inst->ops(*ctx.operands);
            if (!immOps)
                return false;
            if (immOps[2].hasWideImmediateValue())
                return false;

            outImm = immOps[2].valueU64;
            return true;
        }
    }

    bool tryFoldConstStore(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst)
    {
        if (storeInst.numOperands < 4 || ctx.isClaimed(storeRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* storeOps = storeInst.ops(*ctx.operands);
        if (!storeOps)
            return false;

        const MicroReg    base      = storeOps[0].reg;
        const MicroReg    srcReg    = storeOps[1].reg;
        const MicroOpBits storeBits = storeOps[2].opBits;
        const uint64_t    storeOff  = storeOps[3].valueU64;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, srcReg, storeRef))
            return false;

        if (!ctx.claimAll({storeRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(storeBits);

        MicroInstrOperand newOps[4];
        newOps[0].reg      = base;
        newOps[1].opBits   = storeBits;
        newOps[2].valueU64 = storeOff;
        newOps[3].setImmediateValue(ApInt(imm, getNumBits(storeBits)));

        ctx.emitRewrite(storeRef, MicroInstrOpcode::LoadMemImm, newOps);
        return true;
    }

    bool tryFoldConstCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (cmpInst.numOperands < 3 || ctx.isClaimed(cmpRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps)
            return false;

        const MicroReg    lhs    = cmpOps[0].reg;
        const MicroReg    rhs    = cmpOps[1].reg;
        const MicroOpBits opBits = cmpOps[2].opBits;

        // Only rewrite when the RHS is the constant. Swapping with an LHS
        // constant would require inverting every consumer's MicroCond.
        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, rhs, cmpRef))
            return false;

        if (!ctx.claimAll({cmpRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(opBits);

        MicroInstrOperand newOps[3];
        newOps[0].reg    = lhs;
        newOps[1].opBits = opBits;
        newOps[2].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegImm, newOps);
        return true;
    }

    bool tryFoldConstBinaryRhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst)
    {
        if (binInst.numOperands < 4 || ctx.isClaimed(binRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* binOps = binInst.ops(*ctx.operands);
        if (!binOps)
            return false;

        const MicroReg    dst     = binOps[0].reg;
        const MicroReg    rhs     = binOps[1].reg;
        const MicroOpBits opBits  = binOps[2].opBits;
        const MicroOp     microOp = binOps[3].microOp;

        // Only integer ops have a meaningful immediate form.
        if (!dst.isVirtualInt())
            return false;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, rhs, binRef))
            return false;

        if (!ctx.claimAll({binRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(opBits);

        MicroInstrOperand newOps[4];
        newOps[0].reg     = dst;
        newOps[1].opBits  = opBits;
        newOps[2].microOp = microOp;
        newOps[3].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(binRef, MicroInstrOpcode::OpBinaryRegImm, newOps);
        return true;
    }

    // LoadRegReg dst, src, bits where src = LoadRegImm imm  -> LoadRegImm dst, bits, imm.
    // Breaks constant-carrying copies (e.g. from narrowing reg-reg moves
    // that CopyElimination skips when the source/destination widths differ).
    bool tryFoldConstCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.numOperands < 3 || ctx.isClaimed(copyRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg    dst    = copyOps[0].reg;
        const MicroReg    src    = copyOps[1].reg;
        const MicroOpBits opBits = copyOps[2].opBits;

        if (!dst.isVirtualInt())
            return false;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, src, copyRef))
            return false;

        if (!ctx.claimAll({copyRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(opBits);

        MicroInstrOperand newOps[3];
        newOps[0].reg    = dst;
        newOps[1].opBits = opBits;
        newOps[2].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(copyRef, MicroInstrOpcode::LoadRegImm, newOps);
        return true;
    }
}

SWC_END_NAMESPACE();

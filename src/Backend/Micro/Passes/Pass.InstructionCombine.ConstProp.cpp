#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroReg.h"

// Forward a single-use LoadRegImm into its consumer so the intermediate
// register copy disappears.
//
//   LoadRegImm    vt, bitsImm, imm
//   LoadMemReg    [base], vt, storeBits, off    -> LoadMemImm      [base], storeBits, off, imm
//   CmpRegReg     a, vt, bits                   -> CmpRegImm       a, bits, imm
//   OpBinaryRegReg dst, vt, bits, microOp       -> OpBinaryRegImm  dst, bits, microOp, imm

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        struct ImmSource
        {
            MicroInstrRef defRef = MicroInstrRef::invalid();
            uint64_t      imm    = 0;
        };

        bool findSingleUseImmDef(ImmSource& out, Context& ctx, MicroReg useReg, MicroInstrRef useRef)
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

            if (!valueHasSingleUse(*ctx.ssa, useReg, rd.instRef))
                return false;
            if (ctx.isClaimed(rd.instRef))
                return false;

            out.defRef = rd.instRef;
            out.imm    = immOps[2].valueU64;
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

        ImmSource src;
        if (!findSingleUseImmDef(src, ctx, srcReg, storeRef))
            return false;

        if (!ctx.claimAll({src.defRef, storeRef}))
            return false;

        const uint64_t imm = src.imm & getBitsMask(storeBits);

        MicroInstrOperand newOps[4];
        newOps[0].reg    = base;
        newOps[1].opBits = storeBits;
        newOps[2].valueU64 = storeOff;
        newOps[3].setImmediateValue(ApInt(imm, getNumBits(storeBits)));

        ctx.emitRewrite(storeRef, MicroInstrOpcode::LoadMemImm, newOps);
        ctx.emitErase(src.defRef);
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
        ImmSource src;
        if (!findSingleUseImmDef(src, ctx, rhs, cmpRef))
            return false;

        if (!ctx.claimAll({src.defRef, cmpRef}))
            return false;

        const uint64_t imm = src.imm & getBitsMask(opBits);

        MicroInstrOperand newOps[3];
        newOps[0].reg    = lhs;
        newOps[1].opBits = opBits;
        newOps[2].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegImm, newOps);
        ctx.emitErase(src.defRef);
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

        ImmSource src;
        if (!findSingleUseImmDef(src, ctx, rhs, binRef))
            return false;

        if (!ctx.claimAll({src.defRef, binRef}))
            return false;

        const uint64_t imm = src.imm & getBitsMask(opBits);

        MicroInstrOperand newOps[4];
        newOps[0].reg     = dst;
        newOps[1].opBits  = opBits;
        newOps[2].microOp = microOp;
        newOps[3].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(binRef, MicroInstrOpcode::OpBinaryRegImm, newOps);
        ctx.emitErase(src.defRef);
        return true;
    }
}

SWC_END_NAMESPACE();

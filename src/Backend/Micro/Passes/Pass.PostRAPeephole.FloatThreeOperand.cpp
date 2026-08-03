#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

// Fold the copy that legacy SSE forces in front of every float binary operation
// into the operation itself.
//
// SSE only writes its result back into one of its inputs, so `c = a * b` is
// built as `c = a` followed by `c *= b`. The copy is not an artifact of register
// allocation - no allocator can remove it, because the destination genuinely has
// to start out holding one of the operands - and it lands squarely in hot loops:
// raytrace's sphere-intersection loop spends 14 of its 102 instructions on them.
//
// AVX's VEX encoding names all three registers, so the copy disappears.

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool hasThreeOperandForm(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::FloatAdd:
                case MicroOp::FloatSubtract:
                case MicroOp::FloatMultiply:
                case MicroOp::FloatDivide:
                case MicroOp::FloatMin:
                case MicroOp::FloatMax:
                case MicroOp::FloatAnd:
                case MicroOp::FloatXor:
                    return true;
                default:
                    return false;
            }
        }
    }

    // Fold a float operand's reload into the operation that consumes it.
    //
    // x86 float arithmetic can read one operand straight from memory, but the
    // encoder only ever built the register form, so every value coming out of a
    // spill slot cost a separate load. raytrace's inner loop reloads twenty-two
    // times; each fold turns two instructions into one and frees the scratch
    // register the value was staged in.
    bool tryFoldLoadIntoFloatBinary(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (loadInst.op != MicroInstrOpcode::LoadRegMem || loadInst.numOperands < 4)
            return false;

        const MicroInstrOperand* loadOps = ctx.operandsFor(loadRef);
        if (!loadOps)
            return false;

        const MicroReg loaded = loadOps[0].reg;
        const MicroReg base   = loadOps[1].reg;
        if (!loaded.isFloat() || base.isFloat() || !base.isValid())
            return false;

        const MicroOpBits opBits = loadOps[2].opBits;
        if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
            return false;

        constexpr uint32_t K_MAX_SCAN = 12;

        MicroInstrRef     opRef  = ctx.nextRef(loadRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[1].reg == loaded && candidateOps[0].reg != loaded)
                {
                    opInst = candidate;
                    break;
                }
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrDef& info = MicroInstr::info(candidate->op);
            if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            // The read moves later, so anything that could change what it sees
            // stops the fold: a write to the address register, and any store at
            // all - this pass has no aliasing information.
            if (info.flags.has(MicroInstrFlagsE::WritesMemory))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == loaded || reg == base)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == loaded)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst)
            return false;

        const MicroInstrOperand* binOps = ctx.operandsFor(opRef);
        if (!binOps || binOps[2].opBits != opBits || !hasThreeOperandForm(binOps[3].microOp))
            return false;
        if (!binOps[0].reg.isFloat())
            return false;

        // The register only existed to carry the loaded value across; if anything
        // reads it afterwards it has to keep existing.
        if (!regIsDeadAfter(ctx, opRef, loaded))
            return false;

        if (!ctx.claimAll({loadRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg      = binOps[0].reg;
        newOps[1].reg      = base;
        newOps[2].opBits   = opBits;
        newOps[3].microOp  = binOps[3].microOp;
        newOps[4].valueU64 = loadOps[3].valueU64;

        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegMem, std::span{newOps, 5}, true);
        ctx.emitErase(loadRef);
        return true;
    }

    bool tryFoldCopyIntoFloatBinary(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
            return false;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;

        const MicroReg dst  = copyOps[0].reg;
        const MicroReg src1 = copyOps[1].reg;
        if (!dst.isFloat() || !src1.isFloat())
            return false;

        // The operation is rarely the next instruction: the second operand
        // usually has to be loaded first. Scan ahead for it, but only across
        // instructions that leave both registers alone, and stop at anything
        // control flow can enter from elsewhere - reaching the operation
        // without having run the copy would find a destination that never
        // received src1.
        constexpr uint32_t K_MAX_SCAN = 12;

        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            // A write to either register breaks the chain, and so does a read of
            // the destination: after the fold it no longer holds src1 there.
            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src1)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst || opInst->numOperands < 4)
            return false;

        const MicroInstrOperand* binOps = ctx.operandsFor(opRef);
        if (!binOps)
            return false;

        if (binOps[0].reg != dst)
            return false;

        const MicroReg src2 = binOps[1].reg;
        if (!src2.isFloat())
            return false;

        // `dst op= dst` reads the destination as its second source. Folding the
        // copy away would make that read see the pre-copy value instead of src1,
        // so this shape stays as it is.
        if (src2 == dst)
            return false;

        const MicroOpBits opBits = binOps[2].opBits;
        if (opBits != copyOps[2].opBits)
            return false;
        if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
            return false;
        if (!hasThreeOperandForm(binOps[3].microOp))
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg     = dst;
        newOps[1].reg     = src1;
        newOps[2].reg     = src2;
        newOps[3].opBits  = opBits;
        newOps[4].microOp = binOps[3].microOp;

        // Five operands where the original had four, so the rewrite needs a
        // fresh operand block.
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        bool canEncodeSigned32(const uint64_t value)
        {
            return value <= 0x7FFFFFFF || value >= 0xFFFFFFFF80000000;
        }

        bool getAddressAddOffset(uint64_t& outOffset, const MicroOp op, const uint64_t imm)
        {
            if (op == MicroOp::Add)
            {
                outOffset = imm;
                return true;
            }

            if (op == MicroOp::Subtract)
            {
                outOffset = 0ULL - imm;
                return true;
            }

            return false;
        }

        bool buildCopyAddLoadAddressRewrite(Action& out, const MicroInstr& copyInst, const MicroInstrOperand* copyOps, const MicroInstr& addInst, const MicroInstrOperand* addOps)
        {
            if (!copyOps || !addOps)
                return false;
            if (copyInst.op != MicroInstrOpcode::LoadRegReg || addInst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;
            if (addOps[3].hasWideImmediateValue())
                return false;
            if (copyOps[2].opBits != MicroOpBits::B64 || addOps[1].opBits != MicroOpBits::B64)
                return false;

            const MicroReg dst = copyOps[0].reg;
            const MicroReg src = copyOps[1].reg;
            if (!dst.isAnyInt() || !src.isAnyInt() || addOps[0].reg != dst)
                return false;

            uint64_t offset = 0;
            if (!getAddressAddOffset(offset, addOps[2].microOp, addOps[3].valueU64) || !canEncodeSigned32(offset))
                return false;

            // Adding nothing leaves the copy: a lea with no displacement is
            // an instruction the copy elimination would not see through.
            if (offset == 0)
            {
                out.newOp         = MicroInstrOpcode::LoadRegReg;
                out.numOps        = 3;
                out.allocOps      = true;
                out.ops[0].reg    = dst;
                out.ops[1].reg    = src;
                out.ops[2].opBits = MicroOpBits::B64;
                return true;
            }

            out.newOp           = MicroInstrOpcode::LoadAddrRegMem;
            out.numOps          = 4;
            out.allocOps        = true;
            out.ops[0].reg      = dst;
            out.ops[1].reg      = src;
            out.ops[2].opBits   = MicroOpBits::B64;
            out.ops[3].valueU64 = offset;
            return true;
        }
    }

    bool tryFoldCopyAddIntoLoadAddress(Context& ctx, const MicroInstrRef firstRef, const MicroInstr& firstInst)
    {
        return tryFoldAdjacentPair(ctx, firstRef, firstInst, buildCopyAddLoadAddressRewrite);
    }

    // Form non-destructive scalar arithmetic before allocation, so the allocator
    // sees the result as independent of both inputs instead of preserving a copy.
    bool tryFoldCopyIntoFloatBinary(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary() || ctx.isClaimed(copyRef))
            return false;
        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps || copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroReg    dst  = copyOps[0].reg;
        const MicroReg    src  = copyOps[1].reg;
        const MicroOpBits bits = copyOps[2].opBits;
        if (!dst.isVirtualFloat() || !src.isVirtualFloat() || dst == src)
            return false;
        if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
            return false;
        if (ctx.builder && (ctx.builder->shouldPreserveVirtualCopy(dst) || ctx.builder->shouldPreserveVirtualCopy(src)))
            return false;

        const MicroInstrRef opRef  = ctx.nextRef(copyRef);
        const MicroInstr*   opInst = opRef.isValid() ? ctx.instruction(opRef) : nullptr;
        if (!opInst || opInst->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const MicroInstrOperand* opOps = ctx.operandsFor(opRef);
        if (!opOps || opOps[0].reg != dst || opOps[2].opBits != bits)
            return false;
        switch (opOps[3].microOp)
        {
            case MicroOp::FloatAdd:
            case MicroOp::FloatSubtract:
            case MicroOp::FloatMultiply:
            case MicroOp::FloatDivide:
                break;
            default:
                return false;
        }
        if (!opOps[1].reg.isVirtualFloat() || opOps[1].reg == dst)
            return false;
        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand fused[5] = {};
        fused[0].reg               = dst;
        fused[1].reg               = src;
        fused[2].reg               = opOps[1].reg;
        fused[3].opBits            = bits;
        fused[4].microOp           = opOps[3].microOp;
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{fused, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    // A lane moved into a general register only to be stored is stored from
    // the vector register instead: the scalar store writes the low four or
    // eight bytes of the register, so the move and the general register go.
    // The copy stays for dead-code elimination, in case another reader remains.
    bool tryFoldLaneCopyIntoStore(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;

        const MicroReg    dst  = copyOps[0].reg;
        const MicroReg    src  = copyOps[1].reg;
        const MicroOpBits bits = copyOps[2].opBits;
        if (!dst.isVirtualInt() || !src.isVirtualFloat())
            return false;
        if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
            return false;

        const MicroInstrRef storeRef  = ctx.nextRef(copyRef);
        const MicroInstr*   storeInst = storeRef.isValid() ? ctx.instruction(storeRef) : nullptr;
        if (!storeInst || ctx.isClaimed(storeRef))
            return false;

        const MicroInstrOperand* storeOps = ctx.operandsFor(storeRef);
        if (!storeOps)
            return false;

        // ops: [0] base, [1] value, [2] opBits, [3] offset for the plain store;
        // [0] base, [1] index, [2] value, [3] address bits, [4] opBits for the
        // indexed one. The value is the moved lane, stored at its own width,
        // and no address register is that same general register.
        switch (storeInst->op)
        {
            case MicroInstrOpcode::LoadMemReg:
                if (storeOps[1].reg != dst || storeOps[2].opBits != bits || storeOps[0].reg == dst)
                    return false;
                break;
            case MicroInstrOpcode::LoadAmcMemReg:
                if (storeOps[2].reg != dst || storeOps[4].opBits != bits || storeOps[0].reg == dst || storeOps[1].reg == dst)
                    return false;
                break;
            default:
                return false;
        }

        Action rewrite;
        if (!buildUseOnlyRegRewrite(rewrite, *storeInst, storeOps, dst, src))
            return false;
        if (!ctx.claimAll({storeRef}))
            return false;

        rewrite.ref = storeRef;
        ctx.actions.push_back(rewrite);
        return true;
    }

    bool tryForwardCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg copyDst = copyOps[0].reg;
        const MicroReg copySrc = copyOps[1].reg;
        if (copyDst == copySrc || !copyDst.isVirtual() || !copySrc.isVirtual() || !copyDst.isSameClass(copySrc))
            return false;
        if (ctx.builder &&
            (ctx.builder->shouldPreserveVirtualCopy(copyDst) || ctx.builder->shouldPreserveVirtualCopy(copySrc)))
            return false;

        const MicroInstrRef consumerRef = ctx.nextRef(copyRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        Action rewrite;
        if (!buildUseOnlyRegRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), copyDst, copySrc))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        mergeVirtualForbiddenRegs(ctx, copyDst, copySrc);
        rewrite.ref = consumerRef;
        ctx.actions.push_back(rewrite);
        return true;
    }
}

SWC_END_NAMESPACE();

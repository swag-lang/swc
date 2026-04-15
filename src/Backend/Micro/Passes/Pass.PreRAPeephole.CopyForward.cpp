#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
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

    bool tryFoldCopyAddIntoLoadAddress(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;

        const MicroInstrRef addRef = ctx.nextRef(copyRef);
        if (!addRef.isValid() || ctx.isClaimed(addRef))
            return false;

        const MicroInstr* addInst = ctx.instruction(addRef);
        if (!addInst)
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, addRef))
            return false;

        Action rewrite;
        if (!buildCopyAddLoadAddressRewrite(rewrite, copyInst, ctx.operandsFor(copyRef), *addInst, ctx.operandsFor(addRef)))
            return false;

        if (!ctx.claimAll({copyRef, addRef}))
            return false;

        rewrite.ref = copyRef;
        ctx.actions.push_back(rewrite);
        ctx.emitErase(addRef);
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

        rewrite.ref = consumerRef;
        ctx.actions.push_back(rewrite);
        return true;
    }
}

SWC_END_NAMESPACE();

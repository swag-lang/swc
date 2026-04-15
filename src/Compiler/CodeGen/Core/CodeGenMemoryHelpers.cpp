#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_DEFAULT_UNROLL_MEM_LIMIT = 256;

    uint32_t getUnrollMemLimit(const Runtime::BuildCfgBackend& buildCfg)
    {
        if (buildCfg.unrollMemLimit)
            return buildCfg.unrollMemLimit;
        return K_DEFAULT_UNROLL_MEM_LIMIT;
    }

    void emitMemCopyChunk(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint64_t offset, uint32_t chunkSize, MicroReg tmpIntReg, MicroReg tmpFloatReg)
    {
        if (chunkSize == 16)
        {
            builder.emitLoadRegMem(tmpFloatReg, srcReg, offset, MicroOpBits::B128);
            builder.emitLoadMemReg(dstReg, offset, tmpFloatReg, MicroOpBits::B128);
            return;
        }

        const MicroOpBits opBits = microOpBitsFromChunkSize(chunkSize);
        builder.emitLoadRegMem(tmpIntReg, srcReg, offset, opBits);
        builder.emitLoadMemReg(dstReg, offset, tmpIntReg, opBits);
    }

    void emitMemCopyUnrolled(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint32_t sizeInBytes, bool allow128, MicroReg tmpIntReg, MicroReg tmpFloatReg)
    {
        uint32_t offset = 0;
        uint32_t remain = sizeInBytes;

        if (allow128)
        {
            while (remain >= 16)
            {
                emitMemCopyChunk(builder, dstReg, srcReg, offset, 16, tmpIntReg, tmpFloatReg);
                offset += 16;
                remain -= 16;
            }
        }

        while (remain >= 8)
        {
            emitMemCopyChunk(builder, dstReg, srcReg, offset, 8, tmpIntReg, tmpFloatReg);
            offset += 8;
            remain -= 8;
        }

        if (remain >= 4)
        {
            emitMemCopyChunk(builder, dstReg, srcReg, offset, 4, tmpIntReg, tmpFloatReg);
            offset += 4;
            remain -= 4;
        }

        if (remain >= 2)
        {
            emitMemCopyChunk(builder, dstReg, srcReg, offset, 2, tmpIntReg, tmpFloatReg);
            offset += 2;
            remain -= 2;
        }

        if (remain)
            emitMemCopyChunk(builder, dstReg, srcReg, offset, 1, tmpIntReg, tmpFloatReg);
    }

    void emitMemCopyLoop(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint32_t sizeInBytes, uint32_t chunkSize, MicroReg tmpIntReg, MicroReg tmpFloatReg, MicroReg countReg)
    {
        const uint32_t chunkCount = sizeInBytes / chunkSize;
        const uint32_t tailSize   = sizeInBytes % chunkSize;
        SWC_ASSERT(chunkCount > 0);

        const MicroLabelRef loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemCopyChunk(builder, dstReg, srcReg, 0, chunkSize, tmpIntReg, tmpFloatReg);
        builder.emitOpBinaryRegImm(srcReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemCopyUnrolled(builder, dstReg, srcReg, tailSize, false, tmpIntReg, tmpFloatReg);
    }

    void emitMemCopyUnrolledBackward(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint32_t sizeInBytes, bool allow128, MicroReg tmpIntReg, MicroReg tmpFloatReg)
    {
        uint32_t remain = sizeInBytes;

        if (allow128)
        {
            while (remain >= 16)
            {
                builder.emitOpBinaryRegImm(srcReg, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(dstReg, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
                emitMemCopyChunk(builder, dstReg, srcReg, 0, 16, tmpIntReg, tmpFloatReg);
                remain -= 16;
            }
        }

        while (remain >= 8)
        {
            builder.emitOpBinaryRegImm(srcReg, ApInt(8, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(dstReg, ApInt(8, 64), MicroOp::Subtract, MicroOpBits::B64);
            emitMemCopyChunk(builder, dstReg, srcReg, 0, 8, tmpIntReg, tmpFloatReg);
            remain -= 8;
        }

        if (remain >= 4)
        {
            builder.emitOpBinaryRegImm(srcReg, ApInt(4, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(dstReg, ApInt(4, 64), MicroOp::Subtract, MicroOpBits::B64);
            emitMemCopyChunk(builder, dstReg, srcReg, 0, 4, tmpIntReg, tmpFloatReg);
            remain -= 4;
        }

        if (remain >= 2)
        {
            builder.emitOpBinaryRegImm(srcReg, ApInt(2, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(dstReg, ApInt(2, 64), MicroOp::Subtract, MicroOpBits::B64);
            emitMemCopyChunk(builder, dstReg, srcReg, 0, 2, tmpIntReg, tmpFloatReg);
            remain -= 2;
        }

        if (remain)
        {
            builder.emitOpBinaryRegImm(srcReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(dstReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
            emitMemCopyChunk(builder, dstReg, srcReg, 0, 1, tmpIntReg, tmpFloatReg);
        }
    }

    void emitMemCopyLoopBackward(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint32_t sizeInBytes, uint32_t chunkSize, MicroReg tmpIntReg, MicroReg tmpFloatReg, MicroReg countReg)
    {
        const uint32_t chunkCount = sizeInBytes / chunkSize;
        const uint32_t tailSize   = sizeInBytes % chunkSize;
        SWC_ASSERT(chunkCount > 0);

        const MicroLabelRef loopLabel = builder.createLabel();

        builder.emitOpBinaryRegImm(srcReg, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(dstReg, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        builder.emitOpBinaryRegImm(srcReg, ApInt(chunkSize, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Subtract, MicroOpBits::B64);
        emitMemCopyChunk(builder, dstReg, srcReg, 0, chunkSize, tmpIntReg, tmpFloatReg);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemCopyUnrolledBackward(builder, dstReg, srcReg, tailSize, false, tmpIntReg, tmpFloatReg);
    }

    void emitMemRepeatCopyUnrolled(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint32_t elementSizeInBytes, uint32_t elementCount, MicroReg tmpIntReg, MicroReg tmpFloatReg)
    {
        for (uint32_t i = 0; i < elementCount; ++i)
        {
            emitMemCopyUnrolled(builder, dstReg, srcReg, elementSizeInBytes, true, tmpIntReg, tmpFloatReg);
            builder.emitOpBinaryRegImm(dstReg, ApInt(elementSizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
        }
    }

    void emitMemRepeatCopyLoop(MicroBuilder& builder, MicroReg dstReg, MicroReg srcReg, uint32_t elementSizeInBytes, uint32_t elementCount, MicroReg tmpIntReg, MicroReg tmpFloatReg, MicroReg countReg)
    {
        SWC_ASSERT(elementCount > 0);

        const MicroLabelRef loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(elementCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemCopyUnrolled(builder, dstReg, srcReg, elementSizeInBytes, true, tmpIntReg, tmpFloatReg);
        builder.emitOpBinaryRegImm(dstReg, ApInt(elementSizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);
    }

    void emitMemSetChunk(MicroBuilder& builder, MicroReg dstReg, uint64_t offset, uint32_t chunkSize, MicroReg fillReg)
    {
        builder.emitLoadMemReg(dstReg, offset, fillReg, microOpBitsFromChunkSize(chunkSize));
    }

    void emitMemSetUnrolled(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, MicroReg fillReg)
    {
        uint32_t offset = 0;
        uint32_t remain = sizeInBytes;

        while (remain >= 8)
        {
            emitMemSetChunk(builder, dstReg, offset, 8, fillReg);
            offset += 8;
            remain -= 8;
        }

        if (remain >= 4)
        {
            emitMemSetChunk(builder, dstReg, offset, 4, fillReg);
            offset += 4;
            remain -= 4;
        }

        if (remain >= 2)
        {
            emitMemSetChunk(builder, dstReg, offset, 2, fillReg);
            offset += 2;
            remain -= 2;
        }

        if (remain)
            emitMemSetChunk(builder, dstReg, offset, 1, fillReg);
    }

    void emitMemSetLoop(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, uint32_t chunkSize, MicroReg fillReg, MicroReg countReg)
    {
        const uint32_t chunkCount = sizeInBytes / chunkSize;
        const uint32_t tailSize   = sizeInBytes % chunkSize;
        SWC_ASSERT(chunkCount > 0);

        const MicroLabelRef loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemSetChunk(builder, dstReg, 0, chunkSize, fillReg);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemSetUnrolled(builder, dstReg, tailSize, fillReg);
    }

    void emitBuildRepeatedFillReg64(MicroBuilder& builder, MicroReg outReg, MicroReg scratchReg, MicroReg fillValueReg, uint32_t elementSizeInBytes)
    {
        switch (elementSizeInBytes)
        {
            case 8:
                builder.emitLoadRegReg(outReg, fillValueReg, MicroOpBits::B64);
                return;

            case 4:
                builder.emitLoadRegReg(outReg, fillValueReg, MicroOpBits::B32);
                builder.emitLoadRegReg(scratchReg, outReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(scratchReg, ApInt(32, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(outReg, scratchReg, MicroOp::Or, MicroOpBits::B64);
                return;

            case 2:
                builder.emitClearReg(outReg, MicroOpBits::B64);
                builder.emitLoadRegReg(outReg, fillValueReg, MicroOpBits::B16);
                builder.emitLoadRegReg(scratchReg, outReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(scratchReg, ApInt(16, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(outReg, scratchReg, MicroOp::Or, MicroOpBits::B64);
                builder.emitLoadRegReg(scratchReg, outReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(scratchReg, ApInt(32, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(outReg, scratchReg, MicroOp::Or, MicroOpBits::B64);
                return;

            case 1:
                builder.emitClearReg(outReg, MicroOpBits::B64);
                builder.emitLoadRegReg(outReg, fillValueReg, MicroOpBits::B8);
                builder.emitLoadRegReg(scratchReg, outReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(scratchReg, ApInt(8, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(outReg, scratchReg, MicroOp::Or, MicroOpBits::B64);
                builder.emitLoadRegReg(scratchReg, outReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(scratchReg, ApInt(16, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(outReg, scratchReg, MicroOp::Or, MicroOpBits::B64);
                builder.emitLoadRegReg(scratchReg, outReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(scratchReg, ApInt(32, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
                builder.emitOpBinaryRegReg(outReg, scratchReg, MicroOp::Or, MicroOpBits::B64);
                return;

            default:
                SWC_UNREACHABLE();
        }
    }

    void emitMemFill128Chunk(MicroBuilder& builder, MicroReg dstReg, uint64_t offset, MicroReg fillReg)
    {
        builder.emitLoadMemReg(dstReg, offset, fillReg, MicroOpBits::B128);
    }

    void emitMemFill128Unrolled(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, MicroReg fill128Reg, MicroReg fill64Reg)
    {
        uint32_t offset = 0;
        uint32_t remain = sizeInBytes;

        while (remain >= 16)
        {
            emitMemFill128Chunk(builder, dstReg, offset, fill128Reg);
            offset += 16;
            remain -= 16;
        }

        if (remain)
        {
            const MicroReg tailBaseReg = dstReg;
            if (offset)
                builder.emitOpBinaryRegImm(tailBaseReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
            emitMemSetUnrolled(builder, tailBaseReg, remain, fill64Reg);
        }
    }

    void emitMemFill128Loop(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, MicroReg fill128Reg, MicroReg fill64Reg, MicroReg countReg)
    {
        if (sizeInBytes < 16)
        {
            emitMemSetUnrolled(builder, dstReg, sizeInBytes, fill64Reg);
            return;
        }

        const uint32_t      chunkCount = sizeInBytes / 16;
        const uint32_t      tailSize   = sizeInBytes % 16;
        const MicroLabelRef loopLabel  = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemFill128Chunk(builder, dstReg, 0, fill128Reg);
        builder.emitOpBinaryRegImm(dstReg, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemSetUnrolled(builder, dstReg, tailSize, fill64Reg);
    }

    void emitMemZeroChunk(MicroBuilder& builder, MicroReg dstReg, uint64_t offset, uint32_t chunkSize, MicroReg zeroReg, MicroReg zero128Reg)
    {
        if (chunkSize == 16)
        {
            builder.emitLoadMemReg(dstReg, offset, zero128Reg, MicroOpBits::B128);
            return;
        }

        builder.emitLoadMemReg(dstReg, offset, zeroReg, microOpBitsFromChunkSize(chunkSize));
    }

    void emitMemZeroUnrolled(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, bool allow128, MicroReg zeroReg, MicroReg zero128Reg)
    {
        uint32_t offset = 0;
        uint32_t remain = sizeInBytes;

        if (allow128)
        {
            while (remain >= 16)
            {
                emitMemZeroChunk(builder, dstReg, offset, 16, zeroReg, zero128Reg);
                offset += 16;
                remain -= 16;
            }
        }

        while (remain >= 8)
        {
            emitMemZeroChunk(builder, dstReg, offset, 8, zeroReg, zero128Reg);
            offset += 8;
            remain -= 8;
        }

        if (remain >= 4)
        {
            emitMemZeroChunk(builder, dstReg, offset, 4, zeroReg, zero128Reg);
            offset += 4;
            remain -= 4;
        }

        if (remain >= 2)
        {
            emitMemZeroChunk(builder, dstReg, offset, 2, zeroReg, zero128Reg);
            offset += 2;
            remain -= 2;
        }

        if (remain)
            emitMemZeroChunk(builder, dstReg, offset, 1, zeroReg, zero128Reg);
    }

    void emitMemZeroLoop(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, uint32_t chunkSize, MicroReg zeroReg, MicroReg zero128Reg, MicroReg countReg)
    {
        const uint32_t chunkCount = sizeInBytes / chunkSize;
        const uint32_t tailSize   = sizeInBytes % chunkSize;
        SWC_ASSERT(chunkCount > 0);

        const MicroLabelRef loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemZeroChunk(builder, dstReg, 0, chunkSize, zeroReg, zero128Reg);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemZeroUnrolled(builder, dstReg, tailSize, false, zeroReg, zero128Reg);
    }

    void emitMemCompareUnrolled(MicroBuilder& builder, MicroReg resultReg, MicroReg leftReg, MicroReg rightReg, uint32_t sizeInBytes, MicroReg leftByteReg, MicroReg rightByteReg, MicroLabelRef doneLabel)
    {
        for (uint32_t offset = 0; offset < sizeInBytes; ++offset)
        {
            const MicroLabelRef nextByteLabel = builder.createLabel();
            builder.emitLoadSignedExtendRegMem(leftByteReg, leftReg, offset, MicroOpBits::B64, MicroOpBits::B8);
            builder.emitLoadSignedExtendRegMem(rightByteReg, rightReg, offset, MicroOpBits::B64, MicroOpBits::B8);
            builder.emitCmpRegReg(leftByteReg, rightByteReg, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nextByteLabel);
            builder.emitLoadRegReg(resultReg, leftByteReg, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(resultReg, rightByteReg, MicroOp::Subtract, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
            builder.placeLabel(nextByteLabel);
        }
    }

    void emitMemCompareLoop(MicroBuilder& builder, MicroReg resultReg, MicroReg leftReg, MicroReg rightReg, uint32_t sizeInBytes, MicroReg leftByteReg, MicroReg rightByteReg, MicroReg countReg, MicroLabelRef doneLabel)
    {
        SWC_ASSERT(sizeInBytes);
        const MicroLabelRef loopLabel     = builder.createLabel();
        const MicroLabelRef nextByteLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(sizeInBytes, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        builder.emitLoadSignedExtendRegMem(leftByteReg, leftReg, 0, MicroOpBits::B64, MicroOpBits::B8);
        builder.emitLoadSignedExtendRegMem(rightByteReg, rightReg, 0, MicroOpBits::B64, MicroOpBits::B8);
        builder.emitCmpRegReg(leftByteReg, rightByteReg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nextByteLabel);
        builder.emitLoadRegReg(resultReg, leftByteReg, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(resultReg, rightByteReg, MicroOp::Subtract, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
        builder.placeLabel(nextByteLabel);

        builder.emitOpBinaryRegImm(leftReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(rightReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);
    }
}

void CodeGenMemoryHelpers::loadOperandToRegister(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef regTypeRef, MicroOpBits opBits)
{
    outReg                = codeGen.nextVirtualRegisterForType(regTypeRef);
    MicroBuilder& builder = codeGen.builder();
    if (payload.isAddress())
        builder.emitLoadRegMem(outReg, payload.reg, 0, opBits);
    else
        builder.emitLoadRegReg(outReg, payload.reg, opBits);
}

void CodeGenMemoryHelpers::emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    MicroBuilder&                   builder     = codeGen.builder();
    const Runtime::BuildCfgBackend& buildCfg    = builder.backendBuildCfg();
    const bool                      optimize    = buildCfg.optimize;
    const bool                      allow128    = optimize && sizeInBytes >= 16;
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);

    const MicroReg dstRegTmp   = codeGen.nextVirtualIntRegister();
    const MicroReg srcReg      = codeGen.nextVirtualIntRegister();
    const MicroReg tmpIntReg   = codeGen.nextVirtualIntRegister();
    const MicroReg tmpFloatReg = allow128 ? codeGen.nextVirtualFloatRegister() : MicroReg::invalid();

    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitLoadRegReg(srcReg, srcAddressReg, MicroOpBits::B64);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemCopyUnrolled(builder, dstRegTmp, srcReg, sizeInBytes, false, tmpIntReg, tmpFloatReg);
            return;
        }

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, 8, tmpIntReg, tmpFloatReg, countReg);
        return;
    }

    if (sizeInBytes <= unrollLimit)
    {
        emitMemCopyUnrolled(builder, dstRegTmp, srcReg, sizeInBytes, allow128, tmpIntReg, tmpFloatReg);
        return;
    }

    const MicroReg countReg  = codeGen.nextVirtualIntRegister();
    const uint32_t chunkSize = allow128 ? 16 : 8;
    emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, chunkSize, tmpIntReg, tmpFloatReg, countReg);
}

void CodeGenMemoryHelpers::emitMemFill(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, const uint32_t elementSizeInBytes, const uint32_t elementCount)
{
    if (!elementSizeInBytes || !elementCount)
        return;

    SWC_ASSERT(elementSizeInBytes == 1 || elementSizeInBytes == 2 || elementSizeInBytes == 4 || elementSizeInBytes == 8);

    const uint64_t totalBytes64 = static_cast<uint64_t>(elementSizeInBytes) * elementCount;
    SWC_ASSERT(totalBytes64 <= std::numeric_limits<uint32_t>::max());

    MicroBuilder&                   builder     = codeGen.builder();
    const Runtime::BuildCfgBackend& buildCfg    = builder.backendBuildCfg();
    const bool                      optimize    = buildCfg.optimize;
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);
    const uint32_t                  totalBytes  = static_cast<uint32_t>(totalBytes64);
    const bool                      allow128    = optimize && totalBytes >= 32;

    const MicroReg dstRegTmp   = codeGen.nextVirtualIntRegister();
    const MicroReg fill64Reg   = codeGen.nextVirtualIntRegister();
    const MicroReg fillScratch = elementSizeInBytes == 8 ? MicroReg::invalid() : codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    emitBuildRepeatedFillReg64(builder, fill64Reg, fillScratch, fillValueReg, elementSizeInBytes);

    if (!allow128)
    {
        if (totalBytes <= unrollLimit)
        {
            emitMemSetUnrolled(builder, dstRegTmp, totalBytes, fill64Reg);
            return;
        }

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitMemSetLoop(builder, dstRegTmp, totalBytes, 8, fill64Reg, countReg);
        return;
    }

    emitMemSetChunk(builder, dstRegTmp, 0, 8, fill64Reg);
    emitMemSetChunk(builder, dstRegTmp, 8, 8, fill64Reg);

    const MicroReg fill128Reg = codeGen.nextVirtualFloatRegister();
    builder.emitLoadRegMem(fill128Reg, dstRegTmp, 0, MicroOpBits::B128);

    const uint32_t remainBytes = totalBytes - 16;
    if (!remainBytes)
        return;

    builder.emitOpBinaryRegImm(dstRegTmp, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);
    if (remainBytes <= unrollLimit)
    {
        emitMemFill128Unrolled(builder, dstRegTmp, remainBytes, fill128Reg, fill64Reg);
        return;
    }

    const MicroReg countReg = codeGen.nextVirtualIntRegister();
    emitMemFill128Loop(builder, dstRegTmp, remainBytes, fill128Reg, fill64Reg, countReg);
}

void CodeGenMemoryHelpers::emitMemRepeatCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, const uint32_t elementSizeInBytes, const uint32_t elementCount)
{
    if (!elementSizeInBytes || !elementCount)
        return;

    const uint64_t totalBytes = static_cast<uint64_t>(elementSizeInBytes) * elementCount;
    SWC_ASSERT(totalBytes <= std::numeric_limits<uint32_t>::max());

    MicroBuilder&  builder     = codeGen.builder();
    const uint32_t memLimit    = getUnrollMemLimit(codeGen.buildCfgBackend());
    const MicroReg dstRegTmp   = codeGen.nextVirtualIntRegister();
    const MicroReg srcRegTmp   = codeGen.nextVirtualIntRegister();
    const MicroReg tmpIntReg   = codeGen.nextVirtualIntRegister();
    const MicroReg tmpFloatReg = codeGen.nextVirtualFloatRegister();
    const MicroReg countReg    = codeGen.nextVirtualIntRegister();

    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitLoadRegReg(srcRegTmp, srcAddressReg, MicroOpBits::B64);

    if (totalBytes <= memLimit)
    {
        emitMemRepeatCopyUnrolled(builder, dstRegTmp, srcRegTmp, elementSizeInBytes, elementCount, tmpIntReg, tmpFloatReg);
        return;
    }

    emitMemRepeatCopyLoop(builder, dstRegTmp, srcRegTmp, elementSizeInBytes, elementCount, tmpIntReg, tmpFloatReg, countReg);
}

void CodeGenMemoryHelpers::emitMemSet(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    MicroBuilder&                   builder     = codeGen.builder();
    const Runtime::BuildCfgBackend& buildCfg    = builder.backendBuildCfg();
    const bool                      optimize    = buildCfg.optimize;
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);

    const MicroReg dstRegTmp  = codeGen.nextVirtualIntRegister();
    const MicroReg fillByte   = codeGen.nextVirtualIntRegister();
    const MicroReg fillReg    = codeGen.nextVirtualIntRegister();
    const MicroReg fillRegTmp = codeGen.nextVirtualIntRegister();

    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitClearReg(fillByte, MicroOpBits::B64);
    builder.emitLoadRegReg(fillByte, fillValueReg, MicroOpBits::B8);

    builder.emitLoadRegReg(fillReg, fillByte, MicroOpBits::B64);
    builder.emitLoadRegReg(fillRegTmp, fillReg, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(fillRegTmp, ApInt(8, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(fillReg, fillRegTmp, MicroOp::Or, MicroOpBits::B64);
    builder.emitLoadRegReg(fillRegTmp, fillReg, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(fillRegTmp, ApInt(16, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(fillReg, fillRegTmp, MicroOp::Or, MicroOpBits::B64);
    builder.emitLoadRegReg(fillRegTmp, fillReg, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(fillRegTmp, ApInt(32, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(fillReg, fillRegTmp, MicroOp::Or, MicroOpBits::B64);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemSetUnrolled(builder, dstRegTmp, sizeInBytes, fillReg);
            return;
        }

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitMemSetLoop(builder, dstRegTmp, sizeInBytes, 8, fillReg, countReg);
        return;
    }

    if (sizeInBytes <= unrollLimit)
    {
        emitMemSetUnrolled(builder, dstRegTmp, sizeInBytes, fillReg);
        return;
    }

    const MicroReg countReg = codeGen.nextVirtualIntRegister();
    emitMemSetLoop(builder, dstRegTmp, sizeInBytes, 8, fillReg, countReg);
}

void CodeGenMemoryHelpers::emitMemZero(CodeGen& codeGen, MicroReg dstReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    MicroBuilder&                   builder     = codeGen.builder();
    const Runtime::BuildCfgBackend& buildCfg    = builder.backendBuildCfg();
    const bool                      optimize    = buildCfg.optimize;
    const bool                      allow128    = optimize && sizeInBytes >= 16;
    const bool                      needs64Zero = !allow128 || (sizeInBytes % 16) != 0;
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);

    const MicroReg dstRegTmp  = codeGen.nextVirtualIntRegister();
    const MicroReg zeroReg    = needs64Zero ? codeGen.nextVirtualIntRegister() : MicroReg::invalid();
    const MicroReg zero128Reg = allow128 ? codeGen.nextVirtualFloatRegister() : MicroReg::invalid();
    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    if (needs64Zero)
        builder.emitClearReg(zeroReg, MicroOpBits::B64);
    if (allow128)
        builder.emitClearReg(zero128Reg, MicroOpBits::B128);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemZeroUnrolled(builder, dstRegTmp, sizeInBytes, false, zeroReg, zero128Reg);
            return;
        }

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitMemZeroLoop(builder, dstRegTmp, sizeInBytes, 8, zeroReg, zero128Reg, countReg);
        return;
    }

    if (sizeInBytes <= unrollLimit)
    {
        emitMemZeroUnrolled(builder, dstRegTmp, sizeInBytes, allow128, zeroReg, zero128Reg);
        return;
    }

    const MicroReg countReg  = codeGen.nextVirtualIntRegister();
    const uint32_t chunkSize = allow128 ? 16 : 8;
    emitMemZeroLoop(builder, dstRegTmp, sizeInBytes, chunkSize, zeroReg, zero128Reg, countReg);
}

void CodeGenMemoryHelpers::emitMemMove(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    MicroBuilder&                   builder     = codeGen.builder();
    const Runtime::BuildCfgBackend& buildCfg    = builder.backendBuildCfg();
    const bool                      optimize    = buildCfg.optimize;
    const bool                      allow128    = optimize && sizeInBytes >= 16;
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);

    const MicroReg dstRegTmp   = codeGen.nextVirtualIntRegister();
    const MicroReg srcReg      = codeGen.nextVirtualIntRegister();
    const MicroReg tmpIntReg   = codeGen.nextVirtualIntRegister();
    const MicroReg tmpFloatReg = allow128 ? codeGen.nextVirtualFloatRegister() : MicroReg::invalid();

    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitLoadRegReg(srcReg, srcAddressReg, MicroOpBits::B64);

    const MicroLabelRef forwardLabel = builder.createLabel();
    const MicroLabelRef doneLabel    = builder.createLabel();

    builder.emitCmpRegReg(dstRegTmp, srcReg, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, forwardLabel);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

    const MicroReg srcEndReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(srcEndReg, srcReg, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(srcEndReg, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegReg(dstRegTmp, srcEndReg, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, forwardLabel);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            builder.emitOpBinaryRegImm(srcReg, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(dstRegTmp, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
            emitMemCopyUnrolledBackward(builder, dstRegTmp, srcReg, sizeInBytes, false, tmpIntReg, tmpFloatReg);
        }
        else
        {
            const MicroReg countReg = codeGen.nextVirtualIntRegister();
            emitMemCopyLoopBackward(builder, dstRegTmp, srcReg, sizeInBytes, 8, tmpIntReg, tmpFloatReg, countReg);
        }
    }
    else
    {
        if (sizeInBytes <= unrollLimit)
        {
            builder.emitOpBinaryRegImm(srcReg, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(dstRegTmp, ApInt(sizeInBytes, 64), MicroOp::Add, MicroOpBits::B64);
            emitMemCopyUnrolledBackward(builder, dstRegTmp, srcReg, sizeInBytes, allow128, tmpIntReg, tmpFloatReg);
        }
        else
        {
            const MicroReg countReg  = codeGen.nextVirtualIntRegister();
            const uint32_t chunkSize = allow128 ? 16 : 8;
            emitMemCopyLoopBackward(builder, dstRegTmp, srcReg, sizeInBytes, chunkSize, tmpIntReg, tmpFloatReg, countReg);
        }
    }

    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(forwardLabel);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemCopyUnrolled(builder, dstRegTmp, srcReg, sizeInBytes, false, tmpIntReg, tmpFloatReg);
        }
        else
        {
            const MicroReg countReg = codeGen.nextVirtualIntRegister();
            emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, 8, tmpIntReg, tmpFloatReg, countReg);
        }
    }
    else
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemCopyUnrolled(builder, dstRegTmp, srcReg, sizeInBytes, allow128, tmpIntReg, tmpFloatReg);
        }
        else
        {
            const MicroReg countReg  = codeGen.nextVirtualIntRegister();
            const uint32_t chunkSize = allow128 ? 16 : 8;
            emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, chunkSize, tmpIntReg, tmpFloatReg, countReg);
        }
    }

    builder.placeLabel(doneLabel);
}

void CodeGenMemoryHelpers::emitMemCompare(CodeGen& codeGen, MicroReg outResultReg, MicroReg leftAddressReg, MicroReg rightAddressReg, uint32_t sizeInBytes)
{
    MicroBuilder&                   builder     = codeGen.builder();
    const Runtime::BuildCfgBackend& buildCfg    = builder.backendBuildCfg();
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);

    if (!sizeInBytes)
    {
        builder.emitClearReg(outResultReg, MicroOpBits::B64);
        return;
    }

    const MicroReg leftReg      = codeGen.nextVirtualIntRegister();
    const MicroReg rightReg     = codeGen.nextVirtualIntRegister();
    const MicroReg leftByteReg  = codeGen.nextVirtualIntRegister();
    const MicroReg rightByteReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(leftReg, leftAddressReg, MicroOpBits::B64);
    builder.emitLoadRegReg(rightReg, rightAddressReg, MicroOpBits::B64);

    const MicroLabelRef doneLabel = builder.createLabel();

    if (sizeInBytes <= unrollLimit)
    {
        emitMemCompareUnrolled(builder, outResultReg, leftReg, rightReg, sizeInBytes, leftByteReg, rightByteReg, doneLabel);
    }
    else
    {
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitMemCompareLoop(builder, outResultReg, leftReg, rightReg, sizeInBytes, leftByteReg, rightByteReg, countReg, doneLabel);
    }

    builder.emitClearReg(outResultReg, MicroOpBits::B64);
    builder.placeLabel(doneLabel);
}

SWC_END_NAMESPACE();

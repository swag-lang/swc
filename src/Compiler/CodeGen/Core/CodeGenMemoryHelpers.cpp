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

    void emitMemZeroChunk(MicroBuilder& builder, MicroReg dstReg, uint64_t offset, uint32_t chunkSize, MicroReg zeroReg)
    {
        builder.emitLoadMemReg(dstReg, offset, zeroReg, microOpBitsFromChunkSize(chunkSize));
    }

    void emitMemZeroUnrolled(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, MicroReg zeroReg)
    {
        uint32_t offset = 0;
        uint32_t remain = sizeInBytes;

        while (remain >= 8)
        {
            emitMemZeroChunk(builder, dstReg, offset, 8, zeroReg);
            offset += 8;
            remain -= 8;
        }

        if (remain >= 4)
        {
            emitMemZeroChunk(builder, dstReg, offset, 4, zeroReg);
            offset += 4;
            remain -= 4;
        }

        if (remain >= 2)
        {
            emitMemZeroChunk(builder, dstReg, offset, 2, zeroReg);
            offset += 2;
            remain -= 2;
        }

        if (remain)
            emitMemZeroChunk(builder, dstReg, offset, 1, zeroReg);
    }

    void emitMemZeroLoop(MicroBuilder& builder, MicroReg dstReg, uint32_t sizeInBytes, uint32_t chunkSize, MicroReg zeroReg, MicroReg countReg)
    {
        const uint32_t chunkCount = sizeInBytes / chunkSize;
        const uint32_t tailSize   = sizeInBytes % chunkSize;
        SWC_ASSERT(chunkCount > 0);

        const MicroLabelRef loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemZeroChunk(builder, dstReg, 0, chunkSize, zeroReg);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemZeroUnrolled(builder, dstReg, tailSize, zeroReg);
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
    const uint32_t                  unrollLimit = getUnrollMemLimit(buildCfg);

    const MicroReg dstRegTmp = codeGen.nextVirtualIntRegister();
    const MicroReg zeroReg   = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitClearReg(zeroReg, MicroOpBits::B64);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemZeroUnrolled(builder, dstRegTmp, sizeInBytes, zeroReg);
            return;
        }

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        emitMemZeroLoop(builder, dstRegTmp, sizeInBytes, 8, zeroReg, countReg);
        return;
    }

    if (sizeInBytes <= unrollLimit)
    {
        emitMemZeroUnrolled(builder, dstRegTmp, sizeInBytes, zeroReg);
        return;
    }

    const MicroReg countReg = codeGen.nextVirtualIntRegister();
    emitMemZeroLoop(builder, dstRegTmp, sizeInBytes, 8, zeroReg, countReg);
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

#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Main/CompilerInstance.h"

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

        const auto loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, chunkCount, MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemCopyChunk(builder, dstReg, srcReg, 0, chunkSize, tmpIntReg, tmpFloatReg);
        builder.emitOpBinaryRegImm(srcReg, chunkSize, MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(dstReg, chunkSize, MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, 1, MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, 0, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemCopyUnrolled(builder, dstReg, srcReg, tailSize, false, tmpIntReg, tmpFloatReg);
    }
}

void CodeGenHelpers::emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    const auto&    buildCfg        = codeGen.builder().backendBuildCfg();
    const auto     optimizeLevel   = buildCfg.optimizeLevel;
    const bool     optimize        = optimizeLevel >= Runtime::BuildCfgBackendOptim::O1;
    const bool     optimizeForSize = optimizeLevel == Runtime::BuildCfgBackendOptim::Os || optimizeLevel == Runtime::BuildCfgBackendOptim::Oz;
    const bool     allow128        = optimize && !optimizeForSize && sizeInBytes >= 16;
    const uint32_t unrollLimit     = getUnrollMemLimit(buildCfg);

    auto& builder = codeGen.builder();

    const auto dstRegTmp   = codeGen.nextVirtualIntRegister();
    const auto srcReg      = codeGen.nextVirtualIntRegister();
    const auto tmpIntReg   = codeGen.nextVirtualIntRegister();
    const auto tmpFloatReg = allow128 ? codeGen.nextVirtualFloatRegister() : MicroReg::invalid();

    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitLoadRegReg(srcReg, srcAddressReg, MicroOpBits::B64);

    if (!optimize)
    {
        const auto countReg = codeGen.nextVirtualIntRegister();
        emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, 1, tmpIntReg, tmpFloatReg, countReg);
        return;
    }

    if (sizeInBytes <= unrollLimit)
    {
        emitMemCopyUnrolled(builder, dstRegTmp, srcReg, sizeInBytes, allow128, tmpIntReg, tmpFloatReg);
        return;
    }

    const auto     countReg  = codeGen.nextVirtualIntRegister();
    const uint32_t chunkSize = allow128 ? 16 : 8;
    emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, chunkSize, tmpIntReg, tmpFloatReg, countReg);
}

SWC_END_NAMESPACE();


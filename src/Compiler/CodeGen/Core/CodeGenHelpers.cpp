#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_DEFAULT_UNROLL_MEM_LIMIT = 256;

    MicroOpBits functionParameterLoadBits(bool isFloat, uint8_t numBits)
    {
        if (isFloat)
            return microOpBitsFromBitWidth(numBits);
        return MicroOpBits::B64;
    }

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

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemCopyChunk(builder, dstReg, srcReg, 0, chunkSize, tmpIntReg, tmpFloatReg);
        builder.emitOpBinaryRegImm(srcReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemCopyUnrolled(builder, dstReg, srcReg, tailSize, false, tmpIntReg, tmpFloatReg);
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

        const auto loopLabel = builder.createLabel();

        builder.emitLoadRegImm(countReg, ApInt(chunkCount, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitMemZeroChunk(builder, dstReg, 0, chunkSize, zeroReg);
        builder.emitOpBinaryRegImm(dstReg, ApInt(chunkSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);

        if (tailSize)
            emitMemZeroUnrolled(builder, dstReg, tailSize, zeroReg);
    }
}

CodeGenHelpers::FunctionParameterInfo CodeGenHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg)
{
    SWC_ASSERT(symVar.hasParameterIndex());

    FunctionParameterInfo                  result;
    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const uint32_t                         parameterIndex  = symVar.parameterIndex();
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);

    result.slotIndex     = hasIndirectReturnArg ? parameterIndex + 1 : parameterIndex;
    result.isFloat       = normalizedParam.isFloat;
    result.isIndirect    = normalizedParam.isIndirect;
    result.opBits        = functionParameterLoadBits(normalizedParam.isFloat, normalizedParam.numBits);
    result.isRegisterArg = result.slotIndex < callConv.numArgRegisterSlots();
    return result;
}

CodeGenHelpers::FunctionParameterInfo CodeGenHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    const CallConv&                        callConv      = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
    return functionParameterInfo(codeGen, symbolFunc, symVar, normalizedRet.isIndirect);
}

void CodeGenHelpers::emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg)
{
    const CallConv& callConv = CallConv::get(symbolFunc.callConvKind());
    MicroBuilder&   builder  = codeGen.builder();

    if (paramInfo.isRegisterArg)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.floatArgRegs.size());
            builder.emitLoadRegReg(dstReg, callConv.floatArgRegs[paramInfo.slotIndex], paramInfo.opBits);
        }
        else
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.intArgRegs.size());
            builder.emitLoadRegReg(dstReg, callConv.intArgRegs[paramInfo.slotIndex], paramInfo.opBits);
        }
    }
    else
    {
        const uint64_t frameOffset = ABICall::incomingArgFrameOffset(callConv, paramInfo.slotIndex);
        builder.emitLoadRegMem(dstReg, callConv.framePointer, frameOffset, paramInfo.opBits);
    }
}

CodeGenNodePayload CodeGenHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo)
{
    CodeGenNodePayload          outPayload;

    outPayload.typeRef = symVar.typeRef();
    outPayload.reg     = codeGen.nextVirtualRegisterForType(symVar.typeRef());
    emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, outPayload.reg);

    if (paramInfo.isIndirect)
        outPayload.setIsAddress();
    else
        outPayload.setIsValue();

    codeGen.setVariablePayload(symVar, outPayload);
    return outPayload;
}

CodeGenNodePayload CodeGenHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    const FunctionParameterInfo paramInfo = functionParameterInfo(codeGen, symbolFunc, symVar);
    return materializeFunctionParameter(codeGen, symbolFunc, symVar, paramInfo);
}

void CodeGenHelpers::emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    MicroBuilder&  builder         = codeGen.builder();
    const auto&    buildCfg        = builder.backendBuildCfg();
    const bool     optimize        = buildCfg.optimize;
    const bool     optimizeForSize = buildCfg.optimizeForSize;
    const bool     allow128        = optimize && !optimizeForSize && sizeInBytes >= 16;
    const uint32_t unrollLimit     = getUnrollMemLimit(buildCfg);

    const auto dstRegTmp   = codeGen.nextVirtualIntRegister();
    const auto srcReg      = codeGen.nextVirtualIntRegister();
    const auto tmpIntReg   = codeGen.nextVirtualIntRegister();
    const auto tmpFloatReg = allow128 ? codeGen.nextVirtualFloatRegister() : MicroReg::invalid();

    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitLoadRegReg(srcReg, srcAddressReg, MicroOpBits::B64);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemCopyUnrolled(builder, dstRegTmp, srcReg, sizeInBytes, false, tmpIntReg, tmpFloatReg);
            return;
        }

        const auto countReg = codeGen.nextVirtualIntRegister();
        emitMemCopyLoop(builder, dstRegTmp, srcReg, sizeInBytes, 8, tmpIntReg, tmpFloatReg, countReg);
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

void CodeGenHelpers::emitMemZero(CodeGen& codeGen, MicroReg dstReg, uint32_t sizeInBytes)
{
    if (!sizeInBytes)
        return;

    MicroBuilder&  builder       = codeGen.builder();
    const auto&    buildCfg      = builder.backendBuildCfg();
    const bool     optimize      = buildCfg.optimize;
    const uint32_t unrollLimit   = getUnrollMemLimit(buildCfg);

    const auto dstRegTmp = codeGen.nextVirtualIntRegister();
    const auto zeroReg   = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(dstRegTmp, dstReg, MicroOpBits::B64);
    builder.emitClearReg(zeroReg, MicroOpBits::B64);

    if (!optimize)
    {
        if (sizeInBytes <= unrollLimit)
        {
            emitMemZeroUnrolled(builder, dstRegTmp, sizeInBytes, zeroReg);
            return;
        }

        const auto countReg = codeGen.nextVirtualIntRegister();
        emitMemZeroLoop(builder, dstRegTmp, sizeInBytes, 8, zeroReg, countReg);
        return;
    }

    if (sizeInBytes <= unrollLimit)
    {
        emitMemZeroUnrolled(builder, dstRegTmp, sizeInBytes, zeroReg);
        return;
    }

    const auto countReg = codeGen.nextVirtualIntRegister();
    emitMemZeroLoop(builder, dstRegTmp, sizeInBytes, 8, zeroReg, countReg);
}

SWC_END_NAMESPACE();

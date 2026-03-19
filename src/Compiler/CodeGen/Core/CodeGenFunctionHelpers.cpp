#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool stackContainsRange(const std::byte* localStackBase, uint64_t localStackSize, const void* ptr, uint64_t size)
    {
        if (!localStackBase || !localStackSize || !ptr || !size)
            return false;

        const auto stackBase = reinterpret_cast<uintptr_t>(localStackBase);
        const auto ptrBase   = reinterpret_cast<uintptr_t>(ptr);
        if (ptrBase < stackBase)
            return false;

        const uint64_t offset = ptrBase - stackBase;
        return offset <= localStackSize && size <= localStackSize - offset;
    }

    Result persistCompilerRunValueRec(Sema& sema, DataSegment& segment, TypeRef typeRef, ByteSpanRW dstBytes, ByteSpan srcBytes, const std::byte* localStackBase, uint64_t localStackSize)
    {
        SWC_ASSERT(typeRef.isValid());
        SWC_ASSERT(dstBytes.size() == srcBytes.size());

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef rawTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            SWC_ASSERT(rawTypeRef.isValid());
            if (rawTypeRef.isInvalid())
                return Result::Error;
            return persistCompilerRunValueRec(sema, segment, rawTypeRef, dstBytes, srcBytes, localStackBase, localStackSize);
        }

        if (typeInfo.isEnum())
        {
            const TypeRef rawTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Enum);
            SWC_ASSERT(rawTypeRef.isValid());
            if (rawTypeRef.isInvalid())
                return Result::Error;
            return persistCompilerRunValueRec(sema, segment, rawTypeRef, dstBytes, srcBytes, localStackBase, localStackSize);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        SWC_ASSERT(sizeOf == dstBytes.size());
        SWC_ASSERT(sizeOf == srcBytes.size());
        if (sizeOf != dstBytes.size() || sizeOf != srcBytes.size())
            return Result::Error;

        if (sizeOf)
            std::memcpy(dstBytes.data(), srcBytes.data(), dstBytes.size());

        if (typeInfo.isString())
        {
            auto* const       dstString = reinterpret_cast<Runtime::String*>(dstBytes.data());
            const auto* const srcString = reinterpret_cast<const Runtime::String*>(srcBytes.data());
            if (!srcString->ptr || !srcString->length)
                return Result::Continue;

            if (!stackContainsRange(localStackBase, localStackSize, srcString->ptr, srcString->length))
                return Result::Continue;

            SWC_ASSERT(srcString->length <= std::numeric_limits<uint32_t>::max());
            const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(srcString->length), 1, false);
            SWC_UNUSED(dataOffset);
            std::memcpy(dataStorage, srcString->ptr, srcString->length);
            dstString->ptr    = reinterpret_cast<const char*>(dataStorage);
            dstString->length = srcString->length;
            return Result::Continue;
        }

        if (typeInfo.isSlice())
        {
            auto* const       dstSlice       = reinterpret_cast<Runtime::Slice<std::byte>*>(dstBytes.data());
            const auto* const srcSlice       = reinterpret_cast<const Runtime::Slice<std::byte>*>(srcBytes.data());
            const TypeRef     elementTypeRef = typeInfo.payloadTypeRef();
            const TypeInfo&   elementType    = sema.typeMgr().get(elementTypeRef);
            const uint64_t    elementSize    = elementType.sizeOf(ctx);
            const bool        scanElements   = SemaHelpers::needsPersistentCompilerRunReturn(sema, elementTypeRef);
            if (!srcSlice->ptr || !srcSlice->count || !elementSize)
                return Result::Continue;

            const uint64_t byteCount = srcSlice->count * elementSize;
            SWC_ASSERT(byteCount <= std::numeric_limits<uint32_t>::max());
            const bool mustClone = stackContainsRange(localStackBase, localStackSize, srcSlice->ptr, byteCount) || scanElements;
            if (!mustClone)
                return Result::Continue;

            const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(byteCount), elementType.alignOf(ctx), true);
            SWC_UNUSED(dataOffset);
            if (!scanElements)
            {
                std::memcpy(dataStorage, srcSlice->ptr, byteCount);
            }
            else
            {
                for (uint64_t idx = 0; idx < srcSlice->count; ++idx)
                {
                    const uint64_t elementOffset = idx * elementSize;
                    SWC_RESULT(persistCompilerRunValueRec(sema,
                                                          segment,
                                                          elementTypeRef,
                                                          ByteSpanRW{dataStorage + elementOffset, static_cast<size_t>(elementSize)},
                                                          ByteSpan{srcSlice->ptr + elementOffset, static_cast<size_t>(elementSize)},
                                                          localStackBase,
                                                          localStackSize));
                }
            }

            dstSlice->ptr   = dataStorage;
            dstSlice->count = srcSlice->count;
            return Result::Continue;
        }

        if (typeInfo.isArray())
        {
            const TypeRef elementTypeRef = typeInfo.payloadArrayElemTypeRef();
            if (!SemaHelpers::needsPersistentCompilerRunReturn(sema, elementTypeRef))
                return Result::Continue;

            const TypeInfo& elementType = sema.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize = elementType.sizeOf(ctx);
            SWC_ASSERT(elementSize != 0);
            if (!elementSize)
                return Result::Error;

            uint64_t totalCount = 1;
            for (const uint64_t dim : typeInfo.payloadArrayDims())
                totalCount *= dim;

            for (uint64_t idx = 0; idx < totalCount; ++idx)
            {
                const uint64_t elementOffset = idx * elementSize;
                SWC_RESULT(persistCompilerRunValueRec(sema,
                                                      segment,
                                                      elementTypeRef,
                                                      ByteSpanRW{dstBytes.data() + elementOffset, static_cast<size_t>(elementSize)},
                                                      ByteSpan{srcBytes.data() + elementOffset, static_cast<size_t>(elementSize)},
                                                      localStackBase,
                                                      localStackSize));
            }

            return Result::Continue;
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (!field || !SemaHelpers::needsPersistentCompilerRunReturn(sema, field->typeRef()))
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());
                if (fieldOffset + fieldSize > dstBytes.size())
                    return Result::Error;

                SWC_RESULT(persistCompilerRunValueRec(sema,
                                                      segment,
                                                      fieldTypeRef,
                                                      ByteSpanRW{dstBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)},
                                                      ByteSpan{srcBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)},
                                                      localStackBase,
                                                      localStackSize));
            }

            return Result::Continue;
        }

        return Result::Continue;
    }

    void persistCompilerRunValue(Sema* sema, uint64_t rawTypeRef, void* dst, const void* src, const void* localStackBase, uint64_t localStackSize)
    {
        SWC_ASSERT(sema);
        SWC_ASSERT(dst);
        SWC_ASSERT(src);

        const TypeRef typeRef{static_cast<uint32_t>(rawTypeRef)};
        SWC_ASSERT(typeRef.isValid());
        if (!typeRef.isValid())
            return;

        const TypeInfo& typeInfo = sema->typeMgr().get(typeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(sema->ctx());
        SWC_ASSERT(sizeOf > 0);
        SWC_ASSERT(sizeOf <= std::numeric_limits<uint32_t>::max());
        if (!sizeOf || sizeOf > std::numeric_limits<uint32_t>::max())
            return;

        DataSegment& segment = sema->compiler().compilerSegment();
        const Result result  = persistCompilerRunValueRec(*sema,
                                                          segment,
                                                          typeRef,
                                                          ByteSpanRW{static_cast<std::byte*>(dst), static_cast<size_t>(sizeOf)},
                                                          ByteSpan{static_cast<const std::byte*>(src), static_cast<size_t>(sizeOf)},
                                                          static_cast<const std::byte*>(localStackBase),
                                                          localStackSize);
        SWC_ASSERT(result == Result::Continue);
    }

    MicroOpBits functionParameterLoadBits(bool isFloat, uint8_t numBits)
    {
        if (isFloat)
            return microOpBitsFromBitWidth(numBits);
        return MicroOpBits::B64;
    }
}

bool CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef)
{
    return SemaHelpers::needsPersistentCompilerRunReturn(sema, typeRef);
}

bool CodeGenFunctionHelpers::functionUsesIndirectReturnStorage(CodeGen& codeGen, const SymbolFunction& symbolFunc)
{
    const TypeRef returnTypeRef = symbolFunc.returnTypeRef();
    if (!returnTypeRef.isValid())
        return false;

    const CallConv&                        callConv      = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
    return normalizedRet.isIndirect;
}

bool CodeGenFunctionHelpers::usesCallerReturnStorage(CodeGen& codeGen, const SymbolVariable& symVar)
{
    return symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) &&
           functionUsesIndirectReturnStorage(codeGen, codeGen.function());
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg, bool hasClosureContextArg)
{
    SWC_ASSERT(symVar.hasParameterIndex());

    FunctionParameterInfo                  result;
    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const uint32_t                         parameterIndex  = symVar.parameterIndex();
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);

    result.slotIndex     = parameterIndex + (hasIndirectReturnArg ? 1u : 0u) + (hasClosureContextArg ? 1u : 0u);
    result.isFloat       = normalizedParam.isFloat;
    result.isIndirect    = normalizedParam.isIndirect;
    result.opBits        = functionParameterLoadBits(normalizedParam.isFloat, normalizedParam.numBits);
    result.isRegisterArg = result.slotIndex < callConv.numArgRegisterSlots();
    return result;
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    return functionParameterInfo(codeGen, symbolFunc, symVar, functionUsesIndirectReturnStorage(codeGen, symbolFunc), symbolFunc.isClosure());
}

void CodeGenFunctionHelpers::emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg)
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

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo)
{
    if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
        return *symbolPayload;

    CodeGenNodePayload outPayload;

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

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    const FunctionParameterInfo paramInfo = functionParameterInfo(codeGen, symbolFunc, symVar);
    return materializeFunctionParameter(codeGen, symbolFunc, symVar, paramInfo);
}

void CodeGenFunctionHelpers::emitPersistCompilerRunValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstStorageReg, MicroReg srcStorageReg, MicroReg localStackBaseReg, uint32_t localStackSize)
{
    SWC_ASSERT(typeRef.isValid());
    SWC_ASSERT(dstStorageReg.isValid());
    SWC_ASSERT(srcStorageReg.isValid());

    constexpr auto callConvKind = CallConvKind::Host;

    MicroBuilder&  builder   = codeGen.builder();
    const MicroReg targetReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegPtrImm(targetReg, reinterpret_cast<uint64_t>(&persistCompilerRunValue));

    const MicroReg semaReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegPtrImm(semaReg, reinterpret_cast<uint64_t>(&codeGen.sema()));

    const MicroReg typeReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegImm(typeReg, ApInt(typeRef.get(), 64), MicroOpBits::B64);

    const MicroReg stackBaseReg = codeGen.nextVirtualIntRegister();
    if (localStackBaseReg.isValid())
        builder.emitLoadRegReg(stackBaseReg, localStackBaseReg, MicroOpBits::B64);
    else
        builder.emitLoadRegImm(stackBaseReg, ApInt(0, 64), MicroOpBits::B64);

    const MicroReg stackSizeReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegImm(stackSizeReg, ApInt(localStackSize, 64), MicroOpBits::B64);

    SmallVector<ABICall::PreparedArg> preparedArgs;
    preparedArgs.push_back({.srcReg = semaReg, .numBits = 64});
    preparedArgs.push_back({.srcReg = typeReg, .numBits = 64});
    preparedArgs.push_back({.srcReg = dstStorageReg, .numBits = 64});
    preparedArgs.push_back({.srcReg = srcStorageReg, .numBits = 64});
    preparedArgs.push_back({.srcReg = stackBaseReg, .numBits = 64});
    preparedArgs.push_back({.srcReg = stackSizeReg, .numBits = 64});

    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
    ABICall::callReg(builder, callConvKind, targetReg, preparedCall);
}

SWC_END_NAMESPACE();

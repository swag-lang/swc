#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/Command/CommandLine.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_WINDOWS_STACK_PROBE_PAGE_SIZE = 4096;

    const SymbolVariable* resolveCanonicalParameter(const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return nullptr;

        const auto& params = symbolFunc.parameters();
        if (symVar.hasParameterIndex() && symVar.parameterIndex() < params.size())
        {
            const SymbolVariable* canonicalParam = params[symVar.parameterIndex()];
            if (canonicalParam && canonicalParam != &symVar)
                return canonicalParam;
        }

        if (!symVar.idRef().isValid())
            return nullptr;

        for (const SymbolVariable* param : params)
        {
            if (!param || param == &symVar)
                continue;
            if (param->idRef() == symVar.idRef())
                return param;
        }

        return nullptr;
    }

    bool needsWindowsStackProbe(CodeGen& codeGen, uint64_t sizeInBytes)
    {
        return sizeInBytes > K_WINDOWS_STACK_PROBE_PAGE_SIZE &&
               codeGen.ctx().cmdLine().targetOs == Runtime::TargetOs::Windows;
    }

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

    Result persistCompilerRunValueRec(Sema& sema, DataSegment& segment, TypeRef typeRef, std::span<std::byte> dstBytes, std::span<const std::byte> srcBytes, const std::byte* localStackBase, uint64_t localStackSize)
    {
        SWC_ASSERT(typeRef.isValid());
        SWC_ASSERT(dstBytes.size() == srcBytes.size());

        TaskContext&       ctx      = sema.ctx();
        const TypeManager& typeMgr  = sema.typeMgr();
        const TypeInfo&    typeInfo = typeMgr.get(typeRef);
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
            auto* const dstString = reinterpret_cast<Runtime::String*>(dstBytes.data());
            const auto* srcString = reinterpret_cast<const Runtime::String*>(srcBytes.data());
            if (!srcString->ptr || !srcString->length)
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
            auto* const     dstSlice       = reinterpret_cast<Runtime::Slice<std::byte>*>(dstBytes.data());
            const auto*     srcSlice       = reinterpret_cast<const Runtime::Slice<std::byte>*>(srcBytes.data());
            const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
            const TypeInfo& elementType    = typeMgr.get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(ctx);
            const bool      scanElements   = SemaHelpers::needsPersistentCompilerRunReturn(sema, elementTypeRef);
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
                    SWC_RESULT(persistCompilerRunValueRec(sema, segment, elementTypeRef, std::span{dataStorage + elementOffset, static_cast<size_t>(elementSize)}, std::span{srcSlice->ptr + elementOffset, static_cast<size_t>(elementSize)}, localStackBase, localStackSize));
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

            const TypeInfo& elementType = typeMgr.get(elementTypeRef);
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
                SWC_RESULT(persistCompilerRunValueRec(sema, segment, elementTypeRef, std::span{dstBytes.data() + elementOffset, static_cast<size_t>(elementSize)}, std::span{srcBytes.data() + elementOffset, static_cast<size_t>(elementSize)}, localStackBase, localStackSize));
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
                const TypeInfo& fieldType    = typeMgr.get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());
                if (fieldOffset + fieldSize > dstBytes.size())
                    return Result::Error;

                SWC_RESULT(persistCompilerRunValueRec(sema, segment, fieldTypeRef, std::span{dstBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)}, std::span{srcBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)}, localStackBase, localStackSize));
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
        const Result result  = persistCompilerRunValueRec(*sema, segment, typeRef, std::span{static_cast<std::byte*>(dst), static_cast<size_t>(sizeOf)}, std::span{static_cast<const std::byte*>(src), static_cast<size_t>(sizeOf)}, static_cast<const std::byte*>(localStackBase), localStackSize);
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
    return symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) && functionUsesIndirectReturnStorage(codeGen, codeGen.function());
}

CodeGenNodePayload CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(CodeGen& codeGen, const SymbolVariable& symVar)
{
    SWC_ASSERT(usesCallerReturnStorage(codeGen, symVar));

    if (codeGen.hasCurrentFunctionIndirectReturnStackOffset())
    {
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef = symVar.typeRef();
        symbolPayload.setIsAddress();
        symbolPayload.reg = codeGen.ensureCurrentFunctionIndirectReturnReg(codeGen.function().callConvKind());
        return symbolPayload;
    }

    if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
        return *symbolPayload;

    CodeGenNodePayload symbolPayload;
    symbolPayload.typeRef = symVar.typeRef();
    symbolPayload.setIsAddress();
    symbolPayload.reg = codeGen.nextVirtualIntRegister();
    SWC_ASSERT(codeGen.currentFunctionIndirectReturnReg().isValid());
    codeGen.builder().emitLoadRegReg(symbolPayload.reg, codeGen.currentFunctionIndirectReturnReg(), MicroOpBits::B64);
    codeGen.builder().preserveVirtualCopy(symbolPayload.reg);
    SWC_ASSERT(symbolPayload.reg.isValid());
    codeGen.setVariablePayload(symVar, symbolPayload);
    return symbolPayload;
}

CodeGenNodePayload CodeGenFunctionHelpers::resolveClosureCapturePayload(CodeGen& codeGen, const SymbolVariable& symVar)
{
    SWC_ASSERT(symVar.isClosureCapture());
    SWC_ASSERT(codeGen.currentFunctionClosureContextReg().isValid());

    // Recompute the capture address from the closure context on every access
    // instead of caching it. A cached capture address (context + offset) is a
    // virtual register that stays live from the first to the last reference;
    // when those references straddle loops or calls (e.g. a nested closure built
    // when a popup opens), RegAlloc round-trips that long-lived value through the
    // spill machinery and can reload it from a slot that was never written on the
    // taken path. The context register itself is pinned to a persistent register,
    // so recomputing here keeps every derived address short-lived and spill-free.
    CodeGenNodePayload capturePayload;
    capturePayload.typeRef = symVar.typeRef();

    const MicroReg  captureReg = codeGen.offsetAddressReg(codeGen.currentFunctionClosureContextReg(), symVar.closureCaptureOffset());
    const TypeInfo& typeInfo   = codeGen.typeMgr().get(symVar.typeRef());
    if (typeInfo.isAnyVariadic())
    {
        capturePayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(capturePayload.reg, captureReg, 0, MicroOpBits::B64);
        capturePayload.setIsValue();
    }
    else if (symVar.closureCaptureByRef())
    {
        capturePayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(capturePayload.reg, captureReg, 0, MicroOpBits::B64);
        capturePayload.setIsAddress();
    }
    else
    {
        capturePayload.reg = captureReg;
        capturePayload.setIsAddress();
    }

    return capturePayload;
}

CodeGenNodePayload CodeGenFunctionHelpers::resolveStoredVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
{
    if (symVar.isClosureCapture())
        return resolveClosureCapturePayload(codeGen, symVar);

    if (usesCallerReturnStorage(codeGen, symVar))
        return resolveCallerReturnStoragePayload(codeGen, symVar);

    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        return materializeFunctionParameter(codeGen, symbolFunc, symVar);
    }

    if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
        return *symbolPayload;

    if (symVar.hasGlobalStorage())
    {
        CodeGenNodePayload globalPayload;
        globalPayload.typeRef = symVar.typeRef();
        globalPayload.setIsAddress();
        globalPayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, symVar.globalStorageKind(), symVar.offset());
        return globalPayload;
    }

    if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        return codeGen.resolveLocalStackPayload(symVar);

    if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
        return codeGen.resolveLocalStackPayload(symVar);

    SWC_UNREACHABLE();
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg, bool hasClosureContextArg)
{
    SWC_ASSERT(symVar.hasParameterIndex());

    FunctionParameterInfo                  result;
    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const uint32_t                         parameterIndex  = symVar.parameterIndex();
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);

    result.slotIndex         = parameterIndex + (hasIndirectReturnArg ? 1u : 0u) + (hasClosureContextArg ? 1u : 0u);
    result.isFloat           = normalizedParam.isFloat;
    result.isSigned          = normalizedParam.isSigned;
    result.isIndirect        = normalizedParam.isIndirect;
    result.needsIndirectCopy = normalizedParam.needsIndirectCopy;
    result.numBits           = normalizedParam.numBits;
    result.opBits            = functionParameterLoadBits(normalizedParam.isFloat, normalizedParam.numBits);
    result.isRegisterArg     = result.slotIndex < callConv.numArgRegisterSlots();
    return result;
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    return functionParameterInfo(codeGen, symbolFunc, symVar, functionUsesIndirectReturnStorage(codeGen, symbolFunc), symbolFunc.isClosure());
}

bool CodeGenFunctionHelpers::canUseIncomingIndirectParameterAsAddressableParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return false;
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage))
        return false;

    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);
    return normalizedParam.isIndirect;
}

bool CodeGenFunctionHelpers::isBorrowedIndirectParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return false;

    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);
    return normalizedParam.isIndirect && !normalizedParam.needsIndirectCopy;
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
            ABICall::loadCanonicalIntToReg(builder, dstReg, callConv.intArgRegs[paramInfo.slotIndex], paramInfo.numBits, paramInfo.isSigned);
        }
    }
    else
    {
        const uint64_t frameOffset = ABICall::incomingArgFrameOffset(callConv, paramInfo.slotIndex);
        if (paramInfo.isFloat)
            builder.emitLoadRegMem(dstReg, callConv.framePointer, frameOffset, paramInfo.opBits);
        else
            ABICall::loadCanonicalIntFromMemToReg(builder, dstReg, callConv.framePointer, frameOffset, paramInfo.numBits, paramInfo.isSigned);
    }
}

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo)
{
    const SymbolVariable* canonicalParam = resolveCanonicalParameter(symbolFunc, symVar);
    const SymbolVariable& payloadSym     = canonicalParam ? *canonicalParam : symVar;
    if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(payloadSym))
    {
        if (&payloadSym != &symVar)
            codeGen.setVariablePayload(symVar, *symbolPayload);
        return *symbolPayload;
    }

    if (payloadSym.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage) &&
        payloadSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
        codeGen.localStackBaseReg().isValid())
    {
        const CodeGenNodePayload payload = codeGen.resolveLocalStackPayload(payloadSym);
        if (&payloadSym != &symVar)
            codeGen.setVariablePayload(symVar, payload);
        return payload;
    }

    FunctionParameterInfo effectiveParamInfo = paramInfo;
    if (&payloadSym != &symVar)
        effectiveParamInfo = functionParameterInfo(codeGen, symbolFunc, payloadSym);

    CodeGenNodePayload outPayload;
    outPayload.typeRef = payloadSym.typeRef();
    outPayload.reg     = codeGen.nextVirtualRegisterForType(payloadSym.typeRef());
    emitLoadFunctionParameterToReg(codeGen, symbolFunc, effectiveParamInfo, outPayload.reg);

    if (effectiveParamInfo.isIndirect)
        outPayload.setIsAddress();
    else
        outPayload.setIsValue();

    codeGen.setVariablePayload(payloadSym, outPayload);
    if (&payloadSym != &symVar)
        codeGen.setVariablePayload(symVar, outPayload);
    return outPayload;
}

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    const FunctionParameterInfo paramInfo = functionParameterInfo(codeGen, symbolFunc, symVar);
    return materializeFunctionParameter(codeGen, symbolFunc, symVar, paramInfo);
}

uint32_t CodeGenFunctionHelpers::checkedTypeSizeInBytes(CodeGen& codeGen, const TypeInfo& typeInfo)
{
    const uint64_t rawSize = typeInfo.sizeOf(codeGen.ctx());
    SWC_ASSERT(rawSize > 0 && rawSize <= std::numeric_limits<uint32_t>::max());
    return static_cast<uint32_t>(rawSize);
}

bool CodeGenFunctionHelpers::shouldMaterializeAddressBackedValue(CodeGen& codeGen, const TypeInfo& typeInfo, bool isIndirect, bool isFloat, uint8_t numBits)
{
    if (isIndirect)
        return false;
    if (isFloat)
        return false;
    if (numBits != 64)
        return false;

    return typeInfo.sizeOf(codeGen.ctx()) > sizeof(uint64_t);
}

namespace
{
    TypeRef unwrapDefaultStorageTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (rawTypeRef.isValid())
            return rawTypeRef;
        return typeRef;
    }

    MicroReg addressWithOffset(CodeGen& codeGen, MicroReg baseReg, uint32_t offset)
    {
        if (!offset)
            return baseReg;

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegReg(resultReg, baseReg, MicroOpBits::B64);
        codeGen.builder().emitOpBinaryRegImm(resultReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
        return resultReg;
    }

    bool canEmitDefaultPayloadBytesInline(CodeGen& codeGen, TypeRef typeRef)
    {
        typeRef                  = unwrapDefaultStorageTypeRef(codeGen, typeRef);
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat())
            return true;

        if (typeInfo.isArray())
            return canEmitDefaultPayloadBytesInline(codeGen, typeInfo.payloadArrayElemTypeRef());

        if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
        {
            for (const TypeRef childTypeRef : typeInfo.payloadAggregate().types)
            {
                if (!canEmitDefaultPayloadBytesInline(codeGen, childTypeRef))
                    return false;
            }

            return true;
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (field && !canEmitDefaultPayloadBytesInline(codeGen, field->typeRef()))
                    return false;
            }

            return true;
        }

        return false;
    }

    bool emitZeroOrSparsePayloadBytes(CodeGen& codeGen, MicroReg dstAddressReg, std::span<const std::byte> rawBytes, bool allowNonZeroStores)
    {
        if (rawBytes.empty())
            return true;

        if (std::ranges::all_of(rawBytes, [](const std::byte value) { return value == std::byte{}; }))
        {
            CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, static_cast<uint32_t>(rawBytes.size()));
            return true;
        }
        if (!allowNonZeroStores)
            return false;

        constexpr uint32_t sparseChunkSize  = 8;
        constexpr uint32_t sparseStoreLimit = 4;
        if (rawBytes.size() >= sparseChunkSize * 2ull && (rawBytes.size() % sparseChunkSize) == 0)
        {
            uint32_t nonZeroChunks = 0;
            for (uint32_t off = 0; off < rawBytes.size(); off += sparseChunkSize)
            {
                for (uint32_t i = 0; i < sparseChunkSize; ++i)
                {
                    if (rawBytes[off + i] != std::byte{})
                    {
                        ++nonZeroChunks;
                        break;
                    }
                }

                if (nonZeroChunks > sparseStoreLimit)
                    break;
            }

            if (nonZeroChunks <= sparseStoreLimit)
            {
                MicroBuilder& builder = codeGen.builder();
                CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, static_cast<uint32_t>(rawBytes.size()));
                for (uint32_t off = 0; off < rawBytes.size(); off += sparseChunkSize)
                {
                    uint64_t value = 0;
                    for (uint32_t i = 0; i < sparseChunkSize; ++i)
                        value |= static_cast<uint64_t>(static_cast<uint8_t>(rawBytes[off + i])) << (i * 8);
                    if (value != 0)
                        builder.emitLoadMemImm(dstAddressReg, off, ApInt(value, 64), MicroOpBits::B64);
                }

                return true;
            }
        }

        return false;
    }

    Result materializeStaticDefaultPayload(CodeGen& codeGen, ConstantRef& outPayloadRef, std::span<const std::byte>& outPayloadBytes, TypeRef typeRef, std::span<const std::byte> payloadBytes)
    {
        outPayloadRef   = ConstantRef::invalid();
        outPayloadBytes = {};

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const uint64_t  size     = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(size == payloadBytes.size());
        SWC_ASSERT(size <= std::numeric_limits<uint32_t>::max());
        if (!size || size != payloadBytes.size() || size > std::numeric_limits<uint32_t>::max())
            return Result::Continue;

        DataSegment& segment = codeGen.cstMgr().shardDataSegment(0);
        uint32_t     offset  = INVALID_REF;
        SWC_RESULT(ConstantLower::materializeStaticPayload(offset, codeGen.sema(), segment, typeRef, payloadBytes));
        SWC_ASSERT(offset != INVALID_REF);

        std::byte* storedBytes = segment.ptr<std::byte>(offset);
        SWC_ASSERT(storedBytes);
        if (!storedBytes)
            return Result::Continue;

        outPayloadBytes          = std::span{storedBytes, static_cast<size_t>(size)};
        ConstantValue payloadCst = ConstantValue::makeStructBorrowed(codeGen.ctx(), typeRef, outPayloadBytes);
        payloadCst.setDataSegmentRef({.shardIndex = 0, .offset = offset});
        outPayloadRef = codeGen.cstMgr().addMaterializedPayloadConstant(payloadCst);
        return Result::Continue;
    }

    Result emitDefaultConstantToAddress(CodeGen& codeGen, TypeRef typeRef, ConstantRef valueRef, MicroReg dstAddressReg)
    {
        const TypeInfo&        typeInfo = codeGen.typeMgr().get(typeRef);
        const uint32_t         size     = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        SmallVector<std::byte> payloadBytes;
        payloadBytes.resize(size);
        SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), std::span{payloadBytes.data(), payloadBytes.size()}, valueRef, typeRef));
        const bool canEmitInline = canEmitDefaultPayloadBytesInline(codeGen, typeRef);
        if (emitZeroOrSparsePayloadBytes(codeGen, dstAddressReg, std::span{payloadBytes.data(), payloadBytes.size()}, canEmitInline))
            return Result::Continue;

        auto storeBits = MicroOpBits::Zero;
        if (size == 1)
            storeBits = MicroOpBits::B8;
        else if (size == 2)
            storeBits = MicroOpBits::B16;
        else if (size == 4)
            storeBits = MicroOpBits::B32;
        else if (size == 8)
            storeBits = MicroOpBits::B64;
        if (canEmitInline && storeBits != MicroOpBits::Zero)
        {
            uint64_t value = 0;
            for (uint32_t i = 0; i < size; ++i)
                value |= static_cast<uint64_t>(static_cast<uint8_t>(payloadBytes[i])) << (i * 8);
            codeGen.builder().emitLoadMemImm(dstAddressReg, 0, ApInt(value, 64), storeBits);
            return Result::Continue;
        }

        ConstantRef                payloadRef;
        std::span<const std::byte> materializedPayload;
        SWC_RESULT(materializeStaticDefaultPayload(codeGen, payloadRef, materializedPayload, typeRef, std::span{payloadBytes.data(), payloadBytes.size()}));
        SWC_ASSERT(payloadRef.isValid());
        if (payloadRef.isInvalid())
            return Result::Continue;

        const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(materializedPayload.data()), payloadRef);
        CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, payloadReg, size);
        return Result::Continue;
    }

    Result emitArrayDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg);

    Result emitImplicitDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg)
    {
        typeRef                  = unwrapDefaultStorageTypeRef(codeGen, typeRef);
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isStruct())
            return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, typeRef, dstAddressReg);
        if (typeInfo.isArray())
            return emitArrayDefaultValue(codeGen, typeRef, dstAddressReg);
        if (SymbolStruct::typeRequiresExplicitInitialization(codeGen.sema(), typeRef))
            return Result::Continue;

        const uint32_t size = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, size);
        return Result::Continue;
    }

    Result emitArrayDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg)
    {
        const TypeInfo& arrayType = codeGen.typeMgr().get(typeRef);
        SWC_ASSERT(arrayType.isArray());

        const TypeRef   elemTypeRef = arrayType.payloadArrayElemTypeRef();
        const TypeInfo& elemType    = codeGen.typeMgr().get(elemTypeRef);
        const uint32_t  elemSize    = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, elemType);
        uint64_t        elemCount   = 1;
        for (const uint64_t dim : arrayType.payloadArrayDims())
            elemCount *= dim;
        if (!elemCount)
            return Result::Continue;

        SWC_ASSERT(elemCount <= std::numeric_limits<uint32_t>::max());
        const TypeRef   storageElemTypeRef = unwrapDefaultStorageTypeRef(codeGen, elemTypeRef);
        const TypeInfo& storageElemType    = codeGen.typeMgr().get(storageElemTypeRef);
        if (storageElemType.isStruct())
            return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, storageElemTypeRef, dstAddressReg, static_cast<uint32_t>(elemCount));
        if (!storageElemType.isArray())
        {
            if (SymbolStruct::typeRequiresExplicitInitialization(codeGen.sema(), storageElemTypeRef))
                return Result::Continue;

            const uint64_t totalSize = elemCount * elemSize;
            SWC_ASSERT(totalSize <= std::numeric_limits<uint32_t>::max());
            CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, static_cast<uint32_t>(totalSize));
            return Result::Continue;
        }

        for (uint64_t i = 0; i < elemCount; ++i)
        {
            const uint64_t offset = i * elemSize;
            SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
            const MicroReg elemAddressReg = addressWithOffset(codeGen, dstAddressReg, static_cast<uint32_t>(offset));
            SWC_RESULT(emitArrayDefaultValue(codeGen, storageElemTypeRef, elemAddressReg));
        }

        return Result::Continue;
    }

    Result emitStructPartialDefaultValue(CodeGen& codeGen, const TypeInfo& typeInfo, MicroReg dstAddressReg)
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (!field || field->hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
                continue;

            const TypeRef   fieldTypeRef = field->typeRef();
            const TypeInfo& fieldType    = codeGen.typeMgr().get(fieldTypeRef);
            const uint32_t  fieldSize    = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, fieldType);
            if (!fieldSize)
                continue;

            const MicroReg    fieldAddressReg = addressWithOffset(codeGen, dstAddressReg, field->offset());
            const ConstantRef defaultValueRef = field->defaultValueRef();
            if (defaultValueRef.isValid())
                SWC_RESULT(emitDefaultConstantToAddress(codeGen, fieldTypeRef, defaultValueRef, fieldAddressReg));
            else
                SWC_RESULT(emitImplicitDefaultValue(codeGen, fieldTypeRef, fieldAddressReg));
        }

        return Result::Continue;
    }

    bool tryGetStructDefaultPayload(CodeGen& codeGen, TypeRef typeRef, ConstantRef& outSafeDefaultValueRef, std::span<const std::byte>& outPayloadBytes)
    {
        outSafeDefaultValueRef = ConstantRef::invalid();
        outPayloadBytes        = {};

        const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid())
            typeRef = rawTypeRef;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (!typeInfo.isStruct())
            return false;

        const ConstantRef defaultValueRef = typeInfo.payloadSymStruct().resolveImplicitDefaultValueRef(codeGen.sema(), typeRef);
        if (defaultValueRef.isInvalid())
            return false;

        outSafeDefaultValueRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, defaultValueRef, typeRef);
        if (outSafeDefaultValueRef.isInvalid())
            return false;

        const ConstantValue& defaultValue = codeGen.cstMgr().get(outSafeDefaultValueRef);
        if (!defaultValue.isStruct())
            return false;

        outPayloadBytes = defaultValue.getStruct();
        return true;
    }
}

Result CodeGenFunctionHelpers::emitTypeDefaultValue(CodeGen& codeGen, const TypeRef typeRef, const MicroReg dstAddressReg)
{
    return emitImplicitDefaultValue(codeGen, typeRef, dstAddressReg);
}

Result CodeGenFunctionHelpers::emitStructDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg)
{
    const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
    if (rawTypeRef.isValid())
        typeRef = rawTypeRef;

    const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
    if (!typeInfo.isStruct())
        return Result::Continue;

    const auto& symStruct = typeInfo.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(codeGen.sema());
    if (symStruct.hasImplicitAllUndefinedDefault())
        return Result::Continue;
    if (symStruct.hasImplicitAllZeroDefault())
    {
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, checkedTypeSizeInBytes(codeGen, typeInfo));
        return Result::Continue;
    }
    if (symStruct.hasImplicitUndefinedDefault() || symStruct.requiresExplicitInitialization())
        return emitStructPartialDefaultValue(codeGen, typeInfo, dstAddressReg);

    ConstantRef                safeDefaultValueRef = ConstantRef::invalid();
    std::span<const std::byte> payloadBytes;
    if (!tryGetStructDefaultPayload(codeGen, typeRef, safeDefaultValueRef, payloadBytes))
        return Result::Continue;

    SWC_ASSERT(payloadBytes.size() <= std::numeric_limits<uint32_t>::max());
    if (emitZeroOrSparsePayloadBytes(codeGen, dstAddressReg, payloadBytes, canEmitDefaultPayloadBytesInline(codeGen, typeRef)))
        return Result::Continue;

    const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payloadBytes.data()), safeDefaultValueRef);
    CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, payloadReg, static_cast<uint32_t>(payloadBytes.size()));
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitStructDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg, uint32_t count)
{
    if (!count)
        return Result::Continue;
    if (count == 1)
        return emitStructDefaultValue(codeGen, typeRef, dstAddressReg);

    const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
    if (rawTypeRef.isValid())
        typeRef = rawTypeRef;

    const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
    if (!typeInfo.isStruct())
        return Result::Continue;

    const auto& symStruct = typeInfo.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(codeGen.sema());
    if (symStruct.hasImplicitAllUndefinedDefault())
        return Result::Continue;

    const uint32_t sizeOf = checkedTypeSizeInBytes(codeGen, typeInfo);
    if (symStruct.hasImplicitAllZeroDefault())
    {
        const uint64_t totalSize = static_cast<uint64_t>(sizeOf) * count;
        SWC_ASSERT(totalSize <= std::numeric_limits<uint32_t>::max());
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, static_cast<uint32_t>(totalSize));
        return Result::Continue;
    }
    if (symStruct.hasImplicitUndefinedDefault() || symStruct.requiresExplicitInitialization())
    {
        for (uint32_t i = 0; i < count; ++i)
        {
            const uint64_t offset = static_cast<uint64_t>(sizeOf) * i;
            SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
            const MicroReg elemAddressReg = addressWithOffset(codeGen, dstAddressReg, static_cast<uint32_t>(offset));
            SWC_RESULT(emitStructPartialDefaultValue(codeGen, typeInfo, elemAddressReg));
        }

        return Result::Continue;
    }

    ConstantRef                safeDefaultValueRef = ConstantRef::invalid();
    std::span<const std::byte> payloadBytes;
    if (!tryGetStructDefaultPayload(codeGen, typeRef, safeDefaultValueRef, payloadBytes))
        return Result::Continue;

    const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payloadBytes.data()), safeDefaultValueRef);
    CodeGenMemoryHelpers::emitMemRepeatCopy(codeGen, dstAddressReg, payloadReg, sizeOf, count);
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitStructDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg, MicroReg countReg)
{
    const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
    if (rawTypeRef.isValid())
        typeRef = rawTypeRef;

    const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
    if (!typeInfo.isStruct())
        return Result::Continue;

    const auto& symStruct = typeInfo.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(codeGen.sema());
    if (symStruct.hasImplicitAllUndefinedDefault())
        return Result::Continue;

    const uint32_t sizeOf    = checkedTypeSizeInBytes(codeGen, typeInfo);
    MicroBuilder&  builder   = codeGen.builder();
    const auto     loopLabel = builder.createLabel();
    const auto     doneLabel = builder.createLabel();
    const auto     cursorReg = codeGen.nextVirtualIntRegister();
    const auto     iterReg   = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(cursorReg, dstAddressReg, MicroOpBits::B64);
    builder.emitLoadRegReg(iterReg, countReg, MicroOpBits::B64);
    builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

    builder.placeLabel(loopLabel);
    if (symStruct.hasImplicitAllZeroDefault())
        CodeGenMemoryHelpers::emitMemZero(codeGen, cursorReg, sizeOf);
    else
        SWC_RESULT(emitStructDefaultValue(codeGen, typeRef, cursorReg));
    builder.emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(iterReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitTypeDefaultValue(CodeGen& codeGen, TypeRef typeRef, const MicroReg dstAddressReg, const uint32_t count)
{
    if (!count)
        return Result::Continue;

    const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
    if (rawTypeRef.isValid())
        typeRef = rawTypeRef;

    const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
    if (typeInfo.isStruct())
        return emitStructDefaultValue(codeGen, typeRef, dstAddressReg, count);
    if (count == 1)
        return emitTypeDefaultValue(codeGen, typeRef, dstAddressReg);

    const uint32_t sizeOf = checkedTypeSizeInBytes(codeGen, typeInfo);
    for (uint32_t i = 0; i < count; ++i)
    {
        const uint64_t offset = static_cast<uint64_t>(sizeOf) * i;
        SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
        const MicroReg elemAddressReg = addressWithOffset(codeGen, dstAddressReg, static_cast<uint32_t>(offset));
        SWC_RESULT(emitTypeDefaultValue(codeGen, typeRef, elemAddressReg));
    }

    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitTypeDefaultValue(CodeGen& codeGen, TypeRef typeRef, const MicroReg dstAddressReg, const MicroReg countReg)
{
    const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
    if (rawTypeRef.isValid())
        typeRef = rawTypeRef;

    const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
    if (typeInfo.isStruct())
        return emitStructDefaultValue(codeGen, typeRef, dstAddressReg, countReg);

    const uint32_t sizeOf    = checkedTypeSizeInBytes(codeGen, typeInfo);
    MicroBuilder&  builder   = codeGen.builder();
    const auto     loopLabel = builder.createLabel();
    const auto     doneLabel = builder.createLabel();
    const auto     cursorReg = codeGen.nextVirtualIntRegister();
    const auto     iterReg   = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(cursorReg, dstAddressReg, MicroOpBits::B64);
    builder.emitLoadRegReg(iterReg, countReg, MicroOpBits::B64);
    builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

    builder.placeLabel(loopLabel);
    SWC_RESULT(emitTypeDefaultValue(codeGen, typeRef, cursorReg));
    builder.emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(iterReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

void CodeGenFunctionHelpers::emitStackPointerSubtract(CodeGen& codeGen, const CallConv& callConv, uint64_t sizeInBytes, MicroReg scratchReg)
{
    if (!sizeInBytes)
        return;

    MicroBuilder& builder = codeGen.builder();
    if (!needsWindowsStackProbe(codeGen, sizeInBytes))
    {
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(sizeInBytes, 64), MicroOp::Subtract, MicroOpBits::B64);
        return;
    }

    SWC_ASSERT(scratchReg.isValid() && scratchReg != callConv.stackPointer);
    if (!scratchReg.isValid() || scratchReg == callConv.stackPointer)
    {
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(sizeInBytes, 64), MicroOp::Subtract, MicroOpBits::B64);
        return;
    }

    uint64_t remaining = sizeInBytes;
    while (remaining > K_WINDOWS_STACK_PROBE_PAGE_SIZE)
    {
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(K_WINDOWS_STACK_PROBE_PAGE_SIZE, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadRegMem(scratchReg, callConv.stackPointer, 0, MicroOpBits::B64);
        remaining -= K_WINDOWS_STACK_PROBE_PAGE_SIZE;
    }

    if (remaining)
    {
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(remaining, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadRegMem(scratchReg, callConv.stackPointer, 0, MicroOpBits::B64);
    }
}

bool CodeGenFunctionHelpers::tryUseCurrentFunctionReturnStorageForDirectExpr(CodeGen& codeGen, AstNodeRef nodeRef, MicroReg& outStorageReg)
{
    outStorageReg = MicroReg::invalid();
    if (!codeGen.currentFunctionIndirectReturnReg().isValid() && !codeGen.hasCurrentFunctionIndirectReturnStackOffset())
        return false;

    const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
    if (!resolvedNodeRef.isValid())
        return false;

    for (size_t parentIndex = 0;; ++parentIndex)
    {
        const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
        if (!parentRef.isValid())
            return false;

        const AstNode& parent = codeGen.node(parentRef);
        if (parent.is(AstNodeId::CastExpr) || parent.is(AstNodeId::AutoCastExpr) || parent.is(AstNodeId::ParenExpr))
            continue;

        if (parent.isNot(AstNodeId::ReturnStmt))
            return false;

        const auto&      returnNode        = parent.cast<AstReturnStmt>();
        const AstNodeRef resolvedReturnRef = codeGen.viewZero(returnNode.nodeExprRef).nodeRef();
        if (resolvedReturnRef != resolvedNodeRef)
            return false;

        outStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(codeGen.function().callConvKind());
        return true;
    }
}

void CodeGenFunctionHelpers::emitPersistCompilerRunValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstStorageReg, MicroReg srcStorageReg, MicroReg localStackBaseReg, uint32_t localStackSize)
{
    SWC_ASSERT(typeRef.isValid());
    SWC_ASSERT(dstStorageReg.isValid());
    SWC_ASSERT(srcStorageReg.isValid());

    constexpr auto callConvKind = CallConvKind::C;

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

    const CallConv& callConv = CallConv::get(callConvKind);
    CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
    ABICall::callReg(builder, callConvKind, targetReg, preparedCall);
}

SWC_END_NAMESPACE();

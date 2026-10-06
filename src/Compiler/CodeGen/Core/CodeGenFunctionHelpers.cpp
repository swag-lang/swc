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
#include "Compiler/CodeGen/Core/CodeGenExprView.h"
#include "Compiler/CodeGen/Core/CodeGenGlobalVariablePayload.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
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
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

Result CodeGenFunctionHelpers::emitMoveValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstReg, MicroReg sourceReg, AstNodeRef sourceRef)
{
    CodeGenNodePayload source;
    source.reg     = sourceReg;
    source.typeRef = typeRef;
    source.setIsAddress();
    CodeGenMemoryHelpers::storePayloadToAddress(codeGen, dstReg, source, checkedTypeSizeInBytes(codeGen, codeGen.typeMgr().get(typeRef)));
    SWC_RESULT(CodeGenMemoryHelpers::emitDynamicIdentity(codeGen, typeRef, dstReg));
    if (codeGen.hasLifecycle(typeRef, CodeGen::LifecycleKind::PostMove))
        SWC_RESULT(codeGen.emitLifecycle(typeRef, CodeGen::LifecycleKind::PostMove, dstReg));
    if (codeGen.hasLifecycle(typeRef, CodeGen::LifecycleKind::Drop))
        SWC_RESULT(emitMovedFromDefaultValue(codeGen, typeRef, sourceReg));
    else if (CodeGenSafety::hasLifecycleInvalidate(codeGen))
    {
        sourceRef = SemaHelpers::resolveTransparentExprSourceRef(codeGen.sema(), sourceRef);
        while (sourceRef.isValid() && codeGen.node(sourceRef).is(AstNodeId::ParenExpr))
            sourceRef = codeGen.node(sourceRef).cast<AstParenExpr>().nodeExprRef;
        if (sourceRef.isValid() && codeGen.node(sourceRef).is(AstNodeId::UnaryExpr) &&
            codeGen.token(codeGen.node(sourceRef).codeRef()).id == TokenId::ModifierMove)
            sourceRef = codeGen.node(sourceRef).cast<AstUnaryExpr>().nodeExprRef;
        SWC_RESULT(CodeGenSafety::emitLifecycleInvalidate(codeGen, sourceReg, typeRef, sourceRef));
    }
    return Result::Continue;
}

namespace
{
    constexpr uint64_t K_WINDOWS_STACK_PROBE_PAGE_SIZE = 4096;

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

    Result persistCompilerRunValueRec(TaskContext& ctx, DataSegment& segment, const TypeInfo& typeInfo, std::span<std::byte> dstBytes, std::span<const std::byte> srcBytes, const std::byte* localStackBase, uint64_t localStackSize)
    {
        const TypeRef typeRef = typeInfo.typeRef();
        SWC_ASSERT(typeRef.isValid());
        SWC_ASSERT(dstBytes.size() == srcBytes.size());

        const TypeManager& typeMgr = ctx.typeMgr();
        if (typeInfo.isAlias())
        {
            const TypeRef rawTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            SWC_ASSERT(rawTypeRef.isValid());
            if (rawTypeRef.isInvalid())
                return Result::Error;
            return persistCompilerRunValueRec(ctx, segment, typeMgr.get(rawTypeRef), dstBytes, srcBytes, localStackBase, localStackSize);
        }

        if (typeInfo.isEnum())
        {
            const TypeRef rawTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Enum);
            SWC_ASSERT(rawTypeRef.isValid());
            if (rawTypeRef.isInvalid())
                return Result::Error;
            return persistCompilerRunValueRec(ctx, segment, typeMgr.get(rawTypeRef), dstBytes, srcBytes, localStackBase, localStackSize);
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
            if (!srcSlice->ptr || !srcSlice->count || !elementSize)
                return Result::Continue;

            const bool     scanElements = SemaHelpers::needsPersistentCompilerRunReturn(ctx, elementTypeRef);
            const uint64_t byteCount    = srcSlice->count * elementSize;
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
                    SWC_RESULT(persistCompilerRunValueRec(ctx, segment, elementType, std::span{dataStorage + elementOffset, static_cast<size_t>(elementSize)}, std::span{srcSlice->ptr + elementOffset, static_cast<size_t>(elementSize)}, localStackBase, localStackSize));
                }
            }

            dstSlice->ptr   = dataStorage;
            dstSlice->count = srcSlice->count;
            return Result::Continue;
        }

        if (typeInfo.isArray())
        {
            const TypeRef elementTypeRef = typeInfo.payloadArrayElemTypeRef();
            if (!SemaHelpers::needsPersistentCompilerRunReturn(ctx, elementTypeRef))
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
                SWC_RESULT(persistCompilerRunValueRec(ctx, segment, elementType, std::span{dstBytes.data() + elementOffset, static_cast<size_t>(elementSize)}, std::span{srcBytes.data() + elementOffset, static_cast<size_t>(elementSize)}, localStackBase, localStackSize));
            }

            return Result::Continue;
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (!field || !SemaHelpers::needsPersistentCompilerRunReturn(ctx, field->typeRef()))
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = typeMgr.get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());
                if (fieldOffset + fieldSize > dstBytes.size())
                    return Result::Error;

                SWC_RESULT(persistCompilerRunValueRec(ctx, segment, fieldType, std::span{dstBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)}, std::span{srcBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)}, localStackBase, localStackSize));
            }

            return Result::Continue;
        }

        return Result::Continue;
    }

    // Generated code calls back here with the compiler instance, not with the code-generation
    // Sema that emitted the call: a '#run' executes after its CodeGenJob has finished and
    // released that Sema, while the instance outlives every job of its module.
    void persistCompilerRunValue(CompilerInstance* compiler, uint64_t rawTypeRef, void* dst, const void* src, const void* localStackBase, uint64_t localStackSize)
    {
        SWC_ASSERT(compiler);
        SWC_ASSERT(dst);
        SWC_ASSERT(src);

        const TypeRef typeRef{static_cast<uint32_t>(rawTypeRef)};
        SWC_ASSERT(typeRef.isValid());
        if (!typeRef.isValid())
            return;

        TaskContext     ctx(*compiler);
        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(ctx);
        SWC_ASSERT(sizeOf > 0);
        SWC_ASSERT(sizeOf <= std::numeric_limits<uint32_t>::max());
        if (!sizeOf || sizeOf > std::numeric_limits<uint32_t>::max())
            return;

        DataSegment& segment = compiler->compilerSegment();
        const Result result  = persistCompilerRunValueRec(ctx, segment, typeInfo, std::span{static_cast<std::byte*>(dst), static_cast<size_t>(sizeOf)}, std::span{static_cast<const std::byte*>(src), static_cast<size_t>(sizeOf)}, static_cast<const std::byte*>(localStackBase), localStackSize);
        SWC_ASSERT(result == Result::Continue);
    }

    MicroOpBits functionParameterLoadBits(bool isFloat, uint8_t numBits)
    {
        if (isFloat)
            return microOpBitsFromBitWidth(numBits);
        return MicroOpBits::B64;
    }
}

bool CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(const TaskContext& ctx, TypeRef typeRef)
{
    return SemaHelpers::needsPersistentCompilerRunReturn(ctx, typeRef);
}

bool CodeGenFunctionHelpers::functionUsesIndirectReturnStorage(CodeGen& codeGen, const SymbolFunction& symbolFunc)
{
    const TypeRef returnTypeRef = symbolFunc.returnTypeRef();
    if (!returnTypeRef.isValid())
        return false;

    const CallConv&                        callConv      = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(returnTypeRef), ABITypeNormalize::Usage::Return);
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
        return CodeGenMemoryHelpers::globalVariableAddressPayload(codeGen, symVar);
    }

    if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        return codeGen.resolveLocalStackPayload(symVar);

    if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
        return codeGen.resolveLocalStackPayload(symVar);

    SWC_UNREACHABLE();
}

namespace
{
    void setParameterTypeInfo(CodeGenFunctionHelpers::FunctionParameterInfo& result, const ABITypeNormalize::NormalizedType& type, uint32_t slotIndex)
    {
        result.slotIndex         = slotIndex;
        result.isFloat           = type.isFloat;
        result.isSigned          = type.isSigned;
        result.isIndirect        = type.isIndirect;
        result.needsIndirectCopy = type.needsIndirectCopy;
        result.numBits           = type.numBits;
        result.opBits            = functionParameterLoadBits(type.isFloat, type.numBits);
    }

    void setParameterLocationInfo(CodeGenFunctionHelpers::FunctionParameterInfo& result, const CallConv& callConv, std::span<const ABICall::ArgLayout> argLayouts, uint32_t registerIndex)
    {
        result.registerIndex = registerIndex;
        result.isRegisterArg = result.registerIndex != UINT32_MAX;
        // Only stack arguments load from an incoming frame slot.
        result.stackOffset = result.isRegisterArg ? 0 : ABICall::incomingArgFrameOffset(callConv, argLayouts, result.slotIndex);
    }
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg, bool hasClosureContextArg)
{
    SWC_ASSERT(symVar.hasParameterIndex());

    FunctionParameterInfo                  result;
    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const uint32_t                         parameterIndex  = symVar.parameterIndex();
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(symVar.typeRef()), ABITypeNormalize::Usage::Argument);

    setParameterTypeInfo(result, normalizedParam, parameterIndex + (hasIndirectReturnArg ? 1u : 0u) + (hasClosureContextArg ? 1u : 0u));

    // Register lanes and incoming stack offsets depend only on this prefix.
    // Register home offsets would need the full layout, but are not used here.
    const auto& params = symbolFunc.parameters();
    SWC_ASSERT(parameterIndex < params.size());
    SWC_ASSERT(params[parameterIndex] == &symVar);
    SmallVector<ABICall::ArgLayout> argLayouts;
    argLayouts.reserve(result.slotIndex + 1);
    if (hasIndirectReturnArg)
        argLayouts.push_back({});
    if (hasClosureContextArg)
        argLayouts.push_back({});
    for (uint32_t i = 0; i < parameterIndex; ++i)
    {
        const SymbolVariable* param = params[i];
        SWC_ASSERT(param != nullptr);
        const ABITypeNormalize::NormalizedType type = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(param->typeRef()), ABITypeNormalize::Usage::Argument);
        argLayouts.push_back({.numBits = static_cast<uint8_t>(type.numBits ? type.numBits : 64), .isFloat = type.isFloat});
    }
    argLayouts.push_back({.numBits = static_cast<uint8_t>(normalizedParam.numBits ? normalizedParam.numBits : 64), .isFloat = normalizedParam.isFloat});
    setParameterLocationInfo(result, callConv, argLayouts, ABICall::argumentRegisterIndex(callConv, argLayouts, result.slotIndex));
    return result;
}

CodeGenFunctionHelpers::FunctionParameterInfo CodeGenFunctionHelpers::functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    return functionParameterInfo(codeGen, symbolFunc, symVar, functionUsesIndirectReturnStorage(codeGen, symbolFunc), symbolFunc.isClosure());
}

void CodeGenFunctionHelpers::fillFunctionParameterInfos(CodeGen& codeGen, std::span<FunctionParameterInfo> outParamInfos, const SymbolFunction& symbolFunc, bool hasIndirectReturnArg, bool hasClosureContextArg)
{
    const auto& params = symbolFunc.parameters();
    SWC_ASSERT(outParamInfos.size() == params.size());

    const CallConv& callConv       = CallConv::get(symbolFunc.callConvKind());
    const uint32_t  hiddenArgCount = (hasIndirectReturnArg ? 1u : 0u) + (hasClosureContextArg ? 1u : 0u);

    // Hidden return and closure pointers precede the declared parameters in the integer bank.
    ABICall::ArgRegisterState registerState{.intLane = hiddenArgCount};
    ABICall::ArgStackState    stackState;

    for (size_t i = 0; i < params.size(); ++i)
    {
        const SymbolVariable* param = params[i];
        SWC_ASSERT(param != nullptr && param->hasParameterIndex());
        SWC_ASSERT(param->parameterIndex() == i);
        const ABITypeNormalize::NormalizedType type      = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(param->typeRef()), ABITypeNormalize::Usage::Argument);
        const uint32_t                         slotIndex = param->parameterIndex() + hiddenArgCount;
        FunctionParameterInfo&                 paramInfo = outParamInfos[i];
        setParameterTypeInfo(paramInfo, type, slotIndex);
        paramInfo.registerIndex = registerState.next(callConv, slotIndex, type.isFloat);
        paramInfo.isRegisterArg = paramInfo.registerIndex != UINT32_MAX;
        paramInfo.stackOffset   = paramInfo.isRegisterArg ? 0 : 2 * sizeof(void*) + stackState.next(callConv, static_cast<uint8_t>(type.numBits ? type.numBits : 64));
    }
}

void CodeGenFunctionHelpers::fillFunctionParameterInfos(CodeGen& codeGen, std::span<FunctionParameterInfo> outParamInfos, const SymbolFunction& symbolFunc)
{
    fillFunctionParameterInfos(codeGen, outParamInfos, symbolFunc, functionUsesIndirectReturnStorage(codeGen, symbolFunc), symbolFunc.isClosure());
}

bool CodeGenFunctionHelpers::canUseIncomingIndirectParameterAsAddressableParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo* paramInfo)
{
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return false;
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage))
        return false;
    if (paramInfo)
        return paramInfo->isIndirect;

    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(symVar.typeRef()), ABITypeNormalize::Usage::Argument);
    return normalizedParam.isIndirect;
}

bool CodeGenFunctionHelpers::isBorrowedIndirectParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo* paramInfo)
{
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return false;

    if (paramInfo)
        return paramInfo->isIndirect && !paramInfo->needsIndirectCopy;

    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().get(symVar.typeRef()), ABITypeNormalize::Usage::Argument);
    return normalizedParam.isIndirect && !normalizedParam.needsIndirectCopy;
}

bool CodeGenFunctionHelpers::isByValueAggregateParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo* paramInfo)
{
    // An aggregate small enough for the ABI to pass in a register still needs a memory home in
    // the callee: the body reads it through its address. The prologue gives such a parameter a
    // local slot and spills the incoming register there.
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return false;

    TaskContext&  ctx     = codeGen.ctx();
    const TypeRef typeRef = symVar.typeRef();
    if (!typeRef.isValid())
        return false;

    const TypeInfo& paramType     = ctx.typeMgr().get(typeRef);
    const TypeInfo* unwrappedType = paramType.unwrapAliasEnumType(ctx);
    const TypeInfo& storageType   = unwrappedType ? *unwrappedType : paramType;
    if (!storageType.isStruct() && !storageType.isArray() && !storageType.isAggregate())
        return false;
    if (paramInfo)
        return !paramInfo->isIndirect;

    const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(ctx, callConv, storageType, ABITypeNormalize::Usage::Argument);
    return !normalizedParam.isIndirect;
}

bool CodeGenFunctionHelpers::isImmutableIndirectParameter(CodeGen& codeGen, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo)
{
    if (!paramInfo.isIndirect || !symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return false;

    // A parameter whose address the body takes can be written through that address.
    if (symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage))
        return false;

    TaskContext&  ctx     = codeGen.ctx();
    const TypeRef typeRef = symVar.typeRef();
    if (!typeRef.isValid())
        return false;

    // Only the value handles qualify. A struct parameter is read through the caller's storage,
    // and code relies on seeing what happens to that storage during the call: a thread body
    // takes its 'Thread' by value and polls the stop flag another thread sets. An array
    // parameter is a view the callee itself writes through.
    const TypeInfo& paramType     = ctx.typeMgr().get(typeRef);
    const TypeInfo* unwrappedType = paramType.unwrapAliasEnumType(ctx);
    const TypeInfo& storageType   = unwrappedType ? *unwrappedType : paramType;
    return storageType.isString() || storageType.isSlice() || storageType.isInterface() || storageType.isAny();
}

void CodeGenFunctionHelpers::markImmutableIndirectParameter(CodeGen& codeGen, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo, MicroReg reg)
{
    if (isImmutableIndirectParameter(codeGen, symVar, paramInfo))
        codeGen.builder().markImmutableStorageBase(reg, true);
}

void CodeGenFunctionHelpers::emitLocalStackFrameEpilogue(CodeGen& codeGen, CallConvKind callConvKind)
{
    if (!codeGen.hasLocalStackFrame())
        return;

    const CallConv& callConv = CallConv::get(callConvKind);
    MicroBuilder&   builder  = codeGen.builder();
    builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(codeGen.localStackFrameSize(), 64), MicroOp::Add, MicroOpBits::B64);
}

bool CodeGenFunctionHelpers::canUseDirectCallReturnWriteBack(const AstNode& exprNode, const CodeGenNodePayload& payload, bool returnIsVoid, bool returnIsIndirect)
{
    if (returnIsVoid || returnIsIndirect)
        return false;
    if (exprNode.isNot(AstNodeId::CallExpr))
        return false;
    return payload.isValue();
}

void CodeGenFunctionHelpers::emitLocalStackFramePrologue(CodeGen& codeGen, CallConvKind callConvKind)
{
    if (!codeGen.hasLocalStackFrame())
        return;

    const CallConv& callConv  = CallConv::get(callConvKind);
    MicroBuilder&   builder   = codeGen.builder();
    const uint32_t  frameSize = codeGen.localStackFrameSize();
    SWC_ASSERT(frameSize != 0);

    // RegAlloc picks the physical register for the frame base. Forbidding every transient
    // (caller-saved) one, plus the stack and frame pointers, leaves only persistent registers,
    // so neither a call nor later instruction selection can clobber the active frame base.
    const MicroReg        frameBaseReg  = codeGen.nextVirtualIntRegister();
    SmallVector<MicroReg> forbiddenRegs = callConv.intTransientRegs;
    forbiddenRegs.push_back(callConv.stackPointer);
    if (callConv.framePointer.isValid())
        forbiddenRegs.push_back(callConv.framePointer);
    builder.addVirtualRegForbiddenPhysRegs(frameBaseReg, forbiddenRegs.span());

    builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(frameSize, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);
    codeGen.setLocalStackBaseReg(frameBaseReg);
    codeGen.function().setDebugStackFrameSize(frameSize);
    codeGen.function().setDebugStackBaseReg(frameBaseReg);
}

const SymbolVariable* CodeGenFunctionHelpers::resolveCanonicalParameter(const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
{
    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        return nullptr;

    const auto& params = symbolFunc.parameters();
    if (symVar.hasParameterIndex() && symVar.parameterIndex() < params.size())
    {
        const SymbolVariable* canonicalParam = params[symVar.parameterIndex()];
        // The indexed symbol already proves this is the canonical parameter.
        if (canonicalParam == &symVar)
            return nullptr;
        if (canonicalParam)
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

void CodeGenFunctionHelpers::emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg)
{
    const CallConv& callConv = CallConv::get(symbolFunc.callConvKind());
    MicroBuilder&   builder  = codeGen.builder();

    if (paramInfo.isRegisterArg)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.registerIndex < callConv.floatArgRegs.size());
            builder.emitLoadRegReg(dstReg, callConv.floatArgRegs[paramInfo.registerIndex], paramInfo.opBits);
        }
        else
        {
            SWC_ASSERT(paramInfo.registerIndex < callConv.intArgRegs.size());
            ABICall::loadCanonicalIntToReg(builder, dstReg, callConv.intArgRegs[paramInfo.registerIndex], paramInfo.numBits, paramInfo.isSigned);
        }
    }
    else
    {
        if (paramInfo.isFloat)
            builder.emitLoadRegMem(dstReg, callConv.framePointer, paramInfo.stackOffset, paramInfo.opBits);
        else
            ABICall::loadCanonicalIntFromMemToReg(builder, dstReg, callConv.framePointer, paramInfo.stackOffset, paramInfo.numBits, paramInfo.isSigned);
    }
}

CodeGenNodePayload CodeGenFunctionHelpers::materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo* paramInfo)
{
    const SymbolVariable* canonicalParam = resolveCanonicalParameter(symbolFunc, symVar);
    const SymbolVariable& payloadSym     = canonicalParam ? *canonicalParam : symVar;
    if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(payloadSym))
    {
        if (&payloadSym != &symVar)
            codeGen.setVariablePayload(symVar, *symbolPayload);
        return *symbolPayload;
    }

    if (payloadSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
        codeGen.localStackBaseReg().isValid() &&
        (payloadSym.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage) || isByValueAggregateParameter(codeGen, symbolFunc, payloadSym)))
    {
        const CodeGenNodePayload payload = codeGen.resolveLocalStackPayload(payloadSym);
        if (&payloadSym != &symVar)
            codeGen.setVariablePayload(symVar, payload);
        return payload;
    }

    // Existing payloads and local homes need no ABI layout. Resolve it only
    // for a load, using supplied metadata when it describes the canonical symbol.
    const FunctionParameterInfo effectiveParamInfo = paramInfo && &payloadSym == &symVar ? *paramInfo : functionParameterInfo(codeGen, symbolFunc, payloadSym);

    CodeGenNodePayload outPayload;
    outPayload.typeRef = payloadSym.typeRef();
    outPayload.reg     = codeGen.nextVirtualRegisterForType(payloadSym.typeRef());
    emitLoadFunctionParameterToReg(codeGen, symbolFunc, effectiveParamInfo, outPayload.reg);
    markImmutableIndirectParameter(codeGen, payloadSym, effectiveParamInfo, outPayload.reg);

    if (effectiveParamInfo.isIndirect)
        outPayload.setIsAddress();
    else
        outPayload.setIsValue();

    codeGen.setVariablePayload(payloadSym, outPayload);
    if (&payloadSym != &symVar)
        codeGen.setVariablePayload(symVar, outPayload);
    return outPayload;
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
    MicroReg addressWithOffset(CodeGen& codeGen, MicroReg baseReg, uint32_t offset)
    {
        if (!offset)
            return baseReg;

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegReg(resultReg, baseReg, MicroOpBits::B64);
        codeGen.builder().emitOpBinaryRegImm(resultReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
        return resultReg;
    }

    bool canEmitDefaultPayloadBytesInline(CodeGen& codeGen, const TypeInfo& declaredType)
    {
        const TypeInfo* unwrappedType = declaredType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo& typeInfo      = unwrappedType ? *unwrappedType : declaredType;

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat())
            return true;

        if (typeInfo.isArray())
            return canEmitDefaultPayloadBytesInline(codeGen, codeGen.typeMgr().get(typeInfo.payloadArrayElemTypeRef()));

        if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
        {
            for (const TypeRef childTypeRef : typeInfo.payloadAggregate().types)
            {
                if (!canEmitDefaultPayloadBytesInline(codeGen, codeGen.typeMgr().get(childTypeRef)))
                    return false;
            }

            return true;
        }

        if (typeInfo.isStruct())
        {
            if (typeInfo.payloadSymStruct().hasDynamicStorage())
                return false;
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (field && !canEmitDefaultPayloadBytesInline(codeGen, codeGen.typeMgr().get(field->typeRef())))
                    return false;
            }

            return true;
        }

        return false;
    }

    Result materializeStaticDefaultPayload(CodeGen& codeGen, ConstantRef& outPayloadRef, std::span<const std::byte>& outPayloadBytes, const TypeInfo& typeInfo, std::span<const std::byte> payloadBytes)
    {
        outPayloadRef   = ConstantRef::invalid();
        outPayloadBytes = {};

        const TypeRef  typeRef = typeInfo.typeRef();
        const uint64_t size    = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(size == payloadBytes.size());
        SWC_ASSERT(size <= std::numeric_limits<uint32_t>::max());
        if (!size || size != payloadBytes.size() || size > std::numeric_limits<uint32_t>::max())
            return Result::Continue;

        DataSegment& segment = codeGen.cstMgr().shardDataSegment(0);
        uint32_t     offset  = INVALID_REF;
        SWC_RESULT(ConstantLower::materializeStaticPayload(codeGen.sema(), offset, segment, typeInfo, payloadBytes));
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

    Result emitDefaultConstantToAddress(CodeGen& codeGen, const TypeInfo& typeInfo, ConstantRef valueRef, MicroReg dstAddressReg)
    {
        const uint32_t       size  = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        const ConstantValue& value = codeGen.cstMgr().get(valueRef);
        if ((value.isStruct() || value.isArray()) && value.isPayloadBorrowed() && value.dataSegmentRef().isValid() && ConstantHelpers::typeHasUnionStorage(codeGen.ctx(), typeInfo))
        {
            // Construction already identified the live relocations. A raw byte round trip
            // would lose that inventory and reinterpret inactive union alternatives.
            const auto payload = value.isStruct() ? value.getStruct() : value.getArray();
            SWC_ASSERT(payload.size() == size);
            const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payload.data()), valueRef);
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, payloadReg, size);
            return Result::Continue;
        }
        SmallVector<std::byte> payloadBytes;
        payloadBytes.resize(size);
        SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), std::span{payloadBytes.data(), payloadBytes.size()}, valueRef, typeInfo));
        const bool canEmitInline = canEmitDefaultPayloadBytesInline(codeGen, typeInfo);
        if (CodeGenMemoryHelpers::emitZeroOrSparsePayloadBytes(codeGen, dstAddressReg, std::span{payloadBytes.data(), payloadBytes.size()}, canEmitInline))
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
        SWC_RESULT(materializeStaticDefaultPayload(codeGen, payloadRef, materializedPayload, typeInfo, std::span{payloadBytes.data(), payloadBytes.size()}));
        SWC_ASSERT(payloadRef.isValid());
        if (payloadRef.isInvalid())
            return Result::Continue;

        const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(materializedPayload.data()), payloadRef);
        CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, payloadReg, size);
        return Result::Continue;
    }

    Result emitArrayDefaultValue(CodeGen& codeGen, const TypeInfo& arrayType, MicroReg dstAddressReg);

    Result emitImplicitDefaultValue(CodeGen& codeGen, const TypeInfo& declaredType, MicroReg dstAddressReg)
    {
        const TypeInfo* storageType = declaredType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo& typeInfo    = storageType ? *storageType : declaredType;
        const TypeRef   typeRef     = typeInfo.typeRef();
        if (typeInfo.isStruct())
            return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, typeInfo, dstAddressReg);
        if (typeInfo.isArray())
            return emitArrayDefaultValue(codeGen, typeInfo, dstAddressReg);
        if (SymbolStruct::typeRequiresExplicitInitialization(codeGen.sema(), typeRef))
            return Result::Continue;

        const uint32_t size = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, size);
        return Result::Continue;
    }

    Result emitArrayDefaultValue(CodeGen& codeGen, const TypeInfo& arrayType, MicroReg dstAddressReg)
    {
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
        const TypeInfo* unwrappedElemType = elemType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo& storageElemType   = unwrappedElemType ? *unwrappedElemType : elemType;
        if (storageElemType.isStruct())
            return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, storageElemType, dstAddressReg, static_cast<uint32_t>(elemCount));
        if (!storageElemType.isArray())
        {
            if (SymbolStruct::typeRequiresExplicitInitialization(codeGen.sema(), storageElemType.typeRef()))
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
            SWC_RESULT(emitArrayDefaultValue(codeGen, storageElemType, elemAddressReg));
        }

        return Result::Continue;
    }

    Result emitStructFieldDefaultValue(CodeGen& codeGen, const SymbolVariable& field, const TypeInfo& fieldType, uint32_t fieldSize, MicroReg dstAddressReg)
    {
        if (!fieldSize)
            return Result::Continue;

        const MicroReg fieldAddressReg = addressWithOffset(codeGen, dstAddressReg, field.offset());

        // A 'late' field is typed non-null, so the generic implicit-default
        // path would skip it ("needs explicit initialization"). Its storage
        // must instead start as null so a presence comparison reads false: zero it.
        if (field.hasExtraFlag(SymbolVariableFlagsE::LateInit))
        {
            CodeGenMemoryHelpers::emitMemZero(codeGen, fieldAddressReg, fieldSize);
            return Result::Continue;
        }

        const ConstantRef defaultValueRef = field.defaultValueRef();
        if (defaultValueRef.isValid())
            SWC_RESULT(emitDefaultConstantToAddress(codeGen, fieldType, defaultValueRef, fieldAddressReg));
        else
            SWC_RESULT(emitImplicitDefaultValue(codeGen, fieldType, fieldAddressReg));

        return Result::Continue;
    }

    Result emitStructPartialDefaultValue(CodeGen& codeGen, const TypeInfo& typeInfo, MicroReg dstAddressReg)
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (field)
            {
                const TypeInfo& fieldType = codeGen.typeMgr().get(field->typeRef());
                const uint32_t  fieldSize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, fieldType);
                SWC_RESULT(emitStructFieldDefaultValue(codeGen, *field, fieldType, fieldSize, dstAddressReg));
            }
        }

        return CodeGenMemoryHelpers::emitDynamicIdentity(codeGen, typeInfo.payloadSymStruct().typeRef(), dstAddressReg);
    }

    bool shouldComposeLargeSparseStructDefault(CodeGen& codeGen, const TypeInfo& typeInfo, std::span<const std::byte> payloadBytes)
    {
        constexpr uint64_t MIN_COMPOSED_SIZE     = 64 * 1024;
        constexpr uint64_t MAX_NON_ZERO_FRACTION = 8;
        if (payloadBytes.size() < MIN_COMPOSED_SIZE)
            return false;

        const uint64_t maxNonZeroBytes = payloadBytes.size() / MAX_NON_ZERO_FRACTION;
        uint64_t       nonZeroBytes    = 0;
        for (const std::byte value : payloadBytes)
        {
            if (value != std::byte{} && ++nonZeroBytes > maxNonZeroBytes)
                return false;
        }

        uint64_t initializedEnd = 0;
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (!field)
                continue;

            const uint64_t fieldOffset = field->offset();
            const uint64_t fieldSize   = codeGen.typeMgr().get(field->typeRef()).sizeOf(codeGen.ctx());
            if (fieldOffset < initializedEnd)
                return false;
            initializedEnd = fieldOffset + fieldSize;
        }

        return initializedEnd <= payloadBytes.size();
    }

    Result emitStructComposedDefaultValue(CodeGen& codeGen, const TypeInfo& typeInfo, MicroReg dstAddressReg)
    {
        uint32_t initializedEnd = 0;
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (!field)
                continue;

            const TypeInfo& fieldType   = codeGen.typeMgr().get(field->typeRef());
            const uint32_t  fieldSize   = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, fieldType);
            const uint32_t  fieldOffset = field->offset();
            SWC_ASSERT(fieldOffset >= initializedEnd);
            if (fieldOffset > initializedEnd)
            {
                const MicroReg paddingAddressReg = addressWithOffset(codeGen, dstAddressReg, initializedEnd);
                CodeGenMemoryHelpers::emitMemZero(codeGen, paddingAddressReg, fieldOffset - initializedEnd);
            }

            SWC_RESULT(emitStructFieldDefaultValue(codeGen, *field, fieldType, fieldSize, dstAddressReg));
            initializedEnd = fieldOffset + fieldSize;
        }

        const uint32_t structSize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        SWC_ASSERT(initializedEnd <= structSize);
        if (initializedEnd < structSize)
        {
            const MicroReg paddingAddressReg = addressWithOffset(codeGen, dstAddressReg, initializedEnd);
            CodeGenMemoryHelpers::emitMemZero(codeGen, paddingAddressReg, structSize - initializedEnd);
        }

        return CodeGenMemoryHelpers::emitDynamicIdentity(codeGen, typeInfo.payloadSymStruct().typeRef(), dstAddressReg);
    }

    Result lowerStructDefaultPayload(CodeGen& codeGen, SmallVector<std::byte>& outStorage, std::span<const std::byte>& outPayloadBytes, const TypeInfo& typeInfo)
    {
        outStorage.clear();
        outPayloadBytes = {};

        SWC_ASSERT(typeInfo.isStruct());
        const uint32_t size = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        outStorage.resize(size);
        SWC_RESULT(SymbolStruct::lowerTypeImplicitDefaultBytes(codeGen.sema(), std::span{outStorage.data(), outStorage.size()}, typeInfo.typeRef()));

        outPayloadBytes = std::span{outStorage.data(), outStorage.size()};
        return Result::Continue;
    }

    Result materializeStructDefaultPayload(CodeGen& codeGen, ConstantRef& outSafeDefaultValueRef, std::span<const std::byte>& outPayloadBytes, const TypeInfo& typeInfo)
    {
        const TypeRef typeRef = typeInfo.typeRef();
        SWC_ASSERT(typeInfo.isStruct());
        ConstantRef defaultValueRef = ConstantRef::invalid();
        SWC_RESULT(typeInfo.payloadSymStruct().resolveImplicitDefaultValueRef(codeGen.sema(), typeRef, defaultValueRef));
        if (defaultValueRef.isInvalid())
            return typeInfo.payloadSymStruct().hasRuntimeImplicitDefault() ? Result::Continue : Result::Error;

        outSafeDefaultValueRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, defaultValueRef, typeRef);
        if (outSafeDefaultValueRef.isInvalid())
            return Result::Error;

        const ConstantValue& defaultValue = codeGen.cstMgr().get(outSafeDefaultValueRef);
        if (!defaultValue.isStruct())
            return Result::Error;

        outPayloadBytes = defaultValue.getStruct();
        return Result::Continue;
    }
}

Result CodeGenFunctionHelpers::emitTypeDefaultValue(CodeGen& codeGen, const TypeRef typeRef, const MicroReg dstAddressReg)
{
    return emitImplicitDefaultValue(codeGen, codeGen.typeMgr().get(typeRef), dstAddressReg);
}

Result CodeGenFunctionHelpers::emitMovedFromDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg)
{
    const TypeInfo& declaredType  = codeGen.typeMgr().get(typeRef);
    const TypeInfo* unwrappedType = declaredType.unwrapAliasEnumType(codeGen.ctx());
    const TypeInfo& type          = unwrappedType ? *unwrappedType : declaredType;
    if (!type.isStruct() || !type.payloadSymStruct().isDynamic())
        return emitImplicitDefaultValue(codeGen, type, dstAddressReg);

    // Moving out resets user fields, but does not turn an embedded base into a standalone
    // object. Ordinary members and array elements already have their declared root identity.
    const auto            slots = type.payloadSymStruct().dynamicSlotOffsets();
    SmallVector<MicroReg> identities;
    for (const uint32_t offset : slots)
    {
        const MicroReg identity = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(identity, dstAddressReg, offset, MicroOpBits::B64);
        identities.push_back(identity);
    }
    SWC_RESULT(emitImplicitDefaultValue(codeGen, type, dstAddressReg));
    for (size_t i = 0; i < slots.size(); ++i)
        codeGen.builder().emitLoadMemReg(dstAddressReg, slots[i], identities[i], MicroOpBits::B64);
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitStructDefaultValue(CodeGen& codeGen, const TypeInfo& declaredType, MicroReg dstAddressReg)
{
    const TypeInfo* unwrappedType = declaredType.unwrapAliasType(codeGen.ctx());
    const TypeInfo& typeInfo      = unwrappedType ? *unwrappedType : declaredType;
    if (!typeInfo.isStruct())
        return Result::Continue;

    const auto& symStruct = typeInfo.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(codeGen.sema());
    if (symStruct.hasRuntimeImplicitDefault())
    {
        if (const SymbolFunction* init = symStruct.opaqueInit(codeGen.ctx()))
        {
            const MicroReg args[] = {dstAddressReg};
            return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *init, args);
        }
        return symStruct.isUnion() ? emitStructPartialDefaultValue(codeGen, typeInfo, dstAddressReg) : emitStructComposedDefaultValue(codeGen, typeInfo, dstAddressReg);
    }
    if (symStruct.hasImplicitAllZeroDefault())
    {
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, checkedTypeSizeInBytes(codeGen, typeInfo));
        return Result::Continue;
    }
    if (symStruct.requiresExplicitInitialization())
        return emitStructPartialDefaultValue(codeGen, typeInfo, dstAddressReg);

    SmallVector<std::byte>     payloadStorage;
    std::span<const std::byte> payloadBytes;
    SWC_RESULT(lowerStructDefaultPayload(codeGen, payloadStorage, payloadBytes, typeInfo));

    SWC_ASSERT(payloadBytes.size() <= std::numeric_limits<uint32_t>::max());
    if (CodeGenMemoryHelpers::emitZeroOrSparsePayloadBytes(codeGen, dstAddressReg, payloadBytes, canEmitDefaultPayloadBytesInline(codeGen, typeInfo)))
        return Result::Continue;
    if (shouldComposeLargeSparseStructDefault(codeGen, typeInfo, payloadBytes))
        return emitStructComposedDefaultValue(codeGen, typeInfo, dstAddressReg);

    ConstantRef safeDefaultValueRef = ConstantRef::invalid();
    SWC_RESULT(materializeStructDefaultPayload(codeGen, safeDefaultValueRef, payloadBytes, typeInfo));
    // Construction can discover a partial write over a relocated pointer only while
    // resolving the default. Complete that write against the runtime address instead.
    if (safeDefaultValueRef.isInvalid() && symStruct.hasRuntimeImplicitDefault())
        return symStruct.isUnion() ? emitStructPartialDefaultValue(codeGen, typeInfo, dstAddressReg) : emitStructComposedDefaultValue(codeGen, typeInfo, dstAddressReg);

    const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payloadBytes.data()), safeDefaultValueRef);
    CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, payloadReg, static_cast<uint32_t>(payloadBytes.size()));
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitStructDefaultValue(CodeGen& codeGen, const TypeInfo& declaredType, MicroReg dstAddressReg, uint32_t count)
{
    if (!count)
        return Result::Continue;
    if (count == 1)
        return emitStructDefaultValue(codeGen, declaredType, dstAddressReg);

    const TypeInfo* unwrappedType = declaredType.unwrapAliasType(codeGen.ctx());
    const TypeInfo& typeInfo      = unwrappedType ? *unwrappedType : declaredType;
    if (!typeInfo.isStruct())
        return Result::Continue;

    const auto& symStruct = typeInfo.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(codeGen.sema());
    const uint32_t sizeOf = checkedTypeSizeInBytes(codeGen, typeInfo);
    if (symStruct.hasImplicitAllZeroDefault())
    {
        const uint64_t totalSize = static_cast<uint64_t>(sizeOf) * count;
        SWC_ASSERT(totalSize <= std::numeric_limits<uint32_t>::max());
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, static_cast<uint32_t>(totalSize));
        return Result::Continue;
    }
    ConstantRef                safeDefaultValueRef = ConstantRef::invalid();
    std::span<const std::byte> payloadBytes;
    if (!symStruct.requiresExplicitInitialization() && !symStruct.hasRuntimeImplicitDefault())
        SWC_RESULT(materializeStructDefaultPayload(codeGen, safeDefaultValueRef, payloadBytes, typeInfo));
    if (symStruct.requiresExplicitInitialization() || symStruct.hasRuntimeImplicitDefault())
    {
        for (uint32_t i = 0; i < count; ++i)
        {
            const uint64_t offset = static_cast<uint64_t>(sizeOf) * i;
            SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
            const MicroReg elemAddressReg = addressWithOffset(codeGen, dstAddressReg, static_cast<uint32_t>(offset));
            SWC_RESULT(emitStructDefaultValue(codeGen, typeInfo, elemAddressReg));
        }

        return Result::Continue;
    }

    const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payloadBytes.data()), safeDefaultValueRef);
    CodeGenMemoryHelpers::emitMemRepeatCopy(codeGen, dstAddressReg, payloadReg, sizeOf, count);
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitStructDefaultValue(CodeGen& codeGen, const TypeInfo& declaredType, MicroReg dstAddressReg, MicroReg countReg)
{
    const TypeInfo* unwrappedType = declaredType.unwrapAliasType(codeGen.ctx());
    const TypeInfo& typeInfo      = unwrappedType ? *unwrappedType : declaredType;
    if (!typeInfo.isStruct())
        return Result::Continue;

    const auto& symStruct = typeInfo.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(codeGen.sema());
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
        SWC_RESULT(emitStructDefaultValue(codeGen, typeInfo, cursorReg));
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

    const TypeInfo& declaredType  = codeGen.typeMgr().get(typeRef);
    const TypeInfo* unwrappedType = declaredType.unwrapAliasType(codeGen.ctx());
    const TypeInfo& typeInfo      = unwrappedType ? *unwrappedType : declaredType;
    if (typeInfo.isStruct())
        return emitStructDefaultValue(codeGen, typeInfo, dstAddressReg, count);
    if (count == 1)
        return emitImplicitDefaultValue(codeGen, typeInfo, dstAddressReg);

    const uint32_t sizeOf = checkedTypeSizeInBytes(codeGen, typeInfo);
    if (!typeInfo.isArray() && !typeInfo.isEnum())
    {
        if (SymbolStruct::typeRequiresExplicitInitialization(codeGen.sema(), typeInfo.typeRef()))
            return Result::Continue;

        // These defaults only zero storage. Emit one contiguous fill instead of generating
        // an address and a separate initialization for every element in a constant count.
        const uint64_t totalSize = static_cast<uint64_t>(sizeOf) * count;
        if (totalSize <= std::numeric_limits<uint32_t>::max())
        {
            CodeGenMemoryHelpers::emitMemZero(codeGen, dstAddressReg, static_cast<uint32_t>(totalSize));
            return Result::Continue;
        }
    }

    for (uint32_t i = 0; i < count; ++i)
    {
        const uint64_t offset = static_cast<uint64_t>(sizeOf) * i;
        SWC_ASSERT(offset <= std::numeric_limits<uint32_t>::max());
        const MicroReg elemAddressReg = addressWithOffset(codeGen, dstAddressReg, static_cast<uint32_t>(offset));
        SWC_RESULT(emitImplicitDefaultValue(codeGen, typeInfo, elemAddressReg));
    }

    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitTypeDefaultValue(CodeGen& codeGen, TypeRef typeRef, const MicroReg dstAddressReg, const MicroReg countReg)
{
    const TypeInfo& declaredType  = codeGen.typeMgr().get(typeRef);
    const TypeInfo* unwrappedType = declaredType.unwrapAliasType(codeGen.ctx());
    const TypeInfo& typeInfo      = unwrappedType ? *unwrappedType : declaredType;
    if (typeInfo.isStruct())
        return emitStructDefaultValue(codeGen, typeInfo, dstAddressReg, countReg);

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
    SWC_RESULT(emitImplicitDefaultValue(codeGen, typeInfo, cursorReg));
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

// Directly initialize `var x = expr` into x's storage. Calls use this for their hidden
// return pointer, and inline expansions use it instead of creating a second result slot.
bool CodeGenFunctionHelpers::tryUseDirectVarInitStorage(CodeGen& codeGen, AstNodeRef nodeRef, TypeRef typeRef, MicroReg& outStorageReg, SymbolVariable*& outStorageSym)
{
    outStorageReg = MicroReg::invalid();
    outStorageSym = nullptr;

    const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
    if (!resolvedNodeRef.isValid() || !typeRef.isValid())
        return false;

    for (size_t parentIndex = 0;; ++parentIndex)
    {
        const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
        if (parentRef.isInvalid())
            return false;

        const AstNode& parent              = codeGen.node(parentRef);
        const bool     isTransparentParent = (SemaHelpers::isTransparentExprNode(parent) && parent.isNot(AstNodeId::AsCastExpr)) ||
                                         parent.is(AstNodeId::InitializerExpr) ||
                                         parent.is(AstNodeId::ErrorManagementExpr);
        if (isTransparentParent)
            continue;

        if (parent.isNot(AstNodeId::SingleVarDecl))
            return false;

        const auto& varDecl = parent.cast<AstSingleVarDecl>();
        if (varDecl.nodeInitRef.isInvalid())
            return false;

        Symbol* symbol = codeGen.viewSymbol(parentRef).sym();
        if (!symbol || !symbol->isVariable())
            return false;

        auto& symVar = symbol->cast<SymbolVariable>();
        if (!symVar.typeRef().isValid())
            return false;

        if (symVar.typeRef() != typeRef && codeGen.typeMgr().unwrapAlias(codeGen.ctx(), symVar.typeRef()) != codeGen.typeMgr().unwrapAlias(codeGen.ctx(), typeRef))
            return false;

        if (usesCallerReturnStorage(codeGen, symVar))
        {
            // Another named 'retval' local denotes this same slot, so the expression could
            // read it while constructing the result. Keep an intermediate in that case.
            if (SemaHelpers::functionExposesReturnSlot(codeGen.function(), &symVar))
                return false;

            const CodeGenNodePayload storagePayload = resolveCallerReturnStoragePayload(codeGen, symVar);
            SWC_ASSERT(storagePayload.isAddress());
            outStorageReg = storagePayload.reg;
            outStorageSym = &symVar;
            return outStorageReg.isValid();
        }

        if (!codeGen.localStackBaseReg().isValid() || !symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return false;

        const CodeGenNodePayload storagePayload = codeGen.resolveLocalStackPayload(symVar);
        SWC_ASSERT(storagePayload.isAddress());
        outStorageReg = storagePayload.reg;
        outStorageSym = &symVar;
        return outStorageReg.isValid();
    }
}

// A directly returned expression can build into the ABI return slot, or into the result
// storage selected for an ordinary inline expansion. Error-management wrappers do not
// change that destination.
bool CodeGenFunctionHelpers::tryUseDirectReturnStorage(CodeGen& codeGen, AstNodeRef nodeRef, TypeRef typeRef, MicroReg& outStorageReg, SymbolVariable*& outStorageSym)
{
    outStorageReg = MicroReg::invalid();
    outStorageSym = nullptr;
    if (!typeRef.isValid())
        return false;

    const CodeGenFrame::InlineContext* inlineCtx = nullptr;
    if (codeGen.frame().hasCurrentInlineContext())
    {
        const CodeGenFrame::InlineContext& currentInlineCtx = codeGen.frame().currentInlineContext();
        SWC_ASSERT(currentInlineCtx.payload != nullptr);
        if (!currentInlineCtx.payload->returnsToCallerSite())
            inlineCtx = &currentInlineCtx;
    }

    if (!inlineCtx && !codeGen.currentFunctionIndirectReturnReg().isValid() && !codeGen.hasCurrentFunctionIndirectReturnStackOffset())
        return false;

    // The value has to be the returned type itself. A call whose result the return
    // converts - a 'string' becoming a 'String' - builds its own temporary through the
    // conversion; writing the call's bytes into the return slot would leave the slot
    // holding a value of another type, and the conversion's result never copied there.
    const TypeRef returnTypeRef = inlineCtx ? inlineCtx->payload->returnTypeRef : codeGen.function().returnTypeRef();
    if (!returnTypeRef.isValid())
        return false;
    if (typeRef != returnTypeRef && codeGen.typeMgr().unwrapAlias(codeGen.ctx(), typeRef) != codeGen.typeMgr().unwrapAlias(codeGen.ctx(), returnTypeRef))
        return false;

    AstNodeRef directExprRef = codeGen.viewZero(nodeRef).nodeRef();
    if (!directExprRef.isValid())
        return false;

    for (size_t parentIndex = 0;; ++parentIndex)
    {
        const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
        if (!parentRef.isValid())
            return false;

        const AstNode& parent = codeGen.node(parentRef);
        if (parent.is(AstNodeId::CastExpr) || parent.is(AstNodeId::AutoCastExpr) || parent.is(AstNodeId::ParenExpr))
            continue;

        if (parent.is(AstNodeId::ErrorManagementExpr))
        {
            const auto&      errorManagement    = parent.cast<AstErrorManagementExpr>();
            const AstNodeRef resolvedManagedRef = codeGen.viewZero(errorManagement.nodeExprRef).nodeRef();
            if (resolvedManagedRef != directExprRef)
                return false;

            directExprRef = codeGen.viewZero(parentRef).nodeRef();
            continue;
        }

        if (parent.isNot(AstNodeId::ReturnStmt))
            return false;

        const auto&      returnNode        = parent.cast<AstReturnStmt>();
        const AstNodeRef resolvedReturnRef = codeGen.viewZero(returnNode.nodeExprRef).nodeRef();
        if (resolvedReturnRef != directExprRef)
            return false;

        if (inlineCtx)
        {
            SWC_ASSERT(inlineCtx->payload->resultVar != nullptr);
            outStorageSym = inlineCtx->resultStorageSym ? inlineCtx->resultStorageSym : inlineCtx->payload->resultVar;
            if (inlineCtx->resultStorageReg.isValid())
                outStorageReg = inlineCtx->resultStorageReg;
            else
            {
                // Materialized here rather than taken from the cache: the result temporary
                // is declared nowhere, and a 'return' in another branch may have filled it.
                outStorageReg = codeGen.resolveLocalStackPayload(*outStorageSym, false).reg;
            }
            return outStorageReg.isValid();
        }

        outStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(codeGen.function().callConvKind());
        return true;
    }
}

// An aggregate literal builds a whole value from scratch: its fields ran their own copy or
// move hooks as they entered it, and nothing else names the storage it was built in. It is
// therefore an owned value wherever it goes, never a source to copy from.
bool CodeGenFunctionHelpers::isFreshAggregateLiteral(CodeGen& codeGen, AstNodeRef nodeRef)
{
    // The written node is what matters: the cast that types a literal substitutes for it
    // without changing where its value came from.
    while (nodeRef.isValid())
    {
        const AstNode& node = codeGen.node(nodeRef);
        if (node.is(AstNodeId::ParenExpr))
            nodeRef = node.cast<AstParenExpr>().nodeExprRef;
        else if (node.is(AstNodeId::InitializerExpr))
            nodeRef = node.cast<AstInitializerExpr>().nodeExprRef;
        else
            return node.is(AstNodeId::StructInitializerList) || node.is(AstNodeId::StructLiteral) || node.is(AstNodeId::ArrayLiteral);
    }

    return false;
}

// A call result owns its value, whether the call was emitted or expanded inline, and
// whatever error-management wrappers stand around it. A reference-returning call is the
// exception: its address is a borrowed referee.
bool CodeGenFunctionHelpers::isOwnedCallResult(CodeGen& codeGen, AstNodeRef nodeRef)
{
    AstNodeRef resolvedRef = codeGen.viewZero(nodeRef).nodeRef();
    while (resolvedRef.isValid() && codeGen.node(resolvedRef).is(AstNodeId::ErrorManagementExpr))
        resolvedRef = codeGen.viewZero(codeGen.node(resolvedRef).cast<AstErrorManagementExpr>().nodeExprRef).nodeRef();
    if (resolvedRef.isInvalid())
        return false;

    const SemaInlinePayload* inlinePayload = codeGen.sema().inlinePayload(resolvedRef);
    if (inlinePayload && inlinePayload->inlineRootRef == resolvedRef)
        return !inlinePayload->returnsToCallerSite() && inlinePayload->returnTypeRef.isValid() && !codeGen.typeMgr().get(inlinePayload->returnTypeRef).isReference();

    if (codeGen.node(resolvedRef).isNot(AstNodeId::CallExpr))
        return false;

    const SymbolFunction* calledFunction = CodeGenExprView::singleFunction(codeGen.sema().viewStored(resolvedRef, SemaNodeViewPartE::Symbol));
    if (!calledFunction)
        calledFunction = CodeGenExprView::singleFunction(codeGen.viewSymbol(resolvedRef));
    if (!calledFunction || !calledFunction->returnTypeRef().isValid())
        return false;
    return !codeGen.typeMgr().get(calledFunction->returnTypeRef()).isReference();
}

// An expression-bodied function has no 'return' statement for sema to bind to the return
// slot, and no local that could read that slot either: a literal body is built in it.
bool CodeGenFunctionHelpers::tryUseShortBodyReturnStorage(CodeGen& codeGen, AstNodeRef nodeRef, TypeRef typeRef, MicroReg& outStorageReg)
{
    outStorageReg = MicroReg::invalid();
    if (codeGen.frame().hasCurrentInlineContext() || !typeRef.isValid())
        return false;
    if (!functionUsesIndirectReturnStorage(codeGen, codeGen.function()))
        return false;

    // The cast that types the literal stands between it and the declaration.
    size_t     parentIndex = 0;
    AstNodeRef parentRef   = codeGen.visit().parentNodeRef(parentIndex);
    while (parentRef.isValid() && (codeGen.node(parentRef).is(AstNodeId::CastExpr) || codeGen.node(parentRef).is(AstNodeId::ParenExpr)))
        parentRef = codeGen.visit().parentNodeRef(++parentIndex);
    if (parentRef.isInvalid() || parentRef != codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef())
        return false;

    const auto* functionDecl = codeGen.node(parentRef).safeCast<AstFunctionDecl>();
    if (!functionDecl || !functionDecl->hasFlag(AstFunctionFlagsE::Short))
        return false;
    if (codeGen.viewZero(functionDecl->nodeBodyRef).nodeRef() != codeGen.viewZero(nodeRef).nodeRef())
        return false;

    const TypeRef returnTypeRef = codeGen.function().returnTypeRef();
    if (!returnTypeRef.isValid() || codeGen.typeMgr().unwrapAliasEnumOrSelf(codeGen.ctx(), typeRef) != codeGen.typeMgr().unwrapAliasEnumOrSelf(codeGen.ctx(), returnTypeRef))
        return false;

    outStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(codeGen.function().callConvKind());
    return true;
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

    const MicroReg compilerReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegPtrImm(compilerReg, reinterpret_cast<uint64_t>(&codeGen.compiler()));

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
    preparedArgs.push_back({.srcReg = compilerReg, .numBits = 64});
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

#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void scheduleCodeGen(Sema& sema, SymbolFunction& symFn)
    {
        if (symFn.tryMarkCodeGenJobScheduled())
        {
            auto* job = heapNew<CodeGenJob>(sema.ctx(), sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
    }

    TypeRef computeRunExprStorageTypeRef(Sema& sema, TypeRef exprTypeRef)
    {
        const TypeInfo& exprType = sema.typeMgr().get(exprTypeRef);
        return exprType.unwrap(sema.ctx(), exprTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    }

    ConstantValue makeRunExprConstant(Sema& sema, TypeRef exprTypeRef, TypeRef storageTypeRef, const std::byte* storagePtr)
    {
        TaskContext&    ctx         = sema.ctx();
        const TypeInfo& exprType    = sema.typeMgr().get(exprTypeRef);
        const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
        if (exprType.isEnum())
        {
            const ConstantValue storageValue = ConstantValue::make(ctx, storagePtr, storageTypeRef);
            const ConstantRef   storageRef   = sema.cstMgr().addConstant(ctx, storageValue);
            return ConstantValue::makeEnumValue(ctx, storageRef, exprTypeRef);
        }

        if (storageType.isValuePointer() || storageType.isBlockPointer())
        {
            const uint64_t ptrValue = *reinterpret_cast<const uint64_t*>(storagePtr);
            if (!ptrValue)
            {
                ConstantValue nullValue = ConstantValue::makeNull(ctx);
                if (exprType.isAlias())
                    nullValue.setTypeRef(exprTypeRef);
                else
                    nullValue.setTypeRef(storageTypeRef);
                return nullValue;
            }
        }

        ConstantValue result = ConstantValue::make(ctx, storagePtr, storageTypeRef);
        if (exprType.isAlias())
            result.setTypeRef(exprTypeRef);
        return result;
    }

    ConstantValue makeRunExprPointerStringConstant(Sema& sema, const std::byte* storagePtr)
    {
        const TaskContext& ctx           = sema.ctx();
        const uint64_t     strPtrAddress = *reinterpret_cast<const uint64_t*>(storagePtr);
        if (!strPtrAddress)
            return ConstantValue::makeString(ctx, std::string_view{});

        const auto* str = reinterpret_cast<const Runtime::String*>(strPtrAddress);
        if (!str->ptr || !str->length)
            return ConstantValue::makeString(ctx, std::string_view{});

        return ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
    }

    std::optional<Result> consumeJitExecCompletion(Sema& sema, AstNodeRef nodeRef)
    {
        const JITExecManager::Completion completion = sema.compiler().jitExecMgr().consumeCompletion(sema.ctx(), nodeRef);
        if (!completion.hasValue)
            return std::nullopt;
        return completion.result;
    }

    bool hasAnyVariadicParameter(Sema& sema, const SymbolFunction& calledFn)
    {
        for (const SymbolVariable* param : calledFn.parameters())
        {
            SWC_ASSERT(param != nullptr);
            const TypeInfo& paramType = sema.typeMgr().get(param->typeRef());
            if (paramType.isAnyVariadic())
                return true;
        }

        return false;
    }

    bool supportsConstCallValueType(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeRef   valueTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        const TypeInfo& valueType    = sema.typeMgr().get(valueTypeRef);
        if (valueType.isEnum())
            return true;
        if (valueType.isBool() ||
            valueType.isChar() ||
            valueType.isRune() ||
            valueType.isInt() ||
            valueType.isFloat())
        {
            return true;
        }

        return false;
    }

    bool supportsConstCallJit(Sema& sema, const SymbolFunction& calledFn)
    {
        if (!calledFn.isPure() && !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isForeign() || calledFn.isEmpty())
            return false;
        if (!calledFn.returnTypeRef().isValid())
            return false;

        const TypeInfo& returnType = sema.typeMgr().get(calledFn.returnTypeRef());
        if (returnType.isVoid())
            return false;
        if (!supportsConstCallValueType(sema, calledFn.returnTypeRef()))
            return false;

        return true;
    }

    bool canBuildConstCallArguments(Sema& sema, const SymbolFunction& calledFn, std::span<const ResolvedCallArgument> resolvedArgs)
    {
        if (resolvedArgs.size() != calledFn.parameters().size())
            return false;
        if (hasAnyVariadicParameter(sema, calledFn))
            return false;

        for (const ResolvedCallArgument& resolvedArg : resolvedArgs)
        {
            if (resolvedArg.passKind != CallArgumentPassKind::Direct)
                return false;
            if (resolvedArg.argRef.isInvalid())
                return false;
            if (!sema.viewConstant(resolvedArg.argRef).hasConstant())
                return false;
        }

        return true;
    }

    bool buildConstCallArguments(Sema& sema, std::span<const ResolvedCallArgument> resolvedArgs, SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs)
    {
        TaskContext& ctx = sema.ctx();
        outArgStorage.clear();
        outJitArgs.clear();

        outArgStorage.reserve(resolvedArgs.size());
        outJitArgs.reserve(resolvedArgs.size());

        for (const ResolvedCallArgument& resolvedArg : resolvedArgs)
        {
            const AstNodeRef   argRef       = resolvedArg.argRef;
            const SemaNodeView argTypeView  = sema.viewType(argRef);
            const SemaNodeView argConstView = sema.viewConstant(argRef);
            if (!argTypeView.typeRef().isValid() || !argConstView.cstRef().isValid())
                return false;
            if (!supportsConstCallValueType(sema, argTypeView.typeRef()))
                return false;

            const TypeRef argValueTypeRef = sema.typeMgr().get(argTypeView.typeRef()).unwrap(ctx, argTypeView.typeRef(), TypeExpandE::Alias);
            if (!argValueTypeRef.isValid())
                return false;

            const TypeInfo& argValueType   = sema.typeMgr().get(argValueTypeRef);
            const uint64_t  argStorageSize = argValueType.sizeOf(ctx);
            if (!argStorageSize)
                return false;
            SWC_ASSERT(argStorageSize <= std::numeric_limits<uint32_t>::max());
            if (argStorageSize > std::numeric_limits<uint32_t>::max())
                return false;

            auto& argStorage = outArgStorage.emplace_back();
            argStorage.resize(static_cast<size_t>(argStorageSize));
            std::memset(argStorage.data(), 0, argStorage.size());
            ConstantLower::lowerToBytes(sema, ByteSpanRW{argStorage.data(), argStorage.size()}, argConstView.cstRef(), argValueTypeRef);

            JITArgument arg;
            arg.typeRef  = argValueTypeRef;
            arg.valuePtr = argStorage.data();
            outJitArgs.push_back(arg);
        }

        return true;
    }
}

Result SemaJIT::runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef)
{
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));
    if (const std::optional<Result> completion = consumeJitExecCompletion(sema, nodeExprRef))
        return *completion;
    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;
    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT_VERIFY(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    SWC_ASSERT(exprTypeRef.isValid());

    sema.ctx().state().jitEmissionError = false;
    scheduleCodeGen(sema, symFn);
    SWC_RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
    if (sema.ctx().state().jitEmissionError)
        return Result::Error;

    TaskContext&                           ctx            = sema.ctx();
    const TypeRef                          storageTypeRef = computeRunExprStorageTypeRef(sema, exprTypeRef);
    const TypeInfo&                        storageType    = sema.typeMgr().get(storageTypeRef);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(ctx, CallConv::host(), exprTypeRef, ABITypeNormalize::Usage::Return);
    SWC_ASSERT(!storageType.isVoid());

    // Storage, to store the call result of the expression
    uint64_t resultSize = storageType.sizeOf(ctx);
    if (!normalizedRet.isIndirect)
    {
        if (normalizedRet.numBits)
            resultSize = normalizedRet.numBits / 8;
        else
            resultSize = 8;
    }

    SWC_ASSERT(resultSize > 0);
    const auto     resultStorage        = std::make_shared<SmallVector<std::byte>>(resultSize);
    const uint64_t resultStorageAddress = reinterpret_cast<uint64_t>(resultStorage->data());

    // Call !
    SWC_RESULT_VERIFY(symFn.emit(ctx));
    if (ctx.state().jitEmissionError)
        return Result::Error;

    symFn.jit(ctx);
    if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
        return Result::Error;

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeExprRef;
    request.codeRef      = sema.node(nodeExprRef).codeRef();
    request.arg0         = resultStorageAddress;
    request.hasArg0      = true;
    request.runImmediate = false;

    request.onCompleted = [semaPtr = &sema, nodeExprRef, exprTypeRef, storageTypeRef, normalizedRet, resultStorage](Result callResult) {
        if (callResult != Result::Continue)
            return;

        ConstantValue   resultConstant;
        const TypeInfo& exprType = semaPtr->typeMgr().get(exprTypeRef);
        if (!normalizedRet.isIndirect && exprType.isString())
            resultConstant = makeRunExprPointerStringConstant(*semaPtr, resultStorage->data());
        else
            resultConstant = makeRunExprConstant(*semaPtr, exprTypeRef, storageTypeRef, resultStorage->data());
        semaPtr->setConstant(nodeExprRef, semaPtr->cstMgr().addConstant(semaPtr->ctx(), resultConstant));
    };
    return sema.compiler().jitExecMgr().submit(ctx, request);
}

Result SemaJIT::tryRunConstCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs)
{
    if (!supportsConstCallJit(sema, calledFn))
        return Result::Continue;
    if (sema.frame().hasContextFlag(SemaFrameContextFlagsE::RunExpr))
        return Result::Continue;
    if (sema.viewConstant(callRef).hasConstant())
        return Result::Continue;

    if (!canBuildConstCallArguments(sema, calledFn, resolvedArgs))
        return Result::Continue;

    const SymbolFunction* currentFn = sema.frame().currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;

    SWC_RESULT_VERIFY(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    SmallVector<SmallVector<std::byte>> argStorage;
    SmallVector<JITArgument>            jitArgs;
    if (!buildConstCallArguments(sema, resolvedArgs, argStorage, jitArgs))
        return Result::Continue;

    sema.ctx().state().jitEmissionError = false;
    scheduleCodeGen(sema, calledFn);
    SWC_RESULT_VERIFY(sema.waitCodeGenCompleted(&calledFn, calledFn.codeRef()));
    if (sema.ctx().state().jitEmissionError)
        return Result::Error;

    TaskContext& ctx = sema.ctx();
    SWC_RESULT_VERIFY(calledFn.emit(ctx));
    if (ctx.state().jitEmissionError)
        return Result::Error;

    calledFn.jit(ctx);
    if (ctx.state().jitEmissionError || !calledFn.jitEntryAddress())
        return Result::Error;

    const TypeRef   exprTypeRef    = calledFn.returnTypeRef();
    const TypeRef   storageTypeRef = computeRunExprStorageTypeRef(sema, exprTypeRef);
    const TypeInfo& storageType    = sema.typeMgr().get(storageTypeRef);
    const TypeInfo& exprType       = sema.typeMgr().get(exprTypeRef);

    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, CallConv::host(), exprTypeRef, ABITypeNormalize::Usage::Return);
    uint64_t                               resultSize    = storageType.sizeOf(ctx);
    if (!normalizedRet.isIndirect)
    {
        if (normalizedRet.numBits)
            resultSize = normalizedRet.numBits / 8;
        else
            resultSize = 8;
    }

    SWC_ASSERT(resultSize > 0);
    if (!resultSize)
        return Result::Error;

    SmallVector<std::byte> resultStorage;
    resultStorage.resize(static_cast<size_t>(resultSize));
    std::memset(resultStorage.data(), 0, resultStorage.size());

    const JITReturn retMeta{
        .typeRef  = exprTypeRef,
        .valuePtr = resultStorage.data(),
    };

    const Result callResult = JIT::emitAndCall(ctx, calledFn.jitEntryAddress(), jitArgs.span(), retMeta);
    if (callResult != Result::Continue)
        return callResult;

    ConstantValue resultConstant;
    if (!normalizedRet.isIndirect && exprType.isString())
        resultConstant = makeRunExprPointerStringConstant(sema, resultStorage.data());
    else
        resultConstant = makeRunExprConstant(sema, exprTypeRef, storageTypeRef, resultStorage.data());

    sema.setFoldedTypedConst(callRef);
    sema.setConstant(callRef, sema.cstMgr().addConstant(ctx, resultConstant));
    return Result::Continue;
}

Result SemaJIT::runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    if (const std::optional<Result> completion = consumeJitExecCompletion(sema, nodeRef))
        return *completion;

    sema.ctx().state().jitEmissionError = false;
    scheduleCodeGen(sema, symFn);
    SWC_RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
    if (sema.ctx().state().jitEmissionError)
        return Result::Error;

    TaskContext& ctx = sema.ctx();

    SWC_RESULT_VERIFY(symFn.emit(ctx));
    if (ctx.state().jitEmissionError)
        return Result::Error;

    symFn.jit(ctx);
    if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
        return Result::Error;

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeRef;
    request.codeRef      = sema.node(nodeRef).codeRef();
    request.hasArg0      = false;
    request.runImmediate = false;
    return sema.compiler().jitExecMgr().submit(ctx, std::move(request));
}

SWC_END_NAMESPACE();

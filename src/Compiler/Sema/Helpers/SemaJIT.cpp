#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result reportJitEvaluationFailure(Sema& sema, const SymbolFunction& symFn)
    {
        TaskContext& ctx = sema.ctx();
        if (!ctx.hasError())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, symFn.codeRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, std::format("failed to evaluate '{}' at compile time", symFn.name(ctx)));
            diag.report(ctx);
        }

        return Result::Error;
    }

    // ----------------------------------------------------------------------------
    // Data model for one pending JIT evaluation
    // ----------------------------------------------------------------------------

    struct JITCallResultMeta
    {
        TypeRef                          exprTypeRef;
        TypeRef                          storageTypeRef;
        ABITypeNormalize::NormalizedType normalizedRet;
        uint64_t                         resultSize = 0;
    };

    struct ConstCallCacheArg
    {
        TypeRef                typeRef = TypeRef::invalid();
        std::vector<std::byte> bytes;
    };

    struct ConstCallCacheKey
    {
        const SymbolFunction*          function = nullptr;
        std::vector<ConstCallCacheArg> args;
    };

    struct ConstCallCacheEntry
    {
        ConstCallCacheKey key;
        ConstantRef       cstRef = ConstantRef::invalid();
    };

    // Owns all buffers needed by a JIT request until completion.
    struct JITNodePayload
    {
        SmallVector<SmallVector<std::byte>> argStorage;
        SmallVector<JITArgument>            jitArgs;
        SmallVector<std::byte>              resultStorage;
        std::optional<ConstCallCacheKey>    constCallCacheKey;
    };

    // Pending execution data associated with one JIT submission.
    struct JITPendingNodeData
    {
        std::shared_ptr<JITNodePayload> payload;
        JITCallResultMeta               resultMeta;
        bool                            setFoldedTypedConst = false;
    };

    bool sameConstCallCacheKey(const ConstCallCacheKey& lhs, const ConstCallCacheKey& rhs)
    {
        if (lhs.function != rhs.function || lhs.args.size() != rhs.args.size())
            return false;

        for (size_t i = 0; i < lhs.args.size(); ++i)
        {
            if (lhs.args[i].typeRef != rhs.args[i].typeRef || lhs.args[i].bytes != rhs.args[i].bytes)
                return false;
        }

        return true;
    }

    struct ConstCallCacheStorage
    {
        JobClientId                      clientId = 0;
        std::vector<ConstCallCacheEntry> entries;
    };

    ConstCallCacheStorage& constCallCacheStorage()
    {
        thread_local ConstCallCacheStorage storage;
        return storage;
    }

    std::vector<ConstCallCacheEntry>& constCallCache(TaskContext& ctx)
    {
        auto&             storage  = constCallCacheStorage();
        const JobClientId clientId = ctx.compiler().jobClientId();
        if (storage.clientId != clientId)
        {
            // Pure-call folding is only a cache hint. Keep it local to the worker
            // thread and current compiler client instead of serializing all jobs on
            // one shared cache.
            storage.clientId = clientId;
            storage.entries.clear();
        }

        return storage.entries;
    }

    bool buildConstCallCacheKey(Sema& sema, ConstCallCacheKey& outKey, const SymbolFunction& function, std::span<const ResolvedCallArgument> resolvedArgs, std::span<const JITArgument> args)
    {
        if (resolvedArgs.size() != args.size())
            return false;

        TaskContext& ctx = sema.ctx();
        outKey           = {};
        outKey.function  = &function;
        outKey.args.reserve(args.size());

        for (size_t i = 0; i < args.size(); ++i)
        {
            const JITArgument&          arg         = args[i];
            const ResolvedCallArgument& resolvedArg = resolvedArgs[i];
            if (!arg.typeRef.isValid() || !arg.valuePtr)
                return false;

            const TypeInfo& argType   = sema.typeMgr().get(arg.typeRef);
            uint64_t        byteSize  = argType.sizeOf(ctx);
            const void*     sourcePtr = arg.valuePtr;

            // Cache keys must reflect the referenced value, not the transient
            // address of the JIT argument storage used to pass it.
            if (resolvedArg.bindsReferenceToValue && argType.isReference())
            {
                const TypeRef pointeeTypeRef = argType.payloadTypeRef();
                if (!pointeeTypeRef.isValid())
                    return false;

                byteSize                  = sema.typeMgr().get(pointeeTypeRef).sizeOf(ctx);
                const auto pointeeAddress = *static_cast<const uint64_t*>(arg.valuePtr);
                if (byteSize && !pointeeAddress)
                    return false;

                sourcePtr = reinterpret_cast<const void*>(pointeeAddress);
            }

            if (byteSize > std::numeric_limits<uint32_t>::max())
                return false;

            ConstCallCacheArg cacheArg;
            cacheArg.typeRef = arg.typeRef;
            cacheArg.bytes.resize(byteSize);
            if (byteSize)
                std::memcpy(cacheArg.bytes.data(), sourcePtr, cacheArg.bytes.size());
            outKey.args.push_back(std::move(cacheArg));
        }

        return true;
    }

    ConstantRef findConstCallCacheResult(Sema& sema, const ConstCallCacheKey& key)
    {
        for (const ConstCallCacheEntry& entry : constCallCache(sema.ctx()))
        {
            if (sameConstCallCacheKey(entry.key, key))
                return entry.cstRef;
        }

        return ConstantRef::invalid();
    }

    void cacheConstCallResult(Sema& sema, ConstCallCacheKey key, ConstantRef cstRef)
    {
        if (!cstRef.isValid())
            return;

        auto& cache = constCallCache(sema.ctx());
        for (ConstCallCacheEntry& entry : cache)
        {
            if (!sameConstCallCacheKey(entry.key, key))
                continue;

            entry.cstRef = cstRef;
            return;
        }

        cache.push_back({std::move(key), cstRef});
    }

    bool hasPendingJitNode(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        return sema.compiler().jitExecMgr().hasItem(sema.ctx(), nodeRef, sema.node(nodeRef).codeRef());
    }

    std::shared_ptr<JITPendingNodeData> pendingJitCompletionPayload(const JITExecManager::Completion& completion)
    {
        if (!completion.completionPayload)
            return {};
        return std::static_pointer_cast<JITPendingNodeData>(completion.completionPayload);
    }

    ConstantValue makeRunExprConstant(Sema& sema, TypeRef exprTypeRef, TypeRef storageTypeRef, const std::byte* storagePtr)
    {
        TaskContext&    ctx         = sema.ctx();
        const TypeInfo& exprType    = sema.typeMgr().get(exprTypeRef);
        const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
        const TypeInfo* enumType    = &exprType;
        if (!enumType->isEnum() && exprType.isAlias())
        {
            const TypeRef unwrappedTypeRef = exprType.unwrap(ctx, exprTypeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isValid())
            {
                const TypeInfo& unwrappedType = sema.typeMgr().get(unwrappedTypeRef);
                if (unwrappedType.isEnum())
                    enumType = &unwrappedType;
            }
        }

        if (enumType->isEnum())
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

        ConstantValue result = ConstantValue::make(ctx, storagePtr, exprTypeRef);
        if (!result.isValid() && storageTypeRef != exprTypeRef)
            result = ConstantValue::make(ctx, storagePtr, storageTypeRef);
        if (exprType.isAlias())
            result.setTypeRef(exprTypeRef);
        return result;
    }

    ConstantRef makeJitCallResultConstantRef(Sema& sema, const JITCallResultMeta& resultMeta, const std::byte* storagePtr)
    {
        const TypeInfo& exprType        = sema.typeMgr().get(resultMeta.exprTypeRef);
        const TypeRef   constantTypeRef = exprType.isAlias() ? resultMeta.exprTypeRef : resultMeta.storageTypeRef;
        const uint64_t  resultSize      = sema.typeMgr().get(resultMeta.storageTypeRef).sizeOf(sema.ctx());
        const auto      resultBytes     = ByteSpan{storagePtr, static_cast<size_t>(resultSize)};

        if (resultSize && SemaHelpers::needsPersistentCompilerRunReturn(sema, resultMeta.storageTypeRef))
        {
            const ConstantRef cstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, constantTypeRef, resultBytes);
            if (cstRef.isValid())
                return cstRef;
        }

        return sema.cstMgr().addConstant(sema.ctx(), makeRunExprConstant(sema, resultMeta.exprTypeRef, resultMeta.storageTypeRef, storagePtr));
    }

    void applyPendingJitResult(Sema& sema, AstNodeRef nodeRef, const JITPendingNodeData& pendingEntry)
    {
        const ConstantRef cstRef = makeJitCallResultConstantRef(sema, pendingEntry.resultMeta, pendingEntry.payload->resultStorage.data());
        if (pendingEntry.setFoldedTypedConst)
            sema.setFoldedTypedConst(nodeRef);
        sema.setConstant(nodeRef, cstRef);
        if (pendingEntry.payload->constCallCacheKey)
            cacheConstCallResult(sema, std::move(*pendingEntry.payload->constCallCacheKey), cstRef);
    }

    void appendGlobalFunctionInitJitOrder(Sema& sema, SmallVector<SymbolFunction*>& out)
    {
        const auto targets = sema.compiler().nativeGlobalFunctionInitTargetsSnapshot();
        for (const SymbolFunction* target : targets)
        {
            if (!target)
                continue;
            if (target->isForeign() || target->isEmpty() || target->isAttribute())
                continue;

            target->appendJitOrder(out);
        }
    }

    void buildJitOrderWithNativeRoots(Sema& sema, const SymbolFunction& symFn, SmallVector<SymbolFunction*>& out)
    {
        SmallVector<SymbolFunction*> rawOrder;
        symFn.appendJitOrder(rawOrder);
        appendGlobalFunctionInitJitOrder(sema, rawOrder);

        std::unordered_set<SymbolFunction*> seen;
        out.reserve(rawOrder.size());
        for (SymbolFunction* function : rawOrder)
        {
            if (!function)
                continue;
            if (function->attributes().hasRtFlag(RtAttributeFlagsE::Macro) || function->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
                continue;
            if (!seen.insert(function).second)
                continue;

            out.push_back(function);
        }
    }

    bool jitEntryNeedsRuntimeSetup(Sema& sema, const SymbolFunction& symFn)
    {
        if (sema.idMgr().runtimeFunctionKind(symFn.idRef()) == IdentifierManager::RuntimeFunctionKind::SetupRuntime)
            return false;
        if (!symFn.srcViewRef().isValid())
            return true;
        return !sema.compiler().srcView(symFn.srcViewRef()).isRuntimeFile();
    }

    Result prepareJitFunction(Sema& sema, SymbolFunction& symFn);
    Result prepareJitSetupRuntimeFunction(Sema& sema, SymbolFunction& symFn)
    {
        if (!jitEntryNeedsRuntimeSetup(sema, symFn))
            return Result::Continue;

        SymbolFunction* setupFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime, setupFn, symFn.codeRef()));
        if (!setupFn || setupFn == &symFn)
            return Result::Continue;

        return prepareJitFunction(sema, *setupFn);
    }

    Result prepareJitFunction(Sema& sema, SymbolFunction& symFn)
    {
        SWC_RESULT(prepareJitSetupRuntimeFunction(sema, symFn));

        TaskContext& ctx                  = sema.ctx();
        ctx.state().jitEmissionError      = false;
        const uint64_t initTargetsVersion = sema.compiler().nativeGlobalFunctionInitTargetsVersion();
        if (symFn.jitEntryAddress() &&
            symFn.jitReadyVersion() == initTargetsVersion)
            return Result::Continue;

        sema.compiler().tryEnqueueCodeGenJob(sema, symFn, symFn.declNodeRef());
        SWC_RESULT(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
        if (ctx.state().jitEmissionError)
            return reportJitEvaluationFailure(sema, symFn);

        // Dependency-closure loop: keep scheduling CodeGen for newly discovered
        // dependencies until the set stabilises. We capture the last stable
        // `expandedOrder` (snapshot 2) so we can reuse it directly below — this
        // avoids a third `buildJitOrderWithNativeRoots` call after the loop that
        // would race against concurrent jobs registering new native-global-function
        // init targets between the stability check and the snapshot.
        std::unordered_set<SymbolFunction*> knownFunctions;
        size_t                              knownFunctionCount = 0;
        SmallVector<SymbolFunction*>        stableJitOrder;
        while (true)
        {
            SmallVector<SymbolFunction*> jitOrder;
            buildJitOrderWithNativeRoots(sema, symFn, jitOrder);

            for (SymbolFunction* function : jitOrder)
            {
                knownFunctions.insert(function);
                sema.compiler().tryEnqueueCodeGenJob(sema, *function, function->declNodeRef());
            }

            for (const SymbolFunction* function : jitOrder)
            {
                SWC_RESULT(sema.waitCodeGenPreSolved(function, function->codeRef()));
            }

            SmallVector<SymbolFunction*> expandedOrder;
            buildJitOrderWithNativeRoots(sema, symFn, expandedOrder);
            for (SymbolFunction* function : expandedOrder)
            {
                knownFunctions.insert(function);
            }

            if (knownFunctions.size() == knownFunctionCount)
            {
                // Stable: save this snapshot as the definitive JIT order. All
                // functions it contains have had waitCodeGenPreSolved called in
                // a prior (or this) iteration, so it is safe to emit them next.
                stableJitOrder = std::move(expandedOrder);
                break;
            }

            knownFunctionCount = knownFunctions.size();
        }

        for (SymbolFunction* function : stableJitOrder)
        {
            SWC_RESULT(function->emit(ctx));
        }

        if (ctx.state().jitEmissionError)
            return reportJitEvaluationFailure(sema, symFn);

        SWC_RESULT(SymbolFunction::jitBatch(ctx, stableJitOrder));

        if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
            return reportJitEvaluationFailure(sema, symFn);

        if (sema.compiler().nativeGlobalFunctionInitTargetsVersion() == initTargetsVersion)
            symFn.setJitReadyVersion(initTargetsVersion);

        return Result::Continue;
    }

    TypeRef computeRunExprStorageTypeRef(Sema& sema, TypeRef exprTypeRef)
    {
        const TypeInfo& exprType = sema.typeMgr().get(exprTypeRef);
        return exprType.unwrap(sema.ctx(), exprTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    }

    JITCallResultMeta computeJitCallResultMeta(Sema& sema, TypeRef exprTypeRef)
    {
        TaskContext&                           ctx            = sema.ctx();
        const TypeRef                          storageTypeRef = computeRunExprStorageTypeRef(sema, exprTypeRef);
        const TypeInfo&                        storageType    = sema.typeMgr().get(storageTypeRef);
        const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(ctx, CallConv::host(), exprTypeRef, ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!storageType.isVoid());

        uint64_t resultSize = storageType.sizeOf(ctx);
        if (!normalizedRet.isIndirect)
        {
            if (normalizedRet.numBits)
                resultSize = normalizedRet.numBits / 8;
            else
                resultSize = 8;
        }

        SWC_ASSERT(resultSize > 0);

        JITCallResultMeta resultMeta;
        resultMeta.exprTypeRef    = exprTypeRef;
        resultMeta.storageTypeRef = storageTypeRef;
        resultMeta.normalizedRet  = normalizedRet;
        resultMeta.resultSize     = resultSize;
        return resultMeta;
    }

    std::optional<JITExecManager::Completion> consumeJitExecCompletion(Sema& sema, AstNodeRef nodeRef)
    {
        const SourceCodeRef        codeRef    = sema.node(nodeRef).codeRef();
        JITExecManager::Completion completion = sema.compiler().jitExecMgr().consumeCompletion(sema.ctx(), nodeRef, codeRef);
        if (!completion.hasValue)
            return std::nullopt;
        return completion;
    }

    std::optional<Result> consumeJitExecCompletionAndApply(Sema& sema, AstNodeRef nodeRef)
    {
        const std::optional<JITExecManager::Completion> completion = consumeJitExecCompletion(sema, nodeRef);
        if (!completion)
            return std::nullopt;

        const auto pendingEntry = pendingJitCompletionPayload(*completion);
        if (pendingEntry && completion->result == Result::Continue)
            applyPendingJitResult(sema, nodeRef, *pendingEntry);
        return completion->result;
    }

    Result submitJitNode(Sema& sema, AstNodeRef nodeRef, JITExecManager::Request request, const std::shared_ptr<JITNodePayload>& payload, const JITCallResultMeta& resultMeta, bool setFoldedTypedConst)
    {
        TaskContext& ctx = sema.ctx();

        const auto pendingEntry           = std::make_shared<JITPendingNodeData>();
        pendingEntry->payload             = payload;
        pendingEntry->resultMeta          = resultMeta;
        pendingEntry->setFoldedTypedConst = setFoldedTypedConst;
        request.completionPayload         = pendingEntry;
        const Result submitResult         = sema.compiler().jitExecMgr().submit(ctx, request);
        if (submitResult == Result::Pause)
            return Result::Pause;

        if (submitResult != Result::Continue)
            return submitResult;
        applyPendingJitResult(sema, nodeRef, *pendingEntry);
        return Result::Continue;
    }

    Result waitPendingJitNode(Sema& sema, const SymbolFunction& function, AstNodeRef nodeRef)
    {
        sema.ctx().state().setSemaWaitMainThreadRunJit(&function, nodeRef, sema.node(nodeRef).codeRef());
        return Result::Pause;
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

    bool hasUnsupportedConstCallReturn(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
            return unwrappedTypeRef.isValid() && hasUnsupportedConstCallReturn(sema, unwrappedTypeRef);
        }

        if (typeInfo.isEnum())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Enum);
            return unwrappedTypeRef.isValid() && hasUnsupportedConstCallReturn(sema, unwrappedTypeRef);
        }

        if (typeInfo.isAny() || typeInfo.isInterface())
            return true;
        if (typeInfo.isReference())
            return true;
        if (typeInfo.isFunction() && !typeInfo.isLambdaClosure())
            return true;

        if (typeInfo.isArray())
            return hasUnsupportedConstCallReturn(sema, typeInfo.payloadArrayElemTypeRef());

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (field && hasUnsupportedConstCallReturn(sema, field->typeRef()))
                    return true;
            }
        }

        return false;
    }

    bool supportsConstCallJit(Sema& sema, const SymbolFunction& calledFn)
    {
        if (calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        // Throwable calls depend on the runtime error context and must preserve
        // their TLS-visible side effects instead of being folded to a plain value.
        if (calledFn.isThrowable())
            return false;
        if (!calledFn.isPure() && !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isForeign() && !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isEmpty() && !calledFn.isForeign())
            return false;
        if (!calledFn.returnTypeRef().isValid())
            return false;

        const TypeInfo& returnType = sema.typeMgr().get(calledFn.returnTypeRef());
        if (returnType.isVoid())
            return false;
        if (hasUnsupportedConstCallReturn(sema, calledFn.returnTypeRef()))
            return false;

        return true;
    }

    bool supportsConstSetCallJit(Sema& sema, const SymbolFunction& calledFn, const TypeRef receiverTypeRef)
    {
        if (calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        if (calledFn.isThrowable())
            return false;
        if (!calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isEmpty() && !calledFn.isForeign())
            return false;
        if (!receiverTypeRef.isValid() || hasUnsupportedConstCallReturn(sema, receiverTypeRef))
            return false;
        if (calledFn.parameters().empty())
            return false;

        const TypeRef   receiverParamTypeRef      = sema.typeMgr().get(calledFn.parameters().front()->typeRef()).unwrap(sema.ctx(), calledFn.parameters().front()->typeRef(), TypeExpandE::Alias);
        const TypeRef   normalizedReceiverTypeRef = sema.typeMgr().get(receiverTypeRef).unwrap(sema.ctx(), receiverTypeRef, TypeExpandE::Alias);
        const TypeRef   receiverParamRef          = receiverParamTypeRef.isValid() ? receiverParamTypeRef : calledFn.parameters().front()->typeRef();
        const TypeRef   receiverType              = normalizedReceiverTypeRef.isValid() ? normalizedReceiverTypeRef : receiverTypeRef;
        const TypeInfo& receiverParam             = sema.typeMgr().get(receiverParamRef);
        if (!receiverParam.isReference())
            return false;
        if (receiverParam.payloadTypeRef() != receiverType)
            return false;

        if (!calledFn.returnTypeRef().isValid())
            return false;
        if (!sema.typeMgr().get(calledFn.returnTypeRef()).isVoid())
            return false;

        return true;
    }

    Result defaultArgumentConstantRef(Sema& sema, ConstantRef& outCstRef, AstNodeRef callRef, const ResolvedCallArgument& resolvedArg)
    {
        outCstRef = ConstantRef::invalid();

        switch (resolvedArg.defaultKind)
        {
            case CallArgumentDefaultKind::Constant:
                outCstRef = resolvedArg.defaultCstRef;
                return Result::Continue;

            case CallArgumentDefaultKind::CallerLocation:
            {
                const SourceCodeRange codeRange = sema.node(callRef).codeRangeWithChildren(sema.ctx(), sema.ast());
                return ConstantHelpers::makeSourceCodeLocation(sema, outCstRef, codeRange, SemaHelpers::currentLocationFunction(sema));
            }

            case CallArgumentDefaultKind::None:
                break;
        }

        return Result::Continue;
    }

    Result buildConstCallArguments(Sema& sema, bool& outBuilt, const SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs)
    {
        outBuilt = false;
        if (resolvedArgs.size() != calledFn.parameters().size())
            return Result::Continue;
        if (hasAnyVariadicParameter(sema, calledFn))
            return Result::Continue;

        TaskContext& ctx = sema.ctx();
        outArgStorage.clear();
        outJitArgs.clear();

        outArgStorage.reserve(resolvedArgs.size() * 2);
        outJitArgs.reserve(resolvedArgs.size());

        for (size_t i = 0; i < resolvedArgs.size(); ++i)
        {
            const ResolvedCallArgument& resolvedArg = resolvedArgs[i];
            if (resolvedArg.passKind != CallArgumentPassKind::Direct)
                return Result::Continue;
            if (i >= calledFn.parameters().size())
                return Result::Continue;

            const SymbolVariable* param = calledFn.parameters()[i];
            SWC_ASSERT(param != nullptr);

            TypeRef argValueTypeRef = sema.typeMgr().get(param->typeRef()).unwrap(ctx, param->typeRef(), TypeExpandE::Alias);
            if (!argValueTypeRef.isValid())
                return Result::Continue;

            ConstantRef      argCstRef = ConstantRef::invalid();
            const AstNodeRef argRef    = resolvedArg.argRef;
            if (argRef.isValid())
            {
                const SemaNodeView argConstView = sema.viewConstant(argRef);
                if (!argConstView.cstRef().isValid())
                    return Result::Continue;

                argCstRef = argConstView.cstRef();
            }
            else
            {
                SWC_RESULT(defaultArgumentConstantRef(sema, argCstRef, callRef, resolvedArg));
                if (!argCstRef.isValid())
                    return Result::Continue;
            }

            if (!argCstRef.isValid())
                return Result::Continue;

            const TypeInfo&     argValueType     = sema.typeMgr().get(argValueTypeRef);
            const ConstantValue argConstantValue = sema.cstMgr().get(argCstRef);
            if (argValueType.isReference() &&
                !argConstantValue.isNull() &&
                !argConstantValue.isValuePointer() &&
                !argConstantValue.isBlockPointer())
            {
                const TypeRef pointeeTypeRef = argValueType.payloadTypeRef();
                if (!pointeeTypeRef.isValid())
                    return Result::Continue;

                const TypeInfo& pointeeType     = sema.typeMgr().get(pointeeTypeRef);
                const uint64_t  pointeeByteSize = pointeeType.sizeOf(ctx);
                const uint64_t  argStorageSize  = argValueType.sizeOf(ctx);
                if (!argStorageSize || argStorageSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;
                if (pointeeByteSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;

                auto& pointeeStorage = outArgStorage.emplace_back();
                pointeeStorage.resize(pointeeByteSize);
                std::memset(pointeeStorage.data(), 0, pointeeStorage.size());
                SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, ByteSpanRW{pointeeStorage.data(), pointeeStorage.size()}, argCstRef, pointeeTypeRef) == Result::Continue);

                auto& argStorage = outArgStorage.emplace_back();
                argStorage.resize(argStorageSize);
                std::memset(argStorage.data(), 0, argStorage.size());
                const uint64_t ptr = reinterpret_cast<uint64_t>(pointeeStorage.data());
                std::memcpy(argStorage.data(), &ptr, sizeof(ptr));

                JITArgument arg;
                arg.typeRef  = argValueTypeRef;
                arg.valuePtr = argStorage.data();
                outJitArgs.push_back(arg);
                continue;
            }

            const uint64_t argStorageSize = argValueType.sizeOf(ctx);
            if (!argStorageSize)
                return Result::Continue;
            SWC_ASSERT(argStorageSize <= std::numeric_limits<uint32_t>::max());
            if (argStorageSize > std::numeric_limits<uint32_t>::max())
                return Result::Continue;

            auto& argStorage = outArgStorage.emplace_back();
            argStorage.resize(argStorageSize);
            std::memset(argStorage.data(), 0, argStorage.size());
            SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, ByteSpanRW{argStorage.data(), argStorage.size()}, argCstRef, argValueTypeRef) == Result::Continue);

            JITArgument arg;
            arg.typeRef  = argValueTypeRef;
            arg.valuePtr = argStorage.data();
            outJitArgs.push_back(arg);
        }

        outBuilt = true;
        return Result::Continue;
    }

    Result buildConstSetCallArguments(Sema& sema, bool& outBuilt, const SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, TypeRef receiverTypeRef, ConstantRef receiverInitCstRef, const std::byte*& outReceiverStorage, SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs)
    {
        outBuilt           = false;
        outReceiverStorage = nullptr;
        if (resolvedArgs.size() != calledFn.parameters().size())
            return Result::Continue;
        if (resolvedArgs.empty() || hasAnyVariadicParameter(sema, calledFn))
            return Result::Continue;

        TaskContext& ctx = sema.ctx();
        outArgStorage.clear();
        outJitArgs.clear();

        outArgStorage.reserve(resolvedArgs.size() * 2);
        outJitArgs.reserve(resolvedArgs.size());

        for (size_t i = 0; i < resolvedArgs.size(); ++i)
        {
            const ResolvedCallArgument& resolvedArg = resolvedArgs[i];
            if (resolvedArg.passKind != CallArgumentPassKind::Direct)
                return Result::Continue;

            const SymbolVariable* param = calledFn.parameters()[i];
            SWC_ASSERT(param != nullptr);

            TypeRef argValueTypeRef = sema.typeMgr().get(param->typeRef()).unwrap(ctx, param->typeRef(), TypeExpandE::Alias);
            if (!argValueTypeRef.isValid())
                return Result::Continue;

            if (i == 0)
            {
                const TypeInfo& argValueType = sema.typeMgr().get(argValueTypeRef);
                if (!argValueType.isReference())
                    return Result::Continue;

                const TypeRef pointeeTypeRef = argValueType.payloadTypeRef();
                if (!pointeeTypeRef.isValid())
                    return Result::Continue;

                const uint64_t pointeeByteSize = sema.typeMgr().get(receiverTypeRef).sizeOf(ctx);
                const uint64_t argStorageSize  = argValueType.sizeOf(ctx);
                if (!argStorageSize || argStorageSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;
                if (pointeeByteSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;

                auto& pointeeStorage = outArgStorage.emplace_back();
                pointeeStorage.resize(pointeeByteSize);
                std::memset(pointeeStorage.data(), 0, pointeeStorage.size());
                if (receiverInitCstRef.isValid())
                    SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, ByteSpanRW{pointeeStorage.data(), pointeeStorage.size()}, receiverInitCstRef, receiverTypeRef) == Result::Continue);

                auto& argStorage = outArgStorage.emplace_back();
                argStorage.resize(argStorageSize);
                std::memset(argStorage.data(), 0, argStorage.size());
                const uint64_t ptr = reinterpret_cast<uint64_t>(pointeeStorage.data());
                std::memcpy(argStorage.data(), &ptr, sizeof(ptr));

                JITArgument arg;
                arg.typeRef  = argValueTypeRef;
                arg.valuePtr = argStorage.data();
                outJitArgs.push_back(arg);
                outReceiverStorage = pointeeStorage.data();
                continue;
            }

            ConstantRef      argCstRef = ConstantRef::invalid();
            const AstNodeRef argRef    = resolvedArg.argRef;
            if (argRef.isValid())
            {
                const SemaNodeView argConstView = sema.viewConstant(argRef);
                if (!argConstView.cstRef().isValid())
                    return Result::Continue;

                argCstRef = argConstView.cstRef();
            }
            else
            {
                SWC_RESULT(defaultArgumentConstantRef(sema, argCstRef, callRef, resolvedArg));
                if (!argCstRef.isValid())
                    return Result::Continue;
            }

            const TypeInfo&     argValueType     = sema.typeMgr().get(argValueTypeRef);
            const ConstantValue argConstantValue = sema.cstMgr().get(argCstRef);
            if (argValueType.isReference() &&
                !argConstantValue.isNull() &&
                !argConstantValue.isValuePointer() &&
                !argConstantValue.isBlockPointer())
            {
                const TypeRef pointeeTypeRef = argValueType.payloadTypeRef();
                if (!pointeeTypeRef.isValid())
                    return Result::Continue;

                const uint64_t pointeeByteSize = sema.typeMgr().get(pointeeTypeRef).sizeOf(ctx);
                const uint64_t argStorageSize  = argValueType.sizeOf(ctx);
                if (!argStorageSize || argStorageSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;
                if (pointeeByteSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;

                auto& pointeeStorage = outArgStorage.emplace_back();
                pointeeStorage.resize(pointeeByteSize);
                std::memset(pointeeStorage.data(), 0, pointeeStorage.size());
                SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, ByteSpanRW{pointeeStorage.data(), pointeeStorage.size()}, argCstRef, pointeeTypeRef) == Result::Continue);

                auto& argStorage = outArgStorage.emplace_back();
                argStorage.resize(argStorageSize);
                std::memset(argStorage.data(), 0, argStorage.size());
                const uint64_t ptr = reinterpret_cast<uint64_t>(pointeeStorage.data());
                std::memcpy(argStorage.data(), &ptr, sizeof(ptr));

                JITArgument arg;
                arg.typeRef  = argValueTypeRef;
                arg.valuePtr = argStorage.data();
                outJitArgs.push_back(arg);
                continue;
            }

            const uint64_t argStorageSize = argValueType.sizeOf(ctx);
            if (!argStorageSize || argStorageSize > std::numeric_limits<uint32_t>::max())
                return Result::Continue;

            auto& argStorage = outArgStorage.emplace_back();
            argStorage.resize(argStorageSize);
            std::memset(argStorage.data(), 0, argStorage.size());
            SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, ByteSpanRW{argStorage.data(), argStorage.size()}, argCstRef, argValueTypeRef) == Result::Continue);

            JITArgument arg;
            arg.typeRef  = argValueTypeRef;
            arg.valuePtr = argStorage.data();
            outJitArgs.push_back(arg);
        }

        outBuilt = outReceiverStorage != nullptr;
        return Result::Continue;
    }

    Result emitForeignConstExprCall(Sema& sema, const SymbolFunction& calledFn, std::span<const JITArgument> jitArgs, const JITReturn& jitReturn)
    {
        TaskContext& ctx      = sema.ctx();
        void*        targetFn = nullptr;
        if (!JIT::resolveForeignFunctionAddress(ctx, targetFn, calledFn))
            return reportJitEvaluationFailure(sema, calledFn);

        const Result jitResult = JIT::emitAndCall(ctx, targetFn, jitArgs, jitReturn, calledFn.callConvKind());
        if (jitResult != Result::Continue)
            return reportJitEvaluationFailure(sema, calledFn);

        return Result::Continue;
    }
}

Result SemaJIT::runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef)
{
    SWC_RESULT(SemaCheck::isValue(sema, nodeExprRef));

    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, nodeExprRef))
        return *completion;

    ///////////////////////////////////////////
    // Fast exits and prerequisites.
    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;

    if (hasPendingJitNode(sema, nodeExprRef))
        return waitPendingJitNode(sema, symFn, nodeExprRef);

    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef           exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);
    SWC_RESULT(prepareJitFunction(sema, symFn));

    ///////////////////////////////////////////
    // Build payload and submit with shared node lifecycle.
    const auto payload = std::make_shared<JITNodePayload>();
    payload->resultStorage.resize(resultMeta.resultSize);

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeExprRef;
    request.codeRef      = sema.node(nodeExprRef).codeRef();
    request.arg0         = reinterpret_cast<uint64_t>(payload->resultStorage.data());
    request.hasArg0      = true;
    request.runImmediate = false;

    return submitJitNode(sema, nodeExprRef, request, payload, resultMeta, false);
}

Result SemaJIT::runExprImmediate(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef)
{
    SWC_RESULT(SemaCheck::isValue(sema, nodeExprRef));

    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;

    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef           exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);
    SWC_RESULT(prepareJitFunction(sema, symFn));

    SmallVector<std::byte> resultStorage;
    resultStorage.resize(resultMeta.resultSize);

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeExprRef;
    request.codeRef      = sema.node(nodeExprRef).codeRef();
    request.arg0         = reinterpret_cast<uint64_t>(resultStorage.data());
    request.hasArg0      = true;
    request.runImmediate = true;

    const Result jitResult = sema.compiler().jitExecMgr().submit(sema.ctx(), request);
    if (jitResult != Result::Continue)
        return reportJitEvaluationFailure(sema, symFn);

    sema.setConstant(nodeExprRef, makeJitCallResultConstantRef(sema, resultMeta, resultStorage.data()));
    return Result::Continue;
}

Result SemaJIT::runFunctionResult(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, nodeRef))
        return *completion;

    ///////////////////////////////////////////
    // Fast exits and prerequisites.
    if (sema.viewConstant(nodeRef).hasConstant())
        return Result::Continue;
    if (hasPendingJitNode(sema, nodeRef))
        return waitPendingJitNode(sema, symFn, nodeRef);
    if (!symFn.returnTypeRef().isValid())
        return Result::Error;

    const JITCallResultMeta resultMeta = computeJitCallResultMeta(sema, symFn.returnTypeRef());
    SWC_RESULT(prepareJitFunction(sema, symFn));

    ///////////////////////////////////////////
    // Build payload and submit with shared node lifecycle.
    const auto payload = std::make_shared<JITNodePayload>();
    payload->resultStorage.resize(resultMeta.resultSize);

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeRef;
    request.codeRef      = sema.node(nodeRef).codeRef();
    request.jitReturn    = JITReturn{.typeRef = symFn.returnTypeRef(), .valuePtr = payload->resultStorage.data()};
    request.hasJitReturn = true;
    request.runImmediate = false;

    return submitJitNode(sema, nodeRef, request, payload, resultMeta, false);
}

Result SemaJIT::tryRunConstCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs)
{
    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, callRef))
        return *completion;

    ///////////////////////////////////////////
    // Eligibility and prerequisites.
    if (sema.isRunExprContext())
        return Result::Continue;
    if (!sema.isOptimizeEnabled() &&
        !sema.isConstExprRequired())
        return Result::Continue;
    if (sema.viewConstant(callRef).hasConstant())
        return Result::Continue;

    const SymbolFunction* currentFn = sema.currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;

    if (sema.isConstExprRequired())
        SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    if (!supportsConstCallJit(sema, calledFn))
        return Result::Continue;

    if (hasPendingJitNode(sema, callRef))
        return waitPendingJitNode(sema, calledFn, callRef);

    SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));
    if (!supportsConstCallJit(sema, calledFn))
        return Result::Continue;

    ///////////////////////////////////////////
    // Build payload and arguments for call folding.
    const auto payload = std::make_shared<JITNodePayload>();
    bool       built   = false;
    SWC_RESULT(buildConstCallArguments(sema, built, calledFn, callRef, resolvedArgs, payload->argStorage, payload->jitArgs));
    if (!built)
        return Result::Continue;

    const TypeRef           exprTypeRef = calledFn.returnTypeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);
    ConstCallCacheKey       cacheKey;
    if (buildConstCallCacheKey(sema, cacheKey, calledFn, resolvedArgs, payload->jitArgs.span()))
    {
        if (const ConstantRef cachedRef = findConstCallCacheResult(sema, cacheKey); cachedRef.isValid())
        {
            sema.setFoldedTypedConst(callRef);
            sema.setConstant(callRef, cachedRef);
            return Result::Continue;
        }

        payload->constCallCacheKey = std::move(cacheKey);
    }

    payload->resultStorage.resize(resultMeta.resultSize);
    if (calledFn.isForeign())
    {
        const JITReturn jitReturn = {.typeRef = exprTypeRef, .valuePtr = payload->resultStorage.data()};
        SWC_RESULT(emitForeignConstExprCall(sema, calledFn, payload->jitArgs.span(), jitReturn));

        const ConstantRef resultCstRef = makeJitCallResultConstantRef(sema, resultMeta, payload->resultStorage.data());
        if (payload->constCallCacheKey)
            cacheConstCallResult(sema, std::move(*payload->constCallCacheKey), resultCstRef);
        sema.setFoldedTypedConst(callRef);
        sema.setConstant(callRef, resultCstRef);
        return Result::Continue;
    }

    SWC_RESULT(prepareJitFunction(sema, calledFn));

    JITExecManager::Request request;
    request.function     = &calledFn;
    request.nodeRef      = callRef;
    request.codeRef      = sema.node(callRef).codeRef();
    request.jitArgs      = payload->jitArgs.span();
    request.jitReturn    = JITReturn{.typeRef = exprTypeRef, .valuePtr = payload->resultStorage.data()};
    request.hasJitReturn = true;
    request.runImmediate = false;

    return submitJitNode(sema, callRef, request, payload, resultMeta, true);
}

Result SemaJIT::tryRunConstSetCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, const TypeRef receiverTypeRef, const ConstantRef receiverInitCstRef, const bool forceEvaluation)
{
    if (!supportsConstSetCallJit(sema, calledFn, receiverTypeRef))
        return Result::Continue;
    if (sema.isRunExprContext())
        return Result::Continue;
    if (!sema.isOptimizeEnabled() &&
        !sema.isConstExprRequired() &&
        !forceEvaluation)
        return Result::Continue;

    const SymbolFunction* currentFn = sema.currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;
    SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    SmallVector<SmallVector<std::byte>> argStorage;
    SmallVector<JITArgument>            jitArgs;
    const std::byte*                    receiverStorage = nullptr;
    bool                                built           = false;
    SWC_RESULT(buildConstSetCallArguments(sema, built, calledFn, callRef, resolvedArgs, receiverTypeRef, receiverInitCstRef, receiverStorage, argStorage, jitArgs));
    if (!built)
        return Result::Continue;

    if (calledFn.isForeign())
    {
        SWC_RESULT(emitForeignConstExprCall(sema, calledFn, jitArgs.span(), {.typeRef = sema.typeMgr().typeVoid(), .valuePtr = nullptr}));

        const uint64_t    structSize   = sema.typeMgr().get(receiverTypeRef).sizeOf(sema.ctx());
        const ConstantRef resultCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, receiverTypeRef, ByteSpan{receiverStorage, structSize});
        sema.setConstant(callRef, resultCstRef);
        sema.setFoldedTypedConst(callRef);
        return Result::Continue;
    }

    SWC_RESULT(prepareJitFunction(sema, calledFn));

    JITExecManager::Request request;
    request.function     = &calledFn;
    request.nodeRef      = callRef;
    request.codeRef      = sema.node(callRef).codeRef();
    request.jitArgs      = jitArgs.span();
    request.jitReturn    = JITReturn{.typeRef = sema.typeMgr().typeVoid(), .valuePtr = nullptr};
    request.hasJitReturn = true;
    request.runImmediate = true;

    const Result jitResult = sema.compiler().jitExecMgr().submit(sema.ctx(), request);
    if (jitResult != Result::Continue)
        return reportJitEvaluationFailure(sema, calledFn);

    const uint64_t    structSize   = sema.typeMgr().get(receiverTypeRef).sizeOf(sema.ctx());
    const ConstantRef resultCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, receiverTypeRef, ByteSpan{receiverStorage, structSize});
    sema.setConstant(callRef, resultCstRef);
    sema.setFoldedTypedConst(callRef);
    return Result::Continue;
}

Result SemaJIT::runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<JITExecManager::Completion> completion = consumeJitExecCompletion(sema, nodeRef))
        return completion->result;

    ///////////////////////////////////////////
    // Shared codegen/JIT preparation path.
    SWC_RESULT(prepareJitFunction(sema, symFn));

    ///////////////////////////////////////////
    // Submit statement execution to the JIT manager.
    TaskContext&            ctx = sema.ctx();
    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeRef;
    request.codeRef      = sema.node(nodeRef).codeRef();
    request.hasArg0      = false;
    request.runImmediate = false;
    return sema.compiler().jitExecMgr().submit(ctx, request);
}

void SemaJIT::clearConstCallCache()
{
    auto& storage    = constCallCacheStorage();
    storage.clientId = 0;
    storage.entries.clear();
}

Result SemaJIT::prepareFunction(Sema& sema, SymbolFunction& symFn)
{
    return prepareJitFunction(sema, symFn);
}

Result SemaJIT::runStatementImmediate(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    SWC_RESULT(prepareFunction(sema, symFn));

    TaskContext&            ctx = sema.ctx();
    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeRef;
    request.codeRef      = sema.node(nodeRef).codeRef();
    request.hasArg0      = false;
    request.runImmediate = true;
    return sema.compiler().jitExecMgr().submit(ctx, request);
}

SWC_END_NAMESPACE();

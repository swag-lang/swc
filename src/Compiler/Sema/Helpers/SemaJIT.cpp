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

// ============================================================================
// JIT-assisted semantic execution helpers
// ============================================================================
//
// This file handles three semantic JIT use-cases:
// 1) runExpr: execute expression code and materialize a folded constant.
// 2) tryRunConstCall: fold constexpr-like calls through JIT.
// 3) runStatement: execute statements for side effects.
//
// For runExpr/tryRunConstCall we use the same deferred lifecycle:
// - build a JITNodePayload (arguments + return storage),
// - register per-node pending state in sema payload,
// - submit to JITExecManager,
// - consume completion and apply result to AST node constant payload.
//
// Pending state is attached to the node through NodePayload external storage
// (not through global/static state), which is stable across payload rewrites.
//
namespace
{
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

    // Owns all buffers needed by a JIT request until completion.
    struct JITNodePayload
    {
        SmallVector<SmallVector<std::byte>> argStorage;
        SmallVector<JITArgument>            jitArgs;
        SmallVector<std::byte>              resultStorage;
    };

    // Pending execution data associated with one AST node through sema payload.
    struct JITPendingNodeData
    {
        std::shared_ptr<JITNodePayload> payload;
        JITCallResultMeta               resultMeta;
        bool                            setFoldedTypedConst = false;
    };

    JITPendingNodeData* pendingJitNodeData(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;
        if (!sema.hasSemaPayload(nodeRef))
            return nullptr;
        return sema.semaPayload<JITPendingNodeData>(nodeRef);
    }

    bool hasPendingJitNode(const Sema& sema, AstNodeRef nodeRef)
    {
        return pendingJitNodeData(sema, nodeRef) != nullptr;
    }

    void registerPendingJitNode(Sema& sema, AstNodeRef nodeRef, const std::shared_ptr<JITNodePayload>& payload, const JITCallResultMeta& resultMeta, bool setFoldedTypedConst)
    {
        if (pendingJitNodeData(sema, nodeRef))
            return;

        auto* pendingData                = heapNew<JITPendingNodeData>();
        pendingData->payload             = payload;
        pendingData->resultMeta          = resultMeta;
        pendingData->setFoldedTypedConst = setFoldedTypedConst;
        sema.setSemaPayload(nodeRef, pendingData);
    }

    std::optional<JITPendingNodeData> takePendingJitNode(Sema& sema, AstNodeRef nodeRef)
    {
        auto* pendingData = pendingJitNodeData(sema, nodeRef);
        if (!pendingData)
            return std::nullopt;

        JITPendingNodeData result = std::move(*pendingData);
        sema.clearSemaPayload(nodeRef);
        heapDelete(pendingData);
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

    ConstantValue makeJitCallResultConstant(Sema& sema, const JITCallResultMeta& resultMeta, const std::byte* storagePtr)
    {
        const TypeInfo& exprType = sema.typeMgr().get(resultMeta.exprTypeRef);
        if (!resultMeta.normalizedRet.isIndirect && exprType.isString())
            return makeRunExprPointerStringConstant(sema, storagePtr);
        return makeRunExprConstant(sema, resultMeta.exprTypeRef, resultMeta.storageTypeRef, storagePtr);
    }

    void applyPendingJitResult(Sema& sema, AstNodeRef nodeRef, const JITPendingNodeData& pendingEntry)
    {
        const ConstantValue resultConstant = makeJitCallResultConstant(sema, pendingEntry.resultMeta, pendingEntry.payload->resultStorage.data());
        if (pendingEntry.setFoldedTypedConst)
            sema.setFoldedTypedConst(nodeRef);
        sema.setConstant(nodeRef, sema.cstMgr().addConstant(sema.ctx(), resultConstant));
    }

    Result prepareJitFunction(Sema& sema, SymbolFunction& symFn)
    {
        TaskContext& ctx             = sema.ctx();
        ctx.state().jitEmissionError = false;
        if (symFn.tryMarkCodeGenJobScheduled())
        {
            auto* job = heapNew<CodeGenJob>(ctx, sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
        SWC_RESULT(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
        if (ctx.state().jitEmissionError)
            return Result::Error;

        std::unordered_set<SymbolFunction*> knownFunctions;
        size_t                              knownFunctionCount = 0;
        while (true)
        {
            SmallVector<SymbolFunction*> jitOrder;
            symFn.appendJitOrder(jitOrder);

            for (SymbolFunction* function : jitOrder)
            {
                if (!function)
                    continue;

                knownFunctions.insert(function);
                if (!function->tryMarkCodeGenJobScheduled())
                    continue;

                const AstNodeRef depRoot = function->declNodeRef();
                SWC_ASSERT(depRoot.isValid());
                auto* job = heapNew<CodeGenJob>(ctx, sema, *function, depRoot);
                sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
            }

            for (SymbolFunction* function : jitOrder)
            {
                if (!function)
                    continue;
                SWC_RESULT(sema.waitCodeGenPreSolved(function, function->codeRef()));
            }

            SmallVector<SymbolFunction*> expandedOrder;
            symFn.appendJitOrder(expandedOrder);
            for (SymbolFunction* function : expandedOrder)
            {
                if (function)
                    knownFunctions.insert(function);
            }

            if (knownFunctions.size() == knownFunctionCount)
                break;

            knownFunctionCount = knownFunctions.size();
        }

        SmallVector<SymbolFunction*> jitOrder;
        symFn.appendJitOrder(jitOrder);
        for (SymbolFunction* function : jitOrder)
        {
            if (!function)
                continue;
            SWC_RESULT(function->emit(ctx));
        }

        if (ctx.state().jitEmissionError)
            return Result::Error;

        symFn.jit(ctx);
        if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
            return Result::Error;

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

    std::optional<Result> consumeJitExecCompletion(Sema& sema, AstNodeRef nodeRef)
    {
        const JITExecManager::Completion completion = sema.compiler().jitExecMgr().consumeCompletion(sema.ctx(), nodeRef);
        if (!completion.hasValue)
            return std::nullopt;
        return completion.result;
    }

    std::optional<Result> consumeJitExecCompletionAndApply(Sema& sema, AstNodeRef nodeRef)
    {
        const std::optional<Result> completion = consumeJitExecCompletion(sema, nodeRef);
        if (!completion)
            return std::nullopt;

        const std::optional<JITPendingNodeData> pendingEntry = takePendingJitNode(sema, nodeRef);
        if (pendingEntry && *completion == Result::Continue)
            applyPendingJitResult(sema, nodeRef, pendingEntry.value());
        return completion;
    }

    Result submitJitNode(Sema& sema, AstNodeRef nodeRef, const JITExecManager::Request& request, const std::shared_ptr<JITNodePayload>& payload, const JITCallResultMeta& resultMeta, bool setFoldedTypedConst)
    {
        TaskContext& ctx = sema.ctx();

        registerPendingJitNode(sema, nodeRef, payload, resultMeta, setFoldedTypedConst);
        const Result submitResult = sema.compiler().jitExecMgr().submit(ctx, request);
        if (submitResult == Result::Pause)
            return Result::Pause;

        const std::optional<JITPendingNodeData> pendingEntry = takePendingJitNode(sema, nodeRef);
        if (submitResult != Result::Continue)
            return submitResult;
        if (pendingEntry)
            applyPendingJitResult(sema, nodeRef, pendingEntry.value());
        return Result::Continue;
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

        return true;
    }

    bool buildConstCallArguments(Sema& sema, const SymbolFunction& calledFn, std::span<const ResolvedCallArgument> resolvedArgs, SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs)
    {
        if (resolvedArgs.size() != calledFn.parameters().size())
            return false;
        if (hasAnyVariadicParameter(sema, calledFn))
            return false;

        TaskContext& ctx = sema.ctx();
        outArgStorage.clear();
        outJitArgs.clear();

        outArgStorage.reserve(resolvedArgs.size());
        outJitArgs.reserve(resolvedArgs.size());

        for (size_t i = 0; i < resolvedArgs.size(); ++i)
        {
            const ResolvedCallArgument& resolvedArg = resolvedArgs[i];
            if (resolvedArg.passKind != CallArgumentPassKind::Direct)
                return false;
            if (i >= calledFn.parameters().size())
                return false;

            const SymbolVariable* param = calledFn.parameters()[i];
            SWC_ASSERT(param != nullptr);

            TypeRef argValueTypeRef = sema.typeMgr().get(param->typeRef()).unwrap(ctx, param->typeRef(), TypeExpandE::Alias);
            if (!argValueTypeRef.isValid())
                return false;

            ConstantRef      argCstRef = ConstantRef::invalid();
            const AstNodeRef argRef    = resolvedArg.argRef;
            if (argRef.isValid())
            {
                const SemaNodeView argConstView = sema.viewConstant(argRef);
                if (!argConstView.cstRef().isValid())
                    return false;

                argCstRef = argConstView.cstRef();
            }
            else
            {
                if (!resolvedArg.defaultCstRef.isValid())
                    return false;
                argCstRef = resolvedArg.defaultCstRef;
            }

            if (!argCstRef.isValid())
                return false;

            const TypeInfo& argValueType   = sema.typeMgr().get(argValueTypeRef);
            const uint64_t  argStorageSize = argValueType.sizeOf(ctx);
            if (!argStorageSize)
                return false;
            SWC_ASSERT(argStorageSize <= std::numeric_limits<uint32_t>::max());
            if (argStorageSize > std::numeric_limits<uint32_t>::max())
                return false;

            auto& argStorage = outArgStorage.emplace_back();
            argStorage.resize(argStorageSize);
            std::memset(argStorage.data(), 0, argStorage.size());
            ConstantLower::lowerToBytes(sema, ByteSpanRW{argStorage.data(), argStorage.size()}, argCstRef, argValueTypeRef);

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
        return Result::Pause;

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

Result SemaJIT::tryRunConstCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs)
{
    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, callRef))
        return *completion;

    ///////////////////////////////////////////
    // Eligibility and prerequisites.
    if (!supportsConstCallJit(sema, calledFn))
        return Result::Continue;
    if (sema.frame().hasContextFlag(SemaFrameContextFlagsE::RunExpr))
        return Result::Continue;
    if (!sema.compiler().buildCfg().backend.optimize &&
        !sema.frame().hasContextFlag(SemaFrameContextFlagsE::RequireConstExpr))
        return Result::Continue;
    if (sema.viewConstant(callRef).hasConstant())
        return Result::Continue;

    if (hasPendingJitNode(sema, callRef))
        return Result::Pause;

    const SymbolFunction* currentFn = sema.frame().currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;
    SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    ///////////////////////////////////////////
    // Build payload and arguments for call folding.
    const auto payload = std::make_shared<JITNodePayload>();
    if (!buildConstCallArguments(sema, calledFn, resolvedArgs, payload->argStorage, payload->jitArgs))
        return Result::Continue;

    const TypeRef           exprTypeRef = calledFn.returnTypeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);
    SWC_RESULT(prepareJitFunction(sema, calledFn));

    payload->resultStorage.resize(resultMeta.resultSize);

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

Result SemaJIT::runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletion(sema, nodeRef))
        return *completion;

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

SWC_END_NAMESPACE();

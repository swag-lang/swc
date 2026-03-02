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
    struct JITCallResultMeta
    {
        TypeRef                          exprTypeRef;
        TypeRef                          storageTypeRef;
        ABITypeNormalize::NormalizedType normalizedRet;
        uint64_t                         resultSize = 0;
    };

    ConstantValue makeJitCallResultConstant(Sema& sema, const JITCallResultMeta& resultMeta, const std::byte* storagePtr);

    // Owns all buffers needed by a JIT request until completion.
    struct JITNodePayload
    {
        SmallVector<SmallVector<std::byte>> argStorage;
        SmallVector<JITArgument>            jitArgs;
        SmallVector<std::byte>              resultStorage;
    };

    // Key used to track in-flight node executions per semantic task context.
    struct JITPendingKey
    {
        const TaskContext* ctx     = nullptr;
        AstNodeRef         nodeRef = AstNodeRef::invalid();

        bool operator==(const JITPendingKey& other) const noexcept
        {
            return ctx == other.ctx && nodeRef == other.nodeRef;
        }
    };

    struct JITPendingKeyHasher
    {
        size_t operator()(const JITPendingKey& key) const noexcept
        {
            const size_t lhs = std::hash<const TaskContext*>{}(key.ctx);
            const size_t rhs = std::hash<uint32_t>{}(key.nodeRef.get());
            return lhs ^ (rhs + 0x9e3779b9 + (lhs << 6) + (lhs >> 2));
        }
    };

    struct JITPendingEntry
    {
        std::shared_ptr<JITNodePayload> payload;
        JITCallResultMeta               resultMeta;
        bool                            setFoldedTypedConst = false;
    };

    std::mutex                                                              g_JITPendingMutex;
    std::unordered_map<JITPendingKey, JITPendingEntry, JITPendingKeyHasher> g_JITPendingByNode;

    bool hasPendingJitNode(const TaskContext& ctx, AstNodeRef nodeRef)
    {
        const std::scoped_lock lock(g_JITPendingMutex);
        return g_JITPendingByNode.contains(JITPendingKey{.ctx = &ctx, .nodeRef = nodeRef});
    }

    void registerPendingJitNode(const TaskContext& ctx, AstNodeRef nodeRef, const std::shared_ptr<JITNodePayload>& payload, const JITCallResultMeta& resultMeta, bool setFoldedTypedConst)
    {
        const std::scoped_lock lock(g_JITPendingMutex);
        const JITPendingKey    key{.ctx = &ctx, .nodeRef = nodeRef};
        if (g_JITPendingByNode.contains(key))
            return;
        g_JITPendingByNode.emplace(key, JITPendingEntry{.payload = payload, .resultMeta = resultMeta, .setFoldedTypedConst = setFoldedTypedConst});
    }

    std::optional<JITPendingEntry> takePendingJitNode(const TaskContext& ctx, AstNodeRef nodeRef)
    {
        const std::scoped_lock lock(g_JITPendingMutex);
        const JITPendingKey    key{.ctx = &ctx, .nodeRef = nodeRef};

        const auto it = g_JITPendingByNode.find(key);
        if (it == g_JITPendingByNode.end())
            return std::nullopt;

        JITPendingEntry entry = std::move(it->second);
        g_JITPendingByNode.erase(it);
        return entry;
    }

    void applyPendingJitResult(Sema& sema, AstNodeRef nodeRef, const JITPendingEntry& pendingEntry)
    {
        const ConstantValue resultConstant = makeJitCallResultConstant(sema, pendingEntry.resultMeta, pendingEntry.payload->resultStorage.data());
        if (pendingEntry.setFoldedTypedConst)
            sema.setFoldedTypedConst(nodeRef);
        sema.setConstant(nodeRef, sema.cstMgr().addConstant(sema.ctx(), resultConstant));
    }

    void scheduleCodeGen(Sema& sema, SymbolFunction& symFn)
    {
        if (symFn.tryMarkCodeGenJobScheduled())
        {
            auto* job = heapNew<CodeGenJob>(sema.ctx(), sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
    }

    Result prepareJitFunction(Sema& sema, SymbolFunction& symFn)
    {
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

        return Result::Continue;
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

    ConstantValue makeJitCallResultConstant(Sema& sema, const JITCallResultMeta& resultMeta, const std::byte* storagePtr)
    {
        const TypeInfo& exprType = sema.typeMgr().get(resultMeta.exprTypeRef);
        if (!resultMeta.normalizedRet.isIndirect && exprType.isString())
            return makeRunExprPointerStringConstant(sema, storagePtr);
        return makeRunExprConstant(sema, resultMeta.exprTypeRef, resultMeta.storageTypeRef, storagePtr);
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

        if (const std::optional<JITPendingEntry> pendingEntry = takePendingJitNode(sema.ctx(), nodeRef);
            pendingEntry && *completion == Result::Continue)
        {
            applyPendingJitResult(sema, nodeRef, *pendingEntry);
        }

        return completion;
    }

    Result submitJitNode(Sema& sema, AstNodeRef nodeRef, const JITExecManager::Request& request, const std::shared_ptr<JITNodePayload>& payload, const JITCallResultMeta& resultMeta, bool setFoldedTypedConst)
    {
        TaskContext& ctx = sema.ctx();

        registerPendingJitNode(ctx, nodeRef, payload, resultMeta, setFoldedTypedConst);
        const Result submitResult = sema.compiler().jitExecMgr().submit(ctx, request);
        if (submitResult == Result::Pause)
            return Result::Pause;

        const std::optional<JITPendingEntry> pendingEntry = takePendingJitNode(ctx, nodeRef);
        if (submitResult != Result::Continue)
            return submitResult;
        if (pendingEntry)
            applyPendingJitResult(sema, nodeRef, *pendingEntry);
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

    bool supportsConstCallValueType(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeRef   valueTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        const TypeInfo& valueType    = sema.typeMgr().get(valueTypeRef);
        if (valueType.isEnum() ||
            valueType.isBool() ||
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

        for (const ResolvedCallArgument& resolvedArg : resolvedArgs)
        {
            if (resolvedArg.passKind != CallArgumentPassKind::Direct)
                return false;

            const AstNodeRef argRef = resolvedArg.argRef;
            if (argRef.isInvalid())
                return false;

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
            argStorage.resize(argStorageSize);
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

    ///////////////////////////////////////////
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, nodeExprRef))
        return *completion;

    ///////////////////////////////////////////
    // Fast exits and prerequisites.
    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;

    const TaskContext& ctx = sema.ctx();
    if (hasPendingJitNode(ctx, nodeExprRef))
        return Result::Pause;

    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT_VERIFY(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef           exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);
    SWC_RESULT_VERIFY(prepareJitFunction(sema, symFn));

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
    if (sema.viewConstant(callRef).hasConstant())
        return Result::Continue;

    const TaskContext& ctx = sema.ctx();
    if (hasPendingJitNode(ctx, callRef))
        return Result::Pause;

    const SymbolFunction* currentFn = sema.frame().currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;
    SWC_RESULT_VERIFY(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    ///////////////////////////////////////////
    // Build payload and arguments for call folding.
    const auto payload = std::make_shared<JITNodePayload>();
    if (!buildConstCallArguments(sema, calledFn, resolvedArgs, payload->argStorage, payload->jitArgs))
        return Result::Continue;

    const TypeRef           exprTypeRef = calledFn.returnTypeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);
    SWC_RESULT_VERIFY(prepareJitFunction(sema, calledFn));

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
    // Prepare codegen and JIT entry point.
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

    ///////////////////////////////////////////
    // Submit statement execution to the JIT manager.
    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeRef;
    request.codeRef      = sema.node(nodeRef).codeRef();
    request.hasArg0      = false;
    request.runImmediate = false;
    return sema.compiler().jitExecMgr().submit(ctx, request);
}

SWC_END_NAMESPACE();

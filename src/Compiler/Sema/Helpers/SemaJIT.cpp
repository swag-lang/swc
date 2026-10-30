#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCallArgument.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/PointerSet.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result reportJitEvaluationFailure(Sema& sema, const SymbolFunction& symFn)
    {
        TaskContext& ctx = sema.ctx();
        if (!ctx.hasError())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, symFn.codeRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, std::format("cannot evaluate '{}' at compile time", symFn.name(ctx)));
            diag.report(ctx);
        }

        return Result::Error;
    }

    // State retained across a pending JIT evaluation.

    struct JITCallResultMeta
    {
        TypeRef exprTypeRef;
        TypeRef storageTypeRef;

        ABITypeNormalize::NormalizedType normalizedRet;
        uint64_t                         resultSize = 0;
    };

    struct ConstCallCacheKey
    {
        const SymbolFunction* function = nullptr;
        ByteArray             arguments;
        uint32_t              hash = 0;

        bool operator==(const ConstCallCacheKey& other) const
        {
            return function == other.function && arguments == other.arguments;
        }
    };

    struct ConstCallCacheKeyHash
    {
        size_t operator()(const ConstCallCacheKey& key) const noexcept { return key.hash; }
    };

    using ConstCallCache = std::unordered_map<ConstCallCacheKey, ConstantRef, ConstCallCacheKeyHash>;

    // Own request buffers until completion: the executor holds raw pointers into them
    // while the sema node is paused and the main thread runs the JIT.
    struct JITNodePayload
    {
        SmallVector<SmallVector<std::byte>> argStorage;
        SmallVector<JITArgument>            jitArgs;
        SmallVector<std::byte>              resultStorage;
        std::optional<ConstCallCacheKey>    constCallCacheKey;
    };

    // Keep request buffers and result metadata in one owned allocation until the
    // resumed sema node converts the returned bytes into a compiler constant.
    struct JITPendingNodeData
    {
        JITNodePayload    payload;
        JITCallResultMeta resultMeta;

        bool setFoldedTypedConst = false;
    };

    struct ConstCallCacheStorage
    {
        JobClientId    clientId = 0;
        ConstCallCache entries;
    };

    ConstCallCacheStorage& constCallCacheStorage()
    {
        thread_local ConstCallCacheStorage storage;
        return storage;
    }

    ConstCallCache& constCallCache(TaskContext& ctx)
    {
        auto&             storage  = constCallCacheStorage();
        const JobClientId clientId = ctx.compiler().jobClientId();
        if (storage.clientId != clientId)
        {
            // Pure-call folding is a cache hint. Keep it per worker and compiler client
            // to avoid serializing semantic jobs on a shared cache.
            storage.clientId = clientId;
            storage.entries.clear();
        }

        return storage.entries;
    }

    bool hasUnpublishedFunctionArguments(Sema& sema, std::span<const JITArgument> args)
    {
        SmallVector<DataSegmentRef> roots;
        for (const JITArgument& arg : args)
        {
            const TypeInfo& type = sema.typeMgr().get(arg.typeRef);
            if (!type.isAnyTypeInfo(sema.ctx()) && !type.isPointerOrReference())
                continue;

            const void* ptr = nullptr;
            std::memcpy(&ptr, arg.valuePtr, sizeof(ptr));

            DataSegmentRef root;
            if (sema.cstMgr().resolveDataSegmentRef(root, ptr))
                roots.push_back(root);
        }

        return sema.cstMgr().hasUnpublishedFunctionRelocations(roots.span());
    }

    std::shared_ptr<const SymbolFunction::ConstantJitTargetList> constantJitTargetsOf(Sema& sema, const SymbolFunction& function);

    bool hasUnpublishedFunctionConstants(Sema& sema, const SymbolFunction& function)
    {
        SmallVector<DataSegmentRef> roots;
        bool                        unpublished = false;

        function.visitJitOrder([&](const SymbolFunction* called) {
            if (unpublished)
                return;
            if (called->isForeignOrEmptyOrAttribute())
                return;

            if (!called->jitEntryAddress())
            {
                unpublished = true;
                return;
            }

            bool checkedConstantSources = false;
            for (const MicroRelocation& relocation : called->loweredCode().codeRelocations)
            {
                if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
                    continue;

                if (relocation.hasConstantSource())
                {
                    if (checkedConstantSources)
                        continue;

                    checkedConstantSources = true;

                    // Preparation already discovers these targets. Reuse its versioned
                    // closure, but recheck publication: JIT entries change independently
                    // of the constant graph, including targets allowed to remain unresolved.
                    const auto targets = constantJitTargetsOf(sema, *called);
                    for (const auto& target : *targets)
                    {
                        if (!target.first->isForeign() && !target.first->jitEntryAddress())
                        {
                            unpublished = true;
                            return;
                        }
                    }
                }
                else
                {
                    DataSegmentRef root;
                    if (sema.cstMgr().resolveDataSegmentRef(root, reinterpret_cast<const void*>(relocation.targetAddress)))
                        roots.push_back(root);
                }
            }
        });

        if (unpublished)
            return true;

        return sema.cstMgr().hasUnpublishedFunctionRelocations(roots.span());
    }

    bool buildConstCallCacheKey(Sema& sema, ConstCallCacheKey& outKey, const SymbolFunction& function, std::span<const ResolvedCallArgument> resolvedArgs, std::span<const JITArgument> args)
    {
        if (resolvedArgs.size() != args.size())
            return false;

        TaskContext& ctx = sema.ctx();
        outKey           = {};
        outKey.function  = &function;

        // Own the key bytes across a paused call. Lengths and type identities distinguish arguments.
        outKey.arguments.reserve(args.size() * 16);

        for (size_t i = 0; i < args.size(); ++i)
        {
            const JITArgument& arg = args[i];
            if (!arg.typeRef.isValid() || !arg.valuePtr)
                return false;

            const TypeInfo& argType   = sema.typeMgr().get(arg.typeRef);
            uint64_t        byteSize  = argType.sizeOf(ctx);
            const void*     sourcePtr = arg.valuePtr;

            // Pointer-like arguments may name transient receiver storage whose address
            // can be recycled between folds, so they cannot safely identify cached calls.
            if (argType.isPointerOrReference())
                return false;

            if (byteSize > std::numeric_limits<uint32_t>::max())
                return false;

            outKey.arguments.appendLe32(arg.typeRef.get());
            outKey.arguments.appendLe32(static_cast<uint32_t>(byteSize));
            outKey.arguments.append(std::span{static_cast<const std::byte*>(sourcePtr), static_cast<size_t>(byteSize)});
        }

        outKey.hash = Math::hashCombine(Math::hash(outKey.arguments.span()), reinterpret_cast<uint64_t>(outKey.function));
        return true;
    }

    ConstantRef findConstCallCacheResult(Sema& sema, const ConstCallCacheKey& key)
    {
        const auto& cache = constCallCache(sema.ctx());
        const auto  found = cache.find(key);
        return found == cache.end() ? ConstantRef::invalid() : found->second;
    }

    void cacheConstCallResult(Sema& sema, ConstCallCacheKey key, ConstantRef cstRef)
    {
        if (cstRef.isValid())
            constCallCache(sema.ctx()).insert_or_assign(std::move(key), cstRef);
    }

    bool hasPendingJitNode(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        return sema.compiler().jitExecMgr().hasItem(sema.ctx(), nodeRef, sema.node(nodeRef).codeRef());
    }

    JITPendingNodeData* pendingJitCompletionPayload(const JITExecManager::Completion& completion)
    {
        return static_cast<JITPendingNodeData*>(completion.completionPayload.get());
    }

    ConstantValue makeRunExprConstant(Sema& sema, const TypeInfo& exprType, const TypeInfo& storageType, const std::byte* storagePtr)
    {
        TaskContext&  ctx            = sema.ctx();
        const TypeRef exprTypeRef    = exprType.typeRef();
        const TypeRef storageTypeRef = storageType.typeRef();

        const TypeInfo* enumType = &exprType;
        // JIT returns normalized storage bytes. Re-wrap them as the expression
        // type so aliases/enums preserve their source-level identity in constants.
        if (!enumType->isEnum() && exprType.isAlias())
        {
            const TypeInfo* unwrappedType = exprType.unwrapAliasType(ctx);
            if (unwrappedType && unwrappedType->isEnum())
                enumType = unwrappedType;
        }

        if (enumType->isEnum())
        {
            const ConstantValue storageValue = ConstantValue::make(ctx, storagePtr, storageTypeRef);
            const ConstantRef   storageRef   = sema.cstMgr().addConstant(ctx, storageValue);
            return ConstantValue::makeEnumValue(ctx, storageRef, exprTypeRef);
        }

        if (storageType.isAnyPointer())
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
        const TypeInfo& storageType     = sema.typeMgr().get(resultMeta.storageTypeRef);
        const TypeRef   constantTypeRef = exprType.isAlias() ? resultMeta.exprTypeRef : resultMeta.storageTypeRef;
        const uint64_t  resultSize      = storageType.sizeOf(sema.ctx());
        const auto      resultBytes     = std::span{storagePtr, static_cast<size_t>(resultSize)};

        if (resultSize && SemaHelpers::needsPersistentCompilerRunReturn(sema.ctx(), resultMeta.storageTypeRef))
        {
            const ConstantRef cstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, constantTypeRef, resultBytes);
            if (cstRef.isValid())
                return cstRef;
        }

        return sema.cstMgr().addConstant(sema.ctx(), makeRunExprConstant(sema, exprType, storageType, storagePtr));
    }

    void applyPendingJitResult(Sema& sema, AstNodeRef nodeRef, JITPendingNodeData& pendingEntry)
    {
        const ConstantRef cstRef = makeJitCallResultConstantRef(sema, pendingEntry.resultMeta, pendingEntry.payload.resultStorage.data());
        if (pendingEntry.setFoldedTypedConst)
            sema.setFoldedTypedConst(nodeRef);
        sema.setConstant(nodeRef, cstRef);

        if (pendingEntry.payload.constCallCacheKey)
            cacheConstCallResult(sema, std::move(*pendingEntry.payload.constCallCacheKey), cstRef);
    }

    // A root's order includes everything it reaches. Skip roots already encountered
    // to avoid traversing the same closure again.
    void appendJitOrderDeduplicated(const SymbolFunction& root, SmallVector<SymbolFunction*>& out, PointerSet<SymbolFunction>& seen)
    {
        if (seen.contains(&root))
            return;

        root.visitJitOrder([&out, &seen](SymbolFunction* function) {
            if (!function)
                return;
            if (function->attributes().hasMacroOrMixin())
                return;
            if (!seen.insert(function))
                return;

            out.push_back(function);
        });
    }

    void appendGlobalFunctionInitJitOrder(Sema& sema, SmallVector<SymbolFunction*>& out, PointerSet<SymbolFunction>& seen)
    {
        const auto targets = sema.compiler().nativeGlobalFunctionInitTargetsSnapshot();
        for (const SymbolFunction* target : targets)
        {
            if (!target)
                continue;
            if (target->isForeignOrEmptyOrAttribute())
                continue;

            appendJitOrderDeduplicated(*target, out, seen);
        }
    }

    bool isIncludableConstantJitDependency(const SymbolFunction& fn)
    {
        if (fn.isIgnored())
            return false;
        if (fn.isForeignOrEmptyOrAttribute())
            return false;
        if (fn.attributes().hasMacroOrMixin())
            return false;
        if (fn.hasExtraFlag(SymbolFunctionFlagsE::LazyBodyRunning))
            return false;

        return fn.isSemaCompleted() || fn.hasExtraFlag(SymbolFunctionFlagsE::LazyBody);
    }

    bool isIncludableOptionalConstantJitRoot(const SymbolFunction& root)
    {
        // Metadata may remain unpublished while the runtime call graph is incomplete.
        // Pulling an interface method into #ast could wait on the function containing
        // that #ast. Stop at the first dependency that cannot yet be included.
        return root.allInJitOrder([](const SymbolFunction* dependency) {
            if (dependency->isForeignOrEmptyOrAttribute())
                return true;
            if (dependency->attributes().hasMacroOrMixin())
                return true;

            return isIncludableConstantJitDependency(*dependency);
        });
    }

    // Reuse traversal tables per worker: a module performs thousands of constant-graph walks.
    // Keep discovered targets, shard versions and visited nodes in one traversal state.
    struct ConstantJitTargetWalk
    {
        SymbolFunction::ConstantJitTargetList         targets;
        SmallVector<std::pair<uint32_t, uint64_t>, 2> shardVersions;

        StampedKeySet              visitedAllocations;
        PointerSet<SymbolFunction> seenStrictTargets;
        PointerSet<SymbolFunction> seenOptionalTargets;

        uint32_t seenShardMask = 0;

        void reset()
        {
            targets.clear();
            shardVersions.clear();
            visitedAllocations.clear();
            seenStrictTargets.clear();
            seenOptionalTargets.clear();
            seenShardMask = 0;
        }
    };

    // Follow data relocations transitively to collect function targets. The caller
    // decides which targets can be included using their current semantic state.
    void collectConstantJitTargets(Sema& sema, ConstantJitTargetWalk& walk, uint32_t shardIndex, uint32_t sourceOffset)
    {
        SmallVector<DataSegmentRef> pending{{.shardIndex = shardIndex, .offset = sourceOffset}};

        while (!pending.empty())
        {
            const DataSegmentRef current = pending.back();
            pending.pop_back();

            const DataSegment& segment = sema.cstMgr().shardDataSegment(current.shardIndex);

            // Record a shard's version before reading its allocations: cached results
            // remain valid only while every visited shard keeps that version.
            SWC_ASSERT(current.shardIndex < ConstantStorageLayout::SHARD_COUNT);
            const uint32_t shardBit = 1u << current.shardIndex;
            if (!(walk.seenShardMask & shardBit))
            {
                walk.seenShardMask |= shardBit;
                walk.shardVersions.push_back({current.shardIndex, segment.relocationVersion()});
            }

            const ConstantManager::WalkedAllocation* walked = sema.cstMgr().walkedAllocation(current.shardIndex, current.offset);
            if (!walked)
                continue;

            // Nested reflection and interface tables can reach functions through any
            // data relocation. Match the graph used to detect unpublished metadata.
            // The high bit keeps the first allocation of the first shard from packing to zero,
            // which the table reads as a free slot.
            const uint64_t allocationKey = 1ULL << 63 | static_cast<uint64_t>(current.shardIndex) << 32 | walked->allocation.offset;
            if (!walk.visitedAllocations.insert(allocationKey))
                continue;

            for (const DataSegmentRelocation& relocation : walked->relocations)
            {
                if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
                {
                    const uint32_t targetShard = relocation.targetShardIndex == INVALID_REF ? current.shardIndex : relocation.targetShardIndex;
                    pending.push_back({.shardIndex = targetShard, .offset = relocation.targetOffset});
                }
                else
                {
                    auto* target = const_cast<SymbolFunction*>(relocation.targetSymbol);
                    if (!target)
                        continue;

                    // Strict and optional relocations impose different requirements.
                    // Retain each kind once, even when both reach the same target.
                    PointerSet<SymbolFunction>& seen = relocation.allowUnresolvedFunction ? walk.seenOptionalTargets : walk.seenStrictTargets;
                    if (!seen.insert(target))
                        continue;

                    walk.targets.emplace_back(target, relocation.allowUnresolvedFunction);
                }
            }
        }
    }

    void walkConstantJitTargets(Sema& sema, ConstantJitTargetWalk& walk, const SymbolFunction& function)
    {
        for (const MicroRelocation& relocation : function.loweredCode().codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
                continue;
            if (!relocation.hasConstantSource())
                continue;

            collectConstantJitTargets(sema, walk, relocation.constantShard, relocation.constantOffset);
        }
    }

    bool constantJitTargetsAreCurrent(Sema& sema, const SymbolFunction::ConstantJitTargets& cache)
    {
        for (const auto& [shardIndex, version] : cache.shardVersions)
        {
            if (sema.cstMgr().shardDataSegment(shardIndex).relocationVersion() != version)
                return false;
        }

        return true;
    }

    // Cache each function's targets by constant-graph version to avoid repeated walks
    // for every compile-time call. Unlowered code has no relocations to cache yet.
    std::shared_ptr<const SymbolFunction::ConstantJitTargetList> constantJitTargetsOf(Sema& sema, const SymbolFunction& function)
    {
        const bool remembers = function.hasLoweredCode();
        if (remembers)
        {
            // Readers only copy the shared list out; they share the lock.
            const std::shared_lock lock(function.constantJitTargetsMutex());
            const auto&            cache = function.constantJitTargets();
            if (cache.targets && constantJitTargetsAreCurrent(sema, cache))
                return cache.targets;
        }

        static thread_local ConstantJitTargetWalk walk;
        walk.reset();
        walkConstantJitTargets(sema, walk, function);

        auto targets = std::make_shared<SymbolFunction::ConstantJitTargetList>(std::move(walk.targets));
        if (!remembers)
            return targets;

        const std::scoped_lock lock(function.constantJitTargetsMutex());
        auto&                  cache = function.constantJitTargets();
        cache.targets                = targets;
        cache.shardVersions          = walk.shardVersions;

        return targets;
    }

    bool appendConstantFunctionJitRoots(Sema& sema, const SymbolFunction& symFn, SmallVector<SymbolFunction*>& roots, std::span<SymbolFunction* const> functions)
    {
        // Targets already in the run's call graph add no roots. Reuse a flat table
        // per worker because each module performs thousands of compile-time calls.
        static thread_local PointerSet<SymbolFunction> seenFunctions;
        seenFunctions.clear();
        seenFunctions.reserve(roots.size() + functions.size() + 1);

        for (SymbolFunction* root : roots)
        {
            if (root)
                seenFunctions.insert(root);
        }

        seenFunctions.insert(const_cast<SymbolFunction*>(&symFn));
        for (SymbolFunction* function : functions)
        {
            if (function)
                seenFunctions.insert(function);
        }

        // Accepted roots immediately enter seenFunctions. Only rejected optional roots need
        // another verdict cache; a strict relocation must still be allowed to include them.
        static thread_local PointerSet<SymbolFunction> rejectedOptionalRoots;
        rejectedOptionalRoots.clear();

        bool changed = false;
        for (const SymbolFunction* function : functions)
        {
            if (!function)
                continue;

            const auto constantTargets = constantJitTargetsOf(sema, *function);
            for (const auto& [target, allowUnresolved] : *constantTargets)
            {
                if (seenFunctions.contains(target))
                    continue;
                if (!isIncludableConstantJitDependency(*target))
                    continue;

                if (allowUnresolved)
                {
                    if (rejectedOptionalRoots.contains(target))
                        continue;

                    if (!isIncludableOptionalConstantJitRoot(*target))
                    {
                        rejectedOptionalRoots.insert(target);
                        continue;
                    }
                }

                seenFunctions.insert(target);

                roots.push_back(target);
                changed = true;
            }
        }

        return changed;
    }

    void buildJitOrderWithNativeRoots(Sema& sema, const SymbolFunction& symFn, SmallVector<SymbolFunction*>& out, std::span<SymbolFunction* const> extraRoots = {})
    {
        // Each root's order is already unique, but roots often share most dependencies.
        // Build membership alongside the output so previously reached roots need no walk.
        const bool mayRepeat = !extraRoots.empty() || SemaRuntime::isRuntimeArtifactFunction(sema.compiler(), symFn);
        if (!mayRepeat)
        {
            symFn.visitJitOrder([&out](SymbolFunction* function) {
                if (!function)
                    return;
                if (function->attributes().hasMacroOrMixin())
                    return;

                out.push_back(function);
            });

            return;
        }

        // This walk only reads dependency snapshots; it cannot run another semantic job.
        // Reuse the worker's table, clearing all prior symbol pointers before each walk.
        static thread_local PointerSet<SymbolFunction> seen;
        seen.clear();
        appendJitOrderDeduplicated(symFn, out, seen);

        for (const SymbolFunction* root : extraRoots)
        {
            if (!root)
                continue;

            appendJitOrderDeduplicated(*root, out, seen);
        }

        if (SemaRuntime::isRuntimeArtifactFunction(sema.compiler(), symFn))
            appendGlobalFunctionInitJitOrder(sema, out, seen);
    }

    uint64_t jitOrderFingerprint(Sema& sema, const SymbolFunction& symFn, std::span<SymbolFunction* const> extraRoots, const uint64_t callGraphVersion, const uint64_t targetsVersion)
    {
        uint64_t   fingerprint = 1469598103934665603ULL;
        const auto mix         = [&fingerprint](const uint64_t value) {
            fingerprint = (fingerprint ^ value) * 1099511628211ULL;
        };

        mix(reinterpret_cast<uintptr_t>(&symFn));
        mix(callGraphVersion);
        mix(targetsVersion);
        mix(extraRoots.size());
        for (const SymbolFunction* root : extraRoots)
            mix(reinterpret_cast<uintptr_t>(root));

        // Constant function roots can appear without changing the call graph. Their source is
        // the relocation graph across these shards; its versions are a compact invalidation key.
        for (uint32_t shardIndex = 0; shardIndex < ConstantStorageLayout::SHARD_COUNT; ++shardIndex)
            mix(sema.cstMgr().shardDataSegment(shardIndex).relocationVersion());
        mix(sema.compiler().globalInitSegment().relocationVersion());

        return fingerprint ? fingerprint : 1;
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

    Result prepareJitSetupRuntimeFunction(Sema& sema, const SymbolFunction& symFn)
    {
        if (!jitEntryNeedsRuntimeSetup(sema, symFn))
            return Result::Continue;

        SymbolFunction* setupFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime, setupFn, symFn.codeRef()));
        if (!setupFn || setupFn == &symFn)
            return Result::Continue;

        return prepareJitFunction(sema, *setupFn);
    }

    const SymbolFunction* jitWaiterSymbol(Sema& sema)
    {
        const SymbolFunction* currentFn = sema.currentFunction();
        if (currentFn && SemaRuntime::isCompilerOnlyFunction(sema.compiler(), *currentFn))
            return currentFn;

        const SymbolFunction* enclosingFn = sema.frame().enclosingFunction();
        if (enclosingFn)
            return enclosingFn;

        return currentFn;
    }

    Result prepareJitFunction(Sema& sema, SymbolFunction& symFn)
    {
        TaskContext& ctx = sema.ctx();

        // This version is published only after the runtime setup and this root's
        // entire preparation succeed. A ready root needs neither walk repeated.
        if (symFn.jitEntryAddress() && symFn.jitReadyVersion() == sema.compiler().nativeGlobalFunctionInitTargetsVersion())
        {
            ctx.state().jitEmissionError = false;
            return Result::Continue;
        }

        SWC_RESULT(prepareJitSetupRuntimeFunction(sema, symFn));
        ctx.state().jitEmissionError = false;

        // Setup can publish new global targets or finish a concurrent preparation.
        // Only its resulting version describes the work this preparation closes.
        const uint64_t initTargetsVersion = sema.compiler().nativeGlobalFunctionInitTargetsVersion();
        if (symFn.jitEntryAddress() && symFn.jitReadyVersion() == initTargetsVersion)
            return Result::Continue;

        // Publish release summaries before scheduling codegen, which emits before completion
        // and can reject stale reads in its sanity pass. Waiting only on sema allows recursion.
        // Keep the completed order and its versions for reuse in the first codegen round.
        SmallVector<SymbolFunction*> semaOrder;
        uint64_t                     semaOrderCallGraphVersion = 0;
        uint64_t                     semaOrderTargetsVersion   = 0;

        while (true)
        {
            semaOrderCallGraphVersion = SymbolFunction::callGraphVersion();
            semaOrderTargetsVersion   = sema.compiler().nativeGlobalFunctionInitTargetsVersion();
            semaOrder.clear();
            buildJitOrderWithNativeRoots(sema, symFn, semaOrder);

            for (const SymbolFunction* function : semaOrder)
                SWC_RESULT(sema.waitSemaCompleted(function, function->codeRef()));

            // Sema can add dependencies or native roots. Reuse this order only when neither
            // version moved while its functions were being completed.
            if (SymbolFunction::callGraphVersion() == semaOrderCallGraphVersion &&
                sema.compiler().nativeGlobalFunctionInitTargetsVersion() == semaOrderTargetsVersion)
            {
                const uint64_t orderFingerprint = jitOrderFingerprint(sema, symFn, {}, semaOrderCallGraphVersion, semaOrderTargetsVersion);
                SemaEscape::propagateCompletedFreesSummaries(ctx, semaOrder.span(), orderFingerprint);
                break;
            }
        }

        sema.compiler().tryEnqueueCodeGenJob(sema, symFn, symFn.declNodeRef());
        SWC_RESULT(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
        if (ctx.state().jitEmissionError)
            return reportJitEvaluationFailure(sema, symFn);

        // Schedule newly discovered dependencies until the closure stabilizes. Call-graph
        // and native-root versions detect stability without rebuilding the membership set.
        SmallVector<SymbolFunction*> constantRoots;
        SmallVector<SymbolFunction*> stableJitOrder;

        while (true)
        {
            uint64_t stableCallGraphVersion = 0;
            uint64_t stableTargetsVersion   = 0;

            while (true)
            {
                const uint64_t orderCallGraphVersion = SymbolFunction::callGraphVersion();
                const uint64_t orderTargetsVersion   = sema.compiler().nativeGlobalFunctionInitTargetsVersion();

                SmallVector<SymbolFunction*> jitOrder;
                if (constantRoots.empty() && !semaOrder.empty() && orderCallGraphVersion == semaOrderCallGraphVersion && orderTargetsVersion == semaOrderTargetsVersion)
                    jitOrder = std::move(semaOrder);
                else
                    buildJitOrderWithNativeRoots(sema, symFn, jitOrder, constantRoots.span());

                // Read once at most: a later round rebuilds from the roots it has by then.
                semaOrder.clear();

                for (SymbolFunction* function : jitOrder)
                    sema.compiler().tryEnqueueCodeGenJob(sema, *function, function->declNodeRef());

                for (const SymbolFunction* function : jitOrder)
                {
                    SWC_RESULT(sema.waitCodeGenPreSolved(function, function->codeRef()));
                }

                if (SymbolFunction::callGraphVersion() == orderCallGraphVersion &&
                    sema.compiler().nativeGlobalFunctionInitTargetsVersion() == orderTargetsVersion)
                {
                    // Both versions stayed unchanged while waiting: this order is stable,
                    // and every function has completed waitCodeGenPreSolved.
                    stableJitOrder         = std::move(jitOrder);
                    stableCallGraphVersion = orderCallGraphVersion;
                    stableTargetsVersion   = orderTargetsVersion;
                    break;
                }
            }

            // The module-wide summary fixpoint runs after sema drains, but #run must emit
            // and execute this completed call graph now. Publish its transitive frees first
            // so the static lifecycle pass sees the same facts as ordinary code generation.
            const uint64_t orderFingerprint = jitOrderFingerprint(sema, symFn, constantRoots.span(), stableCallGraphVersion, stableTargetsVersion);
            SemaEscape::propagateCompletedFreesSummaries(ctx, stableJitOrder.span(), orderFingerprint);

            for (SymbolFunction* function : stableJitOrder)
            {
                SWC_RESULT(function->emit(ctx));
            }

            if (!appendConstantFunctionJitRoots(sema, symFn, constantRoots, stableJitOrder.span()))
                break;
        }

        if (ctx.state().jitEmissionError)
            return reportJitEvaluationFailure(sema, symFn);

        SWC_RESULT(SymbolFunction::jitBatch(ctx, stableJitOrder, jitWaiterSymbol(sema)));

        if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
            return reportJitEvaluationFailure(sema, symFn);

        if (sema.compiler().nativeGlobalFunctionInitTargetsVersion() == initTargetsVersion)
            symFn.setJitReadyVersion(initTargetsVersion);

        return Result::Continue;
    }

    JITCallResultMeta computeJitCallResultMeta(Sema& sema, TypeRef exprTypeRef)
    {
        TaskContext&    ctx         = sema.ctx();
        const TypeInfo& storageType = sema.typeMgr().unwrapAliasEnumTypeOrSelf(ctx, exprTypeRef);

        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, CallConv::swag(), storageType, ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!storageType.isVoid());

        uint64_t resultSize;
        if (normalizedRet.isIndirect)
            resultSize = storageType.sizeOf(ctx);
        else
            resultSize = normalizedRet.numBits ? normalizedRet.numBits / 8 : 8;

        SWC_ASSERT(resultSize > 0);

        JITCallResultMeta resultMeta;
        resultMeta.exprTypeRef    = exprTypeRef;
        resultMeta.storageTypeRef = storageType.typeRef();
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

        auto* pendingEntry = pendingJitCompletionPayload(*completion);
        if (pendingEntry && completion->result == Result::Continue)
            applyPendingJitResult(sema, nodeRef, *pendingEntry);

        return completion->result;
    }

    // A request to run 'symFn' for 'nodeRef'.
    JITExecManager::Request jitNodeRequest(Sema& sema, const SymbolFunction& symFn, AstNodeRef nodeRef, bool runImmediate)
    {
        JITExecManager::Request request;
        request.function     = &symFn;
        request.nodeRef      = nodeRef;
        request.codeRef      = sema.node(nodeRef).codeRef();
        request.runImmediate = runImmediate;

        return request;
    }

    Result submitJitNode(Sema& sema, AstNodeRef nodeRef, JITExecManager::Request request, const std::shared_ptr<JITPendingNodeData>& pendingEntry, const JITCallResultMeta& resultMeta, bool setFoldedTypedConst)
    {
        TaskContext& ctx = sema.ctx();

        // Apply synchronous and deferred results through the same pending entry
        // so constant materialization and cache updates do not depend on scheduling.
        pendingEntry->resultMeta          = resultMeta;
        pendingEntry->setFoldedTypedConst = setFoldedTypedConst;
        request.completionPayload         = pendingEntry;

        const Result submitResult = sema.compiler().jitExecMgr().submit(ctx, request);
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

    bool supportsConstCallJit(Sema& sema, const SymbolFunction& calledFn, const bool forceEvaluation)
    {
        SWC_UNUSED(forceEvaluation);

        const AttributeList& attributes = calledFn.attributes();
        if (attributes.hasMacroOrMixin())
            return false;

        // Fallible calls depend on the runtime error context and must preserve
        // their TLS-visible side effects instead of being folded to a plain value.
        if (calledFn.isFallible())
            return false;

        if (!calledFn.isPure() && !attributes.hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isForeign() && !attributes.hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isEmptyNonForeign())
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
        const AttributeList& attributes = calledFn.attributes();
        if (attributes.hasMacroOrMixin())
            return false;
        if (calledFn.isFallible())
            return false;
        if (!attributes.hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return false;
        if (calledFn.isEmptyNonForeign())
            return false;
        if (!receiverTypeRef.isValid() || hasUnsupportedConstCallReturn(sema, receiverTypeRef))
            return false;
        if (calledFn.parameters().empty())
            return false;

        const TypeRef receiverParamTypeRef      = sema.typeMgr().unwrapAlias(sema.ctx(), calledFn.parameters().front()->typeRef());
        const TypeRef normalizedReceiverTypeRef = sema.typeMgr().unwrapAlias(sema.ctx(), receiverTypeRef);
        const TypeRef receiverParamRef          = receiverParamTypeRef.isValid() ? receiverParamTypeRef : calledFn.parameters().front()->typeRef();
        const TypeRef receiverType              = normalizedReceiverTypeRef.isValid() ? normalizedReceiverTypeRef : receiverTypeRef;

        const TypeInfo& receiverParam = sema.typeMgr().get(receiverParamRef);
        // Both reference and non-null value-pointer receivers bind by address.
        if (!receiverParam.isReferenceOrNonNullValuePointer())
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
        if (SemaCallArgument::tryResolveDefaultConstant(outCstRef, resolvedArg))
            return Result::Continue;

        const SourceCodeRange codeRange = sema.node(callRef).codeRangeWithChildren(sema.ctx(), sema.ast());
        return ConstantHelpers::makeSourceCodeLocation(sema, outCstRef, codeRange, SemaHelpers::currentLocationFunction(sema));
    }

    bool constantPayloadFitsByteSize(const ConstantValue& value, uint64_t byteSize)
    {
        if (value.isStruct())
            return value.getStruct().size() == byteSize;
        if (value.isArray())
            return value.getArray().size() == byteSize;

        return true;
    }

#if SWC_DEV_MODE
    // A folding overflow may surface later as an allocator failure on another thread.
    // Redzones identify the JIT-executed call that wrote past its buffer.
    constexpr uint64_t K_JIT_FOLD_REDZONE      = 64;
    constexpr uint8_t  K_JIT_FOLD_REDZONE_BYTE = 0xAB;
#endif

    std::byte* reserveJitFoldStorage(SmallVector<std::byte>& storage, const uint64_t size)
    {
        // Every caller supplies a freshly emplaced buffer; resize zeroes its bytes.
#if SWC_DEV_MODE
        storage.resize(size + K_JIT_FOLD_REDZONE);
        std::memset(storage.data() + size, K_JIT_FOLD_REDZONE_BYTE, K_JIT_FOLD_REDZONE);
#else
        storage.resize(size);
#endif
        return storage.data();
    }

    void pushJitArgument(SmallVector<JITArgument>& outJitArgs, TypeRef typeRef, const void* valuePtr)
    {
        JITArgument arg;
        arg.typeRef  = typeRef;
        arg.valuePtr = valuePtr;

        outJitArgs.push_back(arg);
    }

    // Passes the address of 'pointee' as an argument of type 'typeRef', held in 'storageSize' bytes.
    void pushJitPointerArgument(SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs, TypeRef typeRef, uint64_t storageSize, const std::byte* pointee)
    {
        auto& argStorage = outArgStorage.emplace_back();
        reserveJitFoldStorage(argStorage, storageSize);

        const uint64_t ptr = reinterpret_cast<uint64_t>(pointee);
        std::memcpy(argStorage.data(), &ptr, sizeof(ptr));
        pushJitArgument(outJitArgs, typeRef, argStorage.data());
    }

    void verifyJitFoldRedzones(Sema& sema, const SymbolFunction& calledFn, const SmallVector<SmallVector<std::byte>>& argStorage)
    {
#if SWC_DEV_MODE
        for (const SmallVector<std::byte>& storage : argStorage)
        {
            SWC_ASSERT(storage.size() >= K_JIT_FOLD_REDZONE);
            const uint64_t   size = storage.size() - K_JIT_FOLD_REDZONE;
            const std::byte* zone = storage.data() + size;

            for (uint64_t i = 0; i < K_JIT_FOLD_REDZONE; ++i)
            {
                if (zone[i] == std::byte{K_JIT_FOLD_REDZONE_BYTE})
                    continue;

                const Utf8 detail = std::format("  called function: {}\n  buffer size: {}\n  first corrupted redzone byte: +{}\n", calledFn.getFullScopedName(sema.ctx()), size, i);
                swcAssertDetail("JIT compile-time fold stayed within its buffers", __FILE__, __LINE__, detail.view());
            }
        }
#else
        SWC_UNUSED(sema);
        SWC_UNUSED(calledFn);
        SWC_UNUSED(argStorage);
#endif
    }

    __forceinline Result constCallArgumentConstantRef(Sema& sema, ConstantRef& outCstRef, const AstNodeRef& callRef, const ResolvedCallArgument& resolvedArg)
    {
        const AstNodeRef argRef = resolvedArg.argRef;
        if (argRef.isValid())
        {
            const SemaNodeView argConstView = sema.viewConstant(argRef);
            if (!argConstView.cstRef().isValid())
                return Result::Continue;

            outCstRef = argConstView.cstRef();
            return Result::Continue;
        }

        return defaultArgumentConstantRef(sema, outCstRef, callRef, resolvedArg);
    }

    __forceinline bool appendConstCallArgument(Sema& sema, SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs, const TypeRef& argValueTypeRef, const ConstantRef& argCstRef)
    {
        TaskContext&         ctx              = sema.ctx();
        const TypeInfo&      argValueType     = sema.typeMgr().get(argValueTypeRef);
        const ConstantValue& argConstantValue = sema.cstMgr().get(argCstRef);
        if (argValueType.isReferenceOrNonNullValuePointer() &&
            !argConstantValue.isNull() &&
            !argConstantValue.isValuePointer() &&
            !argConstantValue.isBlockPointer())
        {
            const TypeRef pointeeTypeRef = argValueType.payloadTypeRef();
            if (!pointeeTypeRef.isValid())
                return false;

            const TypeInfo& pointeeType     = sema.typeMgr().get(pointeeTypeRef);
            const uint64_t  pointeeByteSize = pointeeType.sizeOf(ctx);
            const uint64_t  argStorageSize  = argValueType.sizeOf(ctx);
            if (!argStorageSize || argStorageSize > std::numeric_limits<uint32_t>::max())
                return false;
            if (pointeeByteSize > std::numeric_limits<uint32_t>::max())
                return false;
            if (!constantPayloadFitsByteSize(argConstantValue, pointeeByteSize))
                return false;

            auto& pointeeStorage = outArgStorage.emplace_back();
            reserveJitFoldStorage(pointeeStorage, pointeeByteSize);
            SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, std::span{pointeeStorage.data(), pointeeByteSize}, argCstRef, pointeeType) == Result::Continue);

            pushJitPointerArgument(outArgStorage, outJitArgs, argValueTypeRef, argStorageSize, pointeeStorage.data());
            return true;
        }

        const uint64_t argStorageSize = argValueType.sizeOf(ctx);
        if (!argStorageSize)
            return false;

        SWC_ASSERT(argStorageSize <= std::numeric_limits<uint32_t>::max());
        if (argStorageSize > std::numeric_limits<uint32_t>::max())
            return false;
        if (!constantPayloadFitsByteSize(argConstantValue, argStorageSize))
            return false;

        auto& argStorage = outArgStorage.emplace_back();
        reserveJitFoldStorage(argStorage, argStorageSize);
        SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, std::span{argStorage.data(), argStorageSize}, argCstRef, argValueType) == Result::Continue);

        pushJitArgument(outJitArgs, argValueTypeRef, argStorage.data());
        return true;
    }

    Result buildConstCallArguments(Sema& sema, bool& outBuilt, const SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, SmallVector<SmallVector<std::byte>>& outArgStorage, SmallVector<JITArgument>& outJitArgs)
    {
        outBuilt = false;
        SWC_ASSERT(resolvedArgs.size() == calledFn.parameters().size());

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

            TypeRef argValueTypeRef = sema.typeMgr().unwrapAlias(ctx, param->typeRef());
            if (!argValueTypeRef.isValid())
                return Result::Continue;

            ConstantRef argCstRef = ConstantRef::invalid();
            SWC_RESULT(constCallArgumentConstantRef(sema, argCstRef, callRef, resolvedArg));
            if (!argCstRef.isValid())
                return Result::Continue;
            if (!appendConstCallArgument(sema, outArgStorage, outJitArgs, argValueTypeRef, argCstRef))
                return Result::Continue;
        }

        outBuilt = true;
        return Result::Continue;
    }

    // Mirror argument eligibility until a default needs materialization. Reject runtime
    // arguments before allocating the fold payload and its inline storage.
    bool explicitArgumentsCanFold(Sema& sema, const SymbolFunction& calledFn, std::span<const ResolvedCallArgument> resolvedArgs)
    {
        SWC_ASSERT(resolvedArgs.size() == calledFn.parameters().size());

        for (size_t i = 0; i < resolvedArgs.size(); ++i)
        {
            const ResolvedCallArgument& resolvedArg = resolvedArgs[i];
            if (resolvedArg.passKind != CallArgumentPassKind::Direct)
                return false;
            if (!sema.typeMgr().unwrapAlias(sema.ctx(), calledFn.parameters()[i]->typeRef()).isValid())
                return false;
            if (resolvedArg.argRef.isInvalid())
                return true;
            if (!sema.viewConstant(resolvedArg.argRef).cstRef().isValid())
                return false;
        }

        return true;
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

            TypeRef argValueTypeRef = sema.typeMgr().unwrapAlias(ctx, param->typeRef());
            if (!argValueTypeRef.isValid())
                return Result::Continue;

            if (i == 0)
            {
                const TypeInfo& argValueType = sema.typeMgr().get(argValueTypeRef);
                // Both reference and non-null value-pointer receivers bind by address.
                if (!argValueType.isReferenceOrNonNullValuePointer())
                    return Result::Continue;

                const TypeRef pointeeTypeRef = argValueType.payloadTypeRef();
                if (!pointeeTypeRef.isValid())
                    return Result::Continue;

                const TypeInfo& receiverType    = sema.typeMgr().get(receiverTypeRef);
                const uint64_t  pointeeByteSize = receiverType.sizeOf(ctx);
                const uint64_t  argStorageSize  = argValueType.sizeOf(ctx);
                if (!argStorageSize || argStorageSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;
                if (pointeeByteSize > std::numeric_limits<uint32_t>::max())
                    return Result::Continue;
                if (receiverInitCstRef.isValid() && !constantPayloadFitsByteSize(sema.cstMgr().get(receiverInitCstRef), pointeeByteSize))
                    return Result::Continue;

                auto& pointeeStorage = outArgStorage.emplace_back();
                reserveJitFoldStorage(pointeeStorage, pointeeByteSize);
                if (receiverInitCstRef.isValid())
                    SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, std::span{pointeeStorage.data(), pointeeByteSize}, receiverInitCstRef, receiverType) == Result::Continue);

                pushJitPointerArgument(outArgStorage, outJitArgs, argValueTypeRef, argStorageSize, pointeeStorage.data());
                outReceiverStorage = pointeeStorage.data();
                continue;
            }

            ConstantRef argCstRef = ConstantRef::invalid();
            SWC_RESULT(constCallArgumentConstantRef(sema, argCstRef, callRef, resolvedArg));
            if (!argCstRef.isValid())
                return Result::Continue;
            if (!appendConstCallArgument(sema, outArgStorage, outJitArgs, argValueTypeRef, argCstRef))
                return Result::Continue;
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

    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, nodeExprRef))
        return *completion;

    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;

    if (hasPendingJitNode(sema, nodeExprRef))
        return waitPendingJitNode(sema, symFn, nodeExprRef);

    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef           exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);

    SWC_RESULT(prepareJitFunction(sema, symFn));

    // Build payload and submit with shared node lifecycle.
    const auto      pendingEntry = std::make_shared<JITPendingNodeData>();
    JITNodePayload& payload      = pendingEntry->payload;
    payload.resultStorage.resize(resultMeta.resultSize);

    JITExecManager::Request request = jitNodeRequest(sema, symFn, nodeExprRef, false);

    request.arg0    = reinterpret_cast<uint64_t>(payload.resultStorage.data());
    request.hasArg0 = true;

    return submitJitNode(sema, nodeExprRef, request, pendingEntry, resultMeta, false);
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

    JITExecManager::Request request = jitNodeRequest(sema, symFn, nodeExprRef, true);

    request.arg0    = reinterpret_cast<uint64_t>(resultStorage.data());
    request.hasArg0 = true;

    const Result jitResult = sema.compiler().jitExecMgr().submit(sema.ctx(), request);
    if (jitResult != Result::Continue)
        return reportJitEvaluationFailure(sema, symFn);

    sema.setConstant(nodeExprRef, makeJitCallResultConstantRef(sema, resultMeta, resultStorage.data()));
    return Result::Continue;
}

Result SemaJIT::runFunctionResult(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, nodeRef))
        return *completion;

    if (sema.viewConstant(nodeRef).hasConstant())
        return Result::Continue;

    if (hasPendingJitNode(sema, nodeRef))
        return waitPendingJitNode(sema, symFn, nodeRef);

    if (!symFn.returnTypeRef().isValid())
        return Result::Error;

    const JITCallResultMeta resultMeta = computeJitCallResultMeta(sema, symFn.returnTypeRef());
    SWC_RESULT(prepareJitFunction(sema, symFn));

    // Build payload and submit with shared node lifecycle.
    const auto      pendingEntry = std::make_shared<JITPendingNodeData>();
    JITNodePayload& payload      = pendingEntry->payload;
    payload.resultStorage.resize(resultMeta.resultSize);

    JITExecManager::Request request = jitNodeRequest(sema, symFn, nodeRef, false);

    request.jitReturn    = JITReturn{.typeRef = symFn.returnTypeRef(), .valuePtr = payload.resultStorage.data()};
    request.hasJitReturn = true;

    return submitJitNode(sema, nodeRef, request, pendingEntry, resultMeta, false);
}

Result SemaJIT::tryRunConstCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, const bool forceEvaluation)
{
    // Resume path: consume deferred completion if present.
    if (const std::optional<Result> completion = consumeJitExecCompletionAndApply(sema, callRef))
        return *completion;

    if (sema.isRunExprContext() && !forceEvaluation)
        return Result::Continue;

    // Skip optional folding when optimization is disabled. Explicit ConstExpr functions
    // must still fold when the argument checks below establish constant inputs.
    if (!sema.isOptimizeEnabled() &&
        !sema.isConstExprRequired() &&
        !forceEvaluation &&
        !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
        return Result::Continue;
    if (sema.viewConstant(callRef).hasConstant() && !forceEvaluation)
        return Result::Continue;

    const SymbolFunction* currentFn = sema.currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;

    if (sema.isConstExprRequired() || forceEvaluation)
        SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    // Eligibility facts, including purity, are final after semantic completion.
    // Recheck after waiting only if the first decision used an incomplete function.
    const bool completedBeforeEligibility = calledFn.isSemaCompleted();
    if (!supportsConstCallJit(sema, calledFn, forceEvaluation))
        return Result::Continue;

    if (hasPendingJitNode(sema, callRef))
        return waitPendingJitNode(sema, calledFn, callRef);

    SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));
    if (!completedBeforeEligibility && !supportsConstCallJit(sema, calledFn, forceEvaluation))
        return Result::Continue;

    // Build payload and arguments for call folding.
    if (resolvedArgs.size() != calledFn.parameters().size() || hasAnyVariadicParameter(sema, calledFn))
        return Result::Continue;
    if (!explicitArgumentsCanFold(sema, calledFn, resolvedArgs))
        return Result::Continue;

    const auto      pendingEntry = std::make_shared<JITPendingNodeData>();
    JITNodePayload& payload      = pendingEntry->payload;
    bool            built        = false;
    SWC_RESULT(buildConstCallArguments(sema, built, calledFn, callRef, resolvedArgs, payload.argStorage, payload.jitArgs));
    if (!built)
        return Result::Continue;

    // Runtime metadata can acquire function addresses after this semantic walk.
    // An explicit compile-time request may inspect the current snapshot, but an
    // optional fold must preserve the later read and must not memoize that snapshot.
    bool       unstableMetadata = hasUnpublishedFunctionArguments(sema, payload.jitArgs.span());
    const bool optionalFold     = !forceEvaluation && !sema.isConstExprRequired() && !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr);
    if (unstableMetadata && optionalFold)
        return Result::Continue;

    if (!calledFn.isForeign())
    {
        SWC_RESULT(prepareJitFunction(sema, calledFn));
        unstableMetadata = unstableMetadata || hasUnpublishedFunctionConstants(sema, calledFn);
        if (unstableMetadata && optionalFold)
            return Result::Continue;
    }

    const TypeRef           exprTypeRef = calledFn.returnTypeRef();
    const JITCallResultMeta resultMeta  = computeJitCallResultMeta(sema, exprTypeRef);

    ConstCallCacheKey cacheKey;
    if (!forceEvaluation && !unstableMetadata && buildConstCallCacheKey(sema, cacheKey, calledFn, resolvedArgs, payload.jitArgs.span()))
    {
        if (const ConstantRef cachedRef = findConstCallCacheResult(sema, cacheKey); cachedRef.isValid())
        {
            sema.setFoldedTypedConst(callRef);
            sema.setConstant(callRef, cachedRef);
            return Result::Continue;
        }

        payload.constCallCacheKey = std::move(cacheKey);
    }

    payload.resultStorage.resize(resultMeta.resultSize);
    if (calledFn.isForeign())
    {
        const JITReturn jitReturn = {.typeRef = exprTypeRef, .valuePtr = payload.resultStorage.data()};
        SWC_RESULT(emitForeignConstExprCall(sema, calledFn, payload.jitArgs.span(), jitReturn));
        verifyJitFoldRedzones(sema, calledFn, payload.argStorage);

        const ConstantRef resultCstRef = makeJitCallResultConstantRef(sema, resultMeta, payload.resultStorage.data());
        if (payload.constCallCacheKey)
            cacheConstCallResult(sema, std::move(*payload.constCallCacheKey), resultCstRef);

        sema.setFoldedTypedConst(callRef);
        sema.setConstant(callRef, resultCstRef);
        return Result::Continue;
    }

    JITExecManager::Request request = jitNodeRequest(sema, calledFn, callRef, false);

    request.jitArgs      = payload.jitArgs.span();
    request.jitReturn    = JITReturn{.typeRef = exprTypeRef, .valuePtr = payload.resultStorage.data()};
    request.hasJitReturn = true;

    return submitJitNode(sema, callRef, request, pendingEntry, resultMeta, true);
}

Result SemaJIT::tryRunConstSetCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, const TypeRef receiverTypeRef, const ConstantRef receiverInitCstRef, const bool forceEvaluation)
{
    if (!supportsConstSetCallJit(sema, calledFn, receiverTypeRef))
        return Result::Continue;
    if (sema.isRunExprContext())
        return Result::Continue;

    // A partial initializer reads the implicit receiver default. Replacing a runtime
    // default with the JIT argument buffer's zeros would change that value.
    if (!calledFn.hasFullInitialization() && receiverInitCstRef.isInvalid() && SymbolStruct::typeHasRuntimeImplicitDefault(sema, receiverTypeRef))
        return Result::Continue;

    // Skip optional folding when optimization is disabled. Explicit ConstExpr functions
    // must still fold when the argument checks below establish constant inputs.
    if (!sema.isOptimizeEnabled() &&
        !sema.isConstExprRequired() &&
        !forceEvaluation &&
        !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
        return Result::Continue;

    const SymbolFunction* currentFn = sema.currentFunction();
    if (currentFn == &calledFn)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(&calledFn, sema.node(callRef).codeRef()));

    SmallVector<SmallVector<std::byte>> argStorage;
    SmallVector<JITArgument>            jitArgs;

    const std::byte* receiverStorage = nullptr;
    bool             built           = false;
    SWC_RESULT(buildConstSetCallArguments(sema, built, calledFn, callRef, resolvedArgs, receiverTypeRef, receiverInitCstRef, receiverStorage, argStorage, jitArgs));
    if (!built)
        return Result::Continue;

    if (calledFn.isForeign())
    {
        SWC_RESULT(emitForeignConstExprCall(sema, calledFn, jitArgs.span(), {.typeRef = sema.typeMgr().typeVoid(), .valuePtr = nullptr}));
        verifyJitFoldRedzones(sema, calledFn, argStorage);

        const uint64_t    structSize   = sema.typeMgr().get(receiverTypeRef).sizeOf(sema.ctx());
        const ConstantRef resultCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, receiverTypeRef, std::span{receiverStorage, structSize});
        sema.setConstant(callRef, resultCstRef);
        sema.setFoldedTypedConst(callRef);
        return Result::Continue;
    }

    SWC_RESULT(prepareJitFunction(sema, calledFn));

    JITExecManager::Request request = jitNodeRequest(sema, calledFn, callRef, true);

    request.jitArgs      = jitArgs.span();
    request.jitReturn    = JITReturn{.typeRef = sema.typeMgr().typeVoid(), .valuePtr = nullptr};
    request.hasJitReturn = true;

    const Result jitResult = sema.compiler().jitExecMgr().submit(sema.ctx(), request);
    verifyJitFoldRedzones(sema, calledFn, argStorage);
    if (jitResult != Result::Continue)
        return reportJitEvaluationFailure(sema, calledFn);

    const uint64_t    structSize   = sema.typeMgr().get(receiverTypeRef).sizeOf(sema.ctx());
    const ConstantRef resultCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, receiverTypeRef, std::span{receiverStorage, structSize});
    sema.setConstant(callRef, resultCstRef);
    sema.setFoldedTypedConst(callRef);
    return Result::Continue;
}

Result SemaJIT::runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    // Resume path: consume deferred completion if present.
    if (const std::optional<JITExecManager::Completion> completion = consumeJitExecCompletion(sema, nodeRef))
        return completion->result;

    SWC_RESULT(prepareJitFunction(sema, symFn));

    TaskContext& ctx = sema.ctx();

    JITExecManager::Request request = jitNodeRequest(sema, symFn, nodeRef, false);
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

    TaskContext& ctx = sema.ctx();

    JITExecManager::Request request = jitNodeRequest(sema, symFn, nodeRef, true);
    return sema.compiler().jitExecMgr().submit(ctx, request);
}

SWC_END_NAMESPACE();

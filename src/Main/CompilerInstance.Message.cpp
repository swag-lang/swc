#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerMessageTypeInfoJob.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Main/TaskState.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t compilerMessageBit(const Runtime::CompilerMsgKind kind)
    {
        return 1ull << static_cast<uint32_t>(kind);
    }

    constexpr uint64_t trackedCompilerMessageSemaMask()
    {
        return compilerMessageBit(Runtime::CompilerMsgKind::SemFunctions) |
               compilerMessageBit(Runtime::CompilerMsgKind::SemTypes) |
               compilerMessageBit(Runtime::CompilerMsgKind::SemGlobals);
    }

    bool isCompilerMessageEligibleFunction(const SymbolFunction& symbol)
    {
        return !symbol.isIgnored() &&
               !symbol.isForeign() &&
               !symbol.hasUnmaterializedGenericBody() &&
               !symbol.isAttribute() &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Macro) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
    }

    template<typename T>
    bool isImportedCompilerMessageSource(const CompilerInstance& compiler, const T& symbol)
    {
        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && sourceFile->isImportedApi();
    }

    struct DeferredCompilerGeneratedSource
    {
        Utf8                   text;
        const SymbolNamespace* moduleNamespace = nullptr;
    };

    struct CompilerMessageBacklogEntry
    {
        Symbol*                  symbol = nullptr;
        Runtime::CompilerMsgKind kind   = Runtime::CompilerMsgKind::PassAfterSemantic;
        Utf8                     key;
    };

    bool compilerMessageBacklogEntryLess(const CompilerMessageBacklogEntry& lhs, const CompilerMessageBacklogEntry& rhs)
    {
        if (lhs.key != rhs.key)
            return lhs.key < rhs.key;
        return static_cast<uint32_t>(lhs.kind) < static_cast<uint32_t>(rhs.kind);
    }

    struct CompilerMessageDispatchStep
    {
        size_t                                 listenerIndex = 0;
        size_t                                 eventIndex    = 0;
        bool                                   fromReplay    = false;
        CompilerInstance::CompilerMessageEvent event;
        SymbolFunction*                        function = nullptr;
        AstNodeRef                             nodeRef  = AstNodeRef::invalid();
    };

    struct CompilerMessageDispatchState
    {
        const CompilerInstance*                       compiler         = nullptr;
        const SymbolNamespace*                        moduleNamespace  = nullptr;
        std::vector<DeferredCompilerGeneratedSource>* generatedSources = nullptr;
    };

    struct CompilerMessageListenerExecutionState
    {
        size_t                listenerIndex = static_cast<size_t>(-1);
        const SourceFile*     file          = nullptr;
        std::unique_ptr<Sema> sema;
    };

    thread_local CompilerMessageDispatchState* g_CompilerMessageDispatchState = nullptr;

    struct ScopedCompilerMessageDispatchState
    {
        explicit ScopedCompilerMessageDispatchState(const CompilerInstance& compiler, const SymbolNamespace* moduleNamespace, std::vector<DeferredCompilerGeneratedSource>& generatedSources)
        {
            previous_                      = g_CompilerMessageDispatchState;
            state_.compiler                = &compiler;
            state_.moduleNamespace         = moduleNamespace;
            state_.generatedSources        = &generatedSources;
            g_CompilerMessageDispatchState = &state_;
        }

        ~ScopedCompilerMessageDispatchState()
        {
            g_CompilerMessageDispatchState = previous_;
        }

        ScopedCompilerMessageDispatchState(const ScopedCompilerMessageDispatchState&)            = delete;
        ScopedCompilerMessageDispatchState& operator=(const ScopedCompilerMessageDispatchState&) = delete;

    private:
        CompilerMessageDispatchState  state_;
        CompilerMessageDispatchState* previous_ = nullptr;
    };

    bool deferCompilerMessageGeneratedSource(const CompilerInstance& compiler, const std::string_view generatedCode)
    {
        const CompilerMessageDispatchState* state = g_CompilerMessageDispatchState;
        if (!state)
            return false;
        if (state->compiler != &compiler || !state->generatedSources)
            return false;

        DeferredCompilerGeneratedSource generatedSource;
        generatedSource.text            = generatedCode;
        generatedSource.moduleNamespace = state->moduleNamespace;
        state->generatedSources->push_back(std::move(generatedSource));
        return true;
    }

    Result ensureCompilerMessageListenerSema(CompilerMessageListenerExecutionState& state, TaskContext& ctx, const CompilerMessageDispatchStep& dispatch, const SourceFile*& outFile, Sema*& outSema)
    {
        if (state.listenerIndex == dispatch.listenerIndex &&
            state.file != nullptr &&
            state.sema != nullptr)
        {
            outFile = state.file;
            outSema = state.sema.get();
            return Result::Continue;
        }

        const SourceFile* listenerFile = ctx.compiler().sourceViewFile(*dispatch.function);
        if (!listenerFile)
            return Result::Error;

        state.listenerIndex = dispatch.listenerIndex;
        state.file          = listenerFile;
        state.sema          = std::make_unique<Sema>(ctx, const_cast<SourceFile*>(listenerFile)->nodePayloadContext(), false);
        outFile             = listenerFile;
        outSema             = state.sema.get();
        return Result::Continue;
    }

    const SymbolNamespace* firstModuleNamespace(const CompilerInstance& compiler)
    {
        for (const SourceFile* file : compiler.filesSnapshot())
        {
            if (!file)
                continue;

            if (const SymbolNamespace* moduleNamespace = file->moduleNamespace())
                return moduleNamespace;
        }

        return nullptr;
    }

    const SymbolNamespace* currentModuleNamespace(const TaskContext& ctx)
    {
        const TaskState& state = ctx.state();
        if (state.codeRef.srcViewRef.isValid())
        {
            const SourceFile* file = ctx.compiler().sourceViewFile(state.codeRef.srcViewRef);
            if (file && file->moduleNamespace())
                return file->moduleNamespace();
        }

        return firstModuleNamespace(ctx.compiler());
    }

    bool isModuleLevelSymbol(const Symbol& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        if (!owner)
            return false;

        while (owner)
        {
            if (owner->isFunction())
                return false;
            owner = owner->ownerSymMap();
        }

        return true;
    }

    bool shouldTrackCompilerMessageFunction(const CompilerInstance& compiler, const SymbolFunction& symbol)
    {
        if (!symbol.isSemaCompleted() || symbol.isIgnored())
            return false;
        if (!isCompilerMessageEligibleFunction(symbol))
            return false;
        if (isImportedCompilerMessageSource(compiler, symbol))
            return false;
        if (!isModuleLevelSymbol(symbol))
            return false;

        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && !sourceFile->isRuntime();
    }

    bool shouldTrackCompilerMessageType(const CompilerInstance& compiler, const Symbol& symbol)
    {
        if (!symbol.isSemaCompleted() || symbol.isIgnored())
            return false;
        if (!symbol.isType())
            return false;
        if (!symbol.idRef().isValid())
            return false;
        if (isImportedCompilerMessageSource(compiler, symbol))
            return false;
        if (!isModuleLevelSymbol(symbol))
            return false;

        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && !sourceFile->isRuntime();
    }

    bool shouldTrackCompilerMessageGlobal(const CompilerInstance& compiler, const SymbolVariable& symbol)
    {
        if (!symbol.isSemaCompleted() || symbol.isIgnored())
            return false;
        if (!symbol.hasGlobalStorage() || symbol.globalStorageKind() == DataSegmentKind::Compiler)
            return false;
        if (isImportedCompilerMessageSource(compiler, symbol))
            return false;
        if (!isModuleLevelSymbol(symbol))
            return false;

        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && !sourceFile->isRuntime();
    }

    std::optional<Runtime::CompilerMsgKind> compilerMessageKindForSymbol(const CompilerInstance& compiler, const Symbol& symbol, const uint64_t activeMask)
    {
        if ((activeMask & compilerMessageBit(Runtime::CompilerMsgKind::SemFunctions)) &&
            symbol.isFunction() &&
            shouldTrackCompilerMessageFunction(compiler, symbol.cast<SymbolFunction>()))
            return Runtime::CompilerMsgKind::SemFunctions;

        if ((activeMask & compilerMessageBit(Runtime::CompilerMsgKind::SemTypes)) &&
            shouldTrackCompilerMessageType(compiler, symbol))
            return Runtime::CompilerMsgKind::SemTypes;

        if ((activeMask & compilerMessageBit(Runtime::CompilerMsgKind::SemGlobals)) &&
            symbol.isVariable() &&
            shouldTrackCompilerMessageGlobal(compiler, symbol.cast<SymbolVariable>()))
            return Runtime::CompilerMsgKind::SemGlobals;

        return std::nullopt;
    }

    bool tryBuildCompilerMessageBacklogEntry(CompilerMessageBacklogEntry& out, const CompilerInstance& compiler, const Symbol& symbol, const uint64_t activationMask)
    {
        const std::optional<Runtime::CompilerMsgKind> kind = compilerMessageKindForSymbol(compiler, symbol, activationMask);
        if (!kind.has_value())
            return false;

        out.symbol = const_cast<Symbol*>(&symbol);
        out.kind   = *kind;
        out.key    = SymbolSort::locationKey(compiler, symbol);
        return true;
    }

    void collectCompilerMessageBacklogRec(const CompilerInstance& compiler, const SymbolMap& symMap, std::unordered_set<const SymbolMap*>& visited, uint64_t activationMask, std::vector<CompilerMessageBacklogEntry>& out)
    {
        if (!visited.insert(&symMap).second)
            return;

        std::vector<const Symbol*> symbols;
        symMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            if (!symbol)
                continue;

            CompilerMessageBacklogEntry entry;
            if (tryBuildCompilerMessageBacklogEntry(entry, compiler, *symbol, activationMask))
                out.push_back(std::move(entry));

            if (symbol->isSymMap())
                collectCompilerMessageBacklogRec(compiler, *symbol->asSymMap(), visited, activationMask, out);
        }
    }

    void appendCompilerMessageBacklog(const CompilerInstance& compiler, uint64_t activationMask, std::vector<CompilerInstance::CompilerMessageEvent>& out)
    {
        std::unordered_set<const SymbolMap*>     visited;
        std::vector<CompilerMessageBacklogEntry> entries;
        for (const SourceFile* file : compiler.filesSnapshot())
        {
            if (!file)
                continue;

            if (const SymbolNamespace* moduleNamespace = file->moduleNamespace())
                collectCompilerMessageBacklogRec(compiler, *moduleNamespace->asSymMap(), visited, activationMask, entries);

            const SymbolNamespace* fileNamespace = file->fileNamespace();
            if (!fileNamespace)
                continue;

            collectCompilerMessageBacklogRec(compiler, *fileNamespace->asSymMap(), visited, activationMask, entries);
        }

        std::ranges::stable_sort(entries, compilerMessageBacklogEntryLess);

        out.reserve(out.size() + entries.size());
        for (const CompilerMessageBacklogEntry& entry : entries)
            out.push_back({.kind = entry.kind, .symbol = entry.symbol});
    }

    void appendCompilerMessageExecutedPasses(const uint64_t executedMask, const uint64_t listenerMask, std::vector<CompilerInstance::CompilerMessageEvent>& out)
    {
        static constexpr Runtime::CompilerMsgKind KINDS[] = {
            Runtime::CompilerMsgKind::PassAfterSemantic,
            Runtime::CompilerMsgKind::PassBeforeRunByteCode,
            Runtime::CompilerMsgKind::PassBeforeOutput,
            Runtime::CompilerMsgKind::PassAllDone,
            Runtime::CompilerMsgKind::AttributeGen,
        };

        for (const Runtime::CompilerMsgKind kind : KINDS)
        {
            const uint64_t bit = compilerMessageBit(kind);
            if ((executedMask & bit) && (listenerMask & bit))
                out.push_back({.kind = kind, .symbol = nullptr});
        }
    }

    bool trySelectReplayCompilerMessage(CompilerMessageDispatchStep& out, const CompilerInstance::CompilerMessageListener& listener, const size_t listenerIndex)
    {
        if (listener.nextReplayIndex >= listener.replayEvents.size())
            return false;

        out.listenerIndex = listenerIndex;
        out.eventIndex    = listener.nextReplayIndex;
        out.fromReplay    = true;
        out.event         = listener.replayEvents[listener.nextReplayIndex];
        out.function      = listener.function;
        out.nodeRef       = listener.nodeRef;
        return true;
    }

    bool trySelectLoggedCompilerMessage(CompilerMessageDispatchStep& out, CompilerInstance::CompilerMessageListener& listener, const std::vector<CompilerInstance::CompilerMessageEvent>& log, const size_t listenerIndex)
    {
        while (listener.nextEventIndex < log.size())
        {
            const CompilerInstance::CompilerMessageEvent& event = log[listener.nextEventIndex];
            if (!(listener.mask & compilerMessageBit(event.kind)))
            {
                listener.nextEventIndex++;
                continue;
            }

            if (event.symbol)
            {
                const auto it = listener.replayedSymbols.find(event.symbol);
                if (it != listener.replayedSymbols.end())
                {
                    listener.replayedSymbols.erase(it);
                    listener.nextEventIndex++;
                    continue;
                }
            }

            out.listenerIndex = listenerIndex;
            out.eventIndex    = listener.nextEventIndex;
            out.fromReplay    = false;
            out.event         = event;
            out.function      = listener.function;
            out.nodeRef       = listener.nodeRef;
            return true;
        }

        return false;
    }

    bool trySelectCompilerMessageDispatchStep(CompilerMessageDispatchStep& out, std::deque<CompilerInstance::CompilerMessageListener>& listeners, const std::vector<CompilerInstance::CompilerMessageEvent>& log)
    {
        for (size_t i = 0; i < listeners.size(); ++i)
        {
            CompilerInstance::CompilerMessageListener& listener = listeners[i];
            if (trySelectReplayCompilerMessage(out, listener, i))
                return true;
            if (trySelectLoggedCompilerMessage(out, listener, log, i))
                return true;
        }

        return false;
    }

    void finalizeCompilerMessageDispatchStep(CompilerInstance::CompilerMessageListener& listener, const CompilerMessageDispatchStep& dispatch, const size_t logSize)
    {
        if (dispatch.fromReplay)
        {
            if (listener.nextReplayIndex == dispatch.eventIndex)
                listener.nextReplayIndex++;
        }
        else if (listener.nextEventIndex == dispatch.eventIndex)
        {
            listener.nextEventIndex++;
        }

        if (listener.nextReplayIndex >= listener.replayEvents.size() &&
            listener.nextEventIndex >= logSize &&
            !listener.replayedSymbols.empty())
        {
            listener.replayedSymbols.clear();
            listener.replayedSymbols.rehash(0);
        }
    }

    Result enqueueGeneratedSource(TaskContext& ctx, std::string_view generatedCode, const SymbolNamespace* moduleNamespace = nullptr)
    {
        if (generatedCode.empty())
            return Result::Continue;

        CompilerInstance&                             compiler = ctx.compiler();
        CompilerInstance::GeneratedSourceAppendResult appendResult;
        Utf8                                          because;
        if (compiler.appendGeneratedSource(appendResult, because, generatedCode, 0) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(appendResult.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        SourceFile&            sourceFile               = compiler.addLoadedFile(appendResult.path, FileFlagsE::CustomSrc | FileFlagsE::SkipFmt, appendResult.snapshot.view());
        const SymbolNamespace* generatedModuleNamespace = moduleNamespace ? moduleNamespace : currentModuleNamespace(ctx);
        if (generatedModuleNamespace)
            sourceFile.setModuleNamespace(*const_cast<SymbolNamespace*>(generatedModuleNamespace));

        sourceFile.ast().srcView().setLineOffset(appendResult.lineOffset);
        if (parseLoadedSourceFile(ctx, sourceFile, {}) != Result::Continue)
            return Result::Error;

        const SourceView& srcView = sourceFile.ast().srcView();
        if (sourceFile.hasError() || srcView.mustSkip() || !srcView.runsSema())
            return Result::Continue;

        auto* declJob = heapNew<SemaJob>(ctx, sourceFile.nodePayloadContext(), true, true);
        ctx.global().jobMgr().enqueue(*declJob, JobPriority::Normal, compiler.jobClientId());
        compiler.notifyAlive();
        return Result::Continue;
    }
}

const Runtime::CompilerMessage* CompilerInstance::runtimeCompilerGetMessage(const CompilerInstance* owner)
{
    SWC_ASSERT(owner != nullptr);
    return &owner->runtimeCompilerMessage();
}

Runtime::BuildCfg* CompilerInstance::runtimeCompilerGetBuildCfg(CompilerInstance* owner)
{
    SWC_ASSERT(owner != nullptr);
    return &owner->buildCfg();
}

void CompilerInstance::runtimeCompilerCompileString(const CompilerInstance* owner, Runtime::String str)
{
    SWC_ASSERT(owner != nullptr);
    const TaskContext* currentCtx = TaskContext::current();
    if (!currentCtx || !currentCtx->hasCompiler())
        return;

    TaskContext& ctx = *const_cast<TaskContext*>(currentCtx);
    if (&ctx.compiler() != owner)
        return;

    const std::string_view generatedCode(str.ptr, str.length);
    if (deferCompilerMessageGeneratedSource(*owner, generatedCode))
        return;

    (void) enqueueGeneratedSource(ctx, generatedCode);
}

bool CompilerInstance::hasCompilerMessageInterest(const Runtime::CompilerMsgKind kind) const
{
    return (compilerMessageActiveMask_.load(std::memory_order_acquire) & compilerMessageBit(kind)) != 0;
}

bool CompilerInstance::tryGetCompilerMessageTypeInfo(const TypeRef typeRef, const Runtime::TypeInfo*& outType)
{
    outType = nullptr;
    const std::shared_lock lock(compilerMessageTypeInfoMutex_);
    const auto             it = compilerMessageTypeInfoCache_.find(typeRef);
    if (it == compilerMessageTypeInfoCache_.end())
        return false;

    outType = it->second;
    return true;
}

void CompilerInstance::cacheCompilerMessageTypeInfo(const TypeRef typeRef, const Runtime::TypeInfo* runtimeTypeInfo)
{
    const std::unique_lock lock(compilerMessageTypeInfoMutex_);
    compilerMessageTypeInfoCache_[typeRef] = runtimeTypeInfo;
    compilerMessageTypeInfoPrepScheduled_.erase(typeRef);
}

bool CompilerInstance::tryPopCompilerMessageTypeInfoPreparation(CompilerMessageTypeInfoPrepRequest& outRequest)
{
    const std::unique_lock lock(compilerMessageTypeInfoMutex_);
    while (!compilerMessageTypeInfoPrepQueue_.empty())
    {
        outRequest = compilerMessageTypeInfoPrepQueue_.front();
        compilerMessageTypeInfoPrepQueue_.pop_front();

        if (compilerMessageTypeInfoCache_.contains(outRequest.typeRef))
        {
            compilerMessageTypeInfoPrepScheduled_.erase(outRequest.typeRef);
            continue;
        }

        return true;
    }

    return false;
}

void CompilerInstance::markCompilerMessageTypeInfoPreparationFailed()
{
    compilerMessageTypeInfoPrepFailed_.store(true, std::memory_order_release);
    notifyAlive();
}

void CompilerInstance::enqueueCompilerMessageTypeInfoPreparation(TaskContext& ctx, const SymbolFunction* listenerFunction, const AstNodeRef ownerNodeRef, const CompilerMessageEvent& event)
{
    if (compilerMessageTypeInfoPrepFailed_.load(std::memory_order_acquire))
        return;

    const TypeRef typeRef = event.symbol ? event.symbol->typeRef() : TypeRef::invalid();
    if (typeRef.isInvalid())
        return;

    if (!listenerFunction || ownerNodeRef.isInvalid() || sourceViewFile(*listenerFunction) == nullptr)
        return;

    const SourceFile* listenerFile = sourceViewFile(*listenerFunction);
    if (!listenerFile)
        return;

    {
        const std::unique_lock lock(compilerMessageTypeInfoMutex_);
        if (compilerMessageTypeInfoCache_.contains(typeRef))
            return;

        if (!compilerMessageTypeInfoPrepScheduled_.insert(typeRef).second)
            return;

        CompilerMessageTypeInfoPrepRequest request;
        request.listenerFile = const_cast<SourceFile*>(listenerFile);
        request.ownerNodeRef = ownerNodeRef;
        request.typeRef      = typeRef;
        compilerMessageTypeInfoPrepQueue_.push_back(request);
    }

    auto* job = heapNew<CompilerMessageTypeInfoJob>(ctx);
    global().jobMgr().enqueue(*job, JobPriority::Normal, jobClientId());
    notifyAlive();
}

Result CompilerInstance::ensureCompilerMessageTypeInfoPrepared(TaskContext& ctx, const SymbolFunction* listenerFunction, const AstNodeRef ownerNodeRef, const CompilerMessageEvent& event)
{
    if (compilerMessageTypeInfoPrepFailed_.load(std::memory_order_acquire))
        return Result::Error;

    const TypeRef typeRef = event.symbol ? event.symbol->typeRef() : TypeRef::invalid();
    if (typeRef.isInvalid())
        return Result::Continue;

    const Runtime::TypeInfo* runtimeTypeInfo = nullptr;
    if (tryGetCompilerMessageTypeInfo(typeRef, runtimeTypeInfo))
        return Result::Continue;

    if (!listenerFunction || ownerNodeRef.isInvalid() || sourceViewFile(*listenerFunction) == nullptr)
        return Result::Continue;

    enqueueCompilerMessageTypeInfoPreparation(ctx, listenerFunction, ownerNodeRef, event);

    if (tryGetCompilerMessageTypeInfo(typeRef, runtimeTypeInfo))
        return Result::Continue;

    return Result::Pause;
}

Result CompilerInstance::prepareCompilerMessageTypeInfo(Sema& sema, const TypeRef typeRef, const AstNodeRef ownerNodeRef)
{
    const Runtime::TypeInfo* runtimeTypeInfo = nullptr;
    if (tryGetCompilerMessageTypeInfo(typeRef, runtimeTypeInfo))
        return Result::Continue;

    if (typeRef.isInvalid() || ownerNodeRef.isInvalid())
        return Result::Continue;

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, typeRef, ownerNodeRef, ConstantManager::TypeInfoLockMode::TryLock));

    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());
    DataSegmentRef typeInfoRef;
    if (!sema.cstMgr().resolveConstantDataSegmentRef(typeInfoRef, typeInfoCstRef, reinterpret_cast<const void*>(typeInfoCst.getValuePointer())))
        return Result::Error;

    runtimeTypeInfo = sema.cstMgr().shardDataSegment(typeInfoRef.shardIndex).ptr<Runtime::TypeInfo>(typeInfoRef.offset);
    if (!runtimeTypeInfo)
        return Result::Error;

    cacheCompilerMessageTypeInfo(typeRef, runtimeTypeInfo);
    notifyAlive();
    return Result::Continue;
}

Result CompilerInstance::fillRuntimeCompilerMessage(Sema& sema, const AstNodeRef ownerNodeRef, const CompilerMessageEvent& event)
{
    Runtime::CompilerMessage& message = runtimeCompilerMessage();
    std::string_view          moduleName;
    if (const SymbolNamespace* moduleNamespace = firstModuleNamespace(sema.ctx().compiler()))
        moduleName = moduleNamespace->name(sema.ctx());
    else
    {
        const Runtime::BuildCfg& buildCfg = sema.ctx().compiler().buildCfg();
        if (buildCfg.moduleNamespace.ptr && buildCfg.moduleNamespace.length)
            moduleName = {buildCfg.moduleNamespace.ptr, buildCfg.moduleNamespace.length};
    }

    message.moduleName = Runtime::String{.ptr = moduleName.data(), .length = moduleName.size()};
    message.name       = {};
    message.type       = nullptr;
    message.kind       = event.kind;

    if (!event.symbol)
        return Result::Continue;

    const std::string_view symbolName = event.symbol->name(sema.ctx());
    message.name                      = Runtime::String{.ptr = symbolName.data(), .length = symbolName.size()};

    const TypeRef typeRef = event.symbol->typeRef();
    if (typeRef.isInvalid())
        return Result::Continue;

    if (tryGetCompilerMessageTypeInfo(typeRef, message.type))
        return Result::Continue;

    if (ownerNodeRef.isInvalid())
        return Result::Continue;

    if (!tryGetCompilerMessageTypeInfo(typeRef, message.type))
        return Result::Pause;

    return Result::Continue;
}

void CompilerInstance::registerCompilerMessageFunction(SymbolFunction* symbol, const AstNodeRef nodeRef, const uint64_t mask)
{
    if (!symbol || !mask)
        return;

    std::vector<CompilerMessageEvent> replayEventsToPrepare;
    {
        const std::scoped_lock lock(compilerMessageDispatchMutex_);
        for (const CompilerMessageListener& listener : compilerMessageListeners_)
        {
            if (listener.function == symbol && listener.nodeRef == nodeRef)
                return;
        }

        CompilerMessageListener listener;
        listener.function = symbol;
        listener.nodeRef  = nodeRef;
        listener.mask     = mask;

        compilerMessageActiveMask_.fetch_or(mask, std::memory_order_release);

        const uint64_t trackedSemaMask = mask & trackedCompilerMessageSemaMask();
        if (trackedSemaMask)
            appendCompilerMessageBacklog(*this, trackedSemaMask, listener.replayEvents);

        const uint64_t executedMask = compilerMessageExecutedPassMask_.load(std::memory_order_relaxed);
        appendCompilerMessageExecutedPasses(executedMask, mask, listener.replayEvents);

        listener.nextEventIndex = compilerMessageLog_.size();
        if (!listener.replayEvents.empty())
        {
            listener.replayedSymbols.reserve(listener.replayEvents.size());
            for (const CompilerMessageEvent& event : listener.replayEvents)
            {
                if (event.symbol)
                    listener.replayedSymbols.insert(event.symbol);
            }
        }

        replayEventsToPrepare = listener.replayEvents;
        compilerMessageListeners_.push_back(std::move(listener));
    }

    TaskContext ctx(*this);
    for (const CompilerMessageEvent& event : replayEventsToPrepare)
        enqueueCompilerMessageTypeInfoPreparation(ctx, symbol, nodeRef, event);

    notifyAlive();
}

void CompilerInstance::onSymbolSemaCompleted(TaskContext& ctx, Symbol& symbol)
{
    ModuleApi::onSymbolSemaCompleted(perThreadData_[JobManager::threadIndex()].moduleApi, ctx, symbol);

    const uint64_t activeMask = compilerMessageActiveMask_.load(std::memory_order_acquire);
    if (!activeMask)
        return;

    const std::optional<Runtime::CompilerMsgKind> kind = compilerMessageKindForSymbol(*this, symbol, activeMask);
    if (!kind.has_value())
        return;

    const CompilerMessageEvent event{
        .kind   = *kind,
        .symbol = &symbol,
    };

    const SymbolFunction* preparationFunction = nullptr;
    AstNodeRef            preparationNodeRef  = AstNodeRef::invalid();

    {
        const std::scoped_lock lock(compilerMessageDispatchMutex_);
        compilerMessageLog_.push_back(event);

        for (const CompilerMessageListener& listener : compilerMessageListeners_)
        {
            if (!(listener.mask & compilerMessageBit(event.kind)))
                continue;
            if (!listener.function || listener.nodeRef.isInvalid() || sourceViewFile(*listener.function) == nullptr)
                continue;

            preparationFunction = listener.function;
            preparationNodeRef  = listener.nodeRef;
            break;
        }
    }

    if (preparationFunction)
    {
        TaskContext taskContext(*this);
        enqueueCompilerMessageTypeInfoPreparation(taskContext, preparationFunction, preparationNodeRef, event);
    }

    notifyAlive();
}

Result CompilerInstance::ensureCompilerMessagePass(const Runtime::CompilerMsgKind kind)
{
    if (!hasCompilerMessageInterest(kind))
        return Result::Continue;

    const uint64_t passBit = compilerMessageBit(kind);
    if (compilerMessageExecutedPassMask_.load(std::memory_order_acquire) & passBit)
        return Result::Continue;

    {
        const std::scoped_lock lock(compilerMessageDispatchMutex_);
        const uint64_t         executedMask = compilerMessageExecutedPassMask_.load(std::memory_order_relaxed);
        if (executedMask & passBit)
            return Result::Continue;

        compilerMessageLog_.push_back({.kind = kind, .symbol = nullptr});
        compilerMessageExecutedPassMask_.store(executedMask | passBit, std::memory_order_release);
    }

    notifyAlive();
    return Result::Pause;
}

Result CompilerInstance::executePendingCompilerMessages(TaskContext& ctx)
{
    {
        const std::scoped_lock lock(compilerMessageDispatchMutex_);
        if (compilerMessageListeners_.empty())
            return Result::Continue;
    }

    std::vector<DeferredCompilerGeneratedSource> deferredGeneratedSources;
    deferredGeneratedSources.reserve(4);
    CompilerMessageListenerExecutionState listenerState;
    SWC_DEV_LOOP_GUARD(loopGuard, 1000000, "CompilerInstance::executePendingCompilerMessages");
    while (true)
    {
        SWC_DEV_LOOP_TICK(loopGuard);
        CompilerMessageDispatchStep dispatch;
        bool                        found = false;
        {
            const std::scoped_lock lock(compilerMessageDispatchMutex_);
            found = trySelectCompilerMessageDispatchStep(dispatch, compilerMessageListeners_, compilerMessageLog_);
        }

        if (!found)
        {
            if (deferredGeneratedSources.empty())
                return Result::Continue;

            for (const DeferredCompilerGeneratedSource& generatedSource : deferredGeneratedSources)
                SWC_RESULT(enqueueGeneratedSource(ctx, generatedSource.text.view(), generatedSource.moduleNamespace));
            return Result::Pause;
        }

        const SourceFile* listenerFile = nullptr;
        Sema*             sema         = nullptr;
        SWC_RESULT(ensureCompilerMessageListenerSema(listenerState, ctx, dispatch, listenerFile, sema));
        SWC_ASSERT(sema != nullptr);
        SWC_RESULT(ensureCompilerMessageTypeInfoPrepared(ctx, dispatch.function, dispatch.nodeRef, dispatch.event));
        SWC_RESULT(fillRuntimeCompilerMessage(*sema, dispatch.nodeRef, dispatch.event));
        {
            ScopedCompilerMessageDispatchState dispatchScope(*this, listenerFile->moduleNamespace(), deferredGeneratedSources);
            SWC_RESULT(SemaJIT::runStatementImmediate(*sema, *dispatch.function, dispatch.nodeRef));
        }

        const std::scoped_lock lock(compilerMessageDispatchMutex_);
        auto&                  listener = compilerMessageListeners_[dispatch.listenerIndex];
        finalizeCompilerMessageDispatchStep(listener, dispatch, compilerMessageLog_.size());

        if (!deferredGeneratedSources.empty())
        {
            for (const DeferredCompilerGeneratedSource& generatedSource : deferredGeneratedSources)
                SWC_RESULT(enqueueGeneratedSource(ctx, generatedSource.text.view(), generatedSource.moduleNamespace));
            deferredGeneratedSources.clear();
            return Result::Pause;
        }
    }
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/Heap.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

bool CompilerInstance::dbgDevStop = false;

class CompilerMessageTypeInfoJob : public Job
{
public:
    explicit CompilerMessageTypeInfoJob(const TaskContext& ctx) :
        Job(ctx, JobKind::CompilerMessage)
    {
    }

    JobResult exec() override
    {
        while (true)
        {
            if (!hasCurrentRequest_)
            {
                if (!ctx().compiler().tryPopCompilerMessageTypeInfoPreparation(currentRequest_))
                    return JobResult::Done;
                hasCurrentRequest_ = true;
            }

            ctx().state().setNone();
            if (!currentRequest_.listenerFile || currentRequest_.ownerNodeRef.isInvalid() || currentRequest_.typeRef.isInvalid())
            {
                hasCurrentRequest_ = false;
                continue;
            }

            Sema         sema(ctx(), currentRequest_.listenerFile->nodePayloadContext(), false);
            const Result result = ctx().compiler().prepareCompilerMessageTypeInfo(sema, currentRequest_.typeRef, currentRequest_.ownerNodeRef);
            if (result == Result::Pause)
                return JobResult::Sleep;

            hasCurrentRequest_ = false;
            if (result == Result::Error)
            {
                ctx().compiler().markCompilerMessageTypeInfoPreparationFailed();
                return JobResult::Done;
            }
        }
    }

private:
    CompilerInstance::CompilerMessageTypeInfoPrepRequest currentRequest_;
    bool                                                 hasCurrentRequest_ = false;
};

namespace
{
    uint64_t       g_RuntimeContextTlsId;
    std::once_flag g_RuntimeContextTlsIdOnce;

    template<typename T>
    bool appendUnique(std::vector<T*>& values, T* value)
    {
        if (std::ranges::find(values, value) != values.end())
            return false;

        values.push_back(value);
        return true;
    }

    bool shouldRegisterNativeFunction(const SymbolFunction& symbol)
    {
        return !symbol.isIgnored() &&
               !symbol.isForeign() &&
               !symbol.isEmpty() &&
               !symbol.isAttribute() &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Macro) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
    }

    bool isNativeRootFunction(const SymbolFunction& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        if (!owner)
            return false;

        while (owner->ownerSymMap())
            owner = owner->ownerSymMap();

        if (owner->isModule() || owner->isStruct() || owner->isInterface() || owner->isImpl())
            return true;

        return owner->isNamespace() && owner->idRef().isValid();
    }

    const SourceFile* sourceFileFromRef(const CompilerInstance& compiler, const SourceViewRef srcViewRef)
    {
        if (!srcViewRef.isValid())
            return nullptr;

        const SourceView& srcView = compiler.srcView(srcViewRef);
        return srcView.file();
    }

    template<typename T>
    bool isImportedApiSource(const CompilerInstance& compiler, const T& symbol)
    {
        const SourceFile* sourceFile = sourceFileFromRef(compiler, symbol.srcViewRef());
        return sourceFile && sourceFile->isImportedApi();
    }

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

        const SourceFile* listenerFile = sourceFileFromRef(ctx.compiler(), dispatch.function->srcViewRef());
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
            const SourceFile* file = sourceFileFromRef(ctx.compiler(), state.codeRef.srcViewRef);
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
        if (!shouldRegisterNativeFunction(symbol))
            return false;
        if (isImportedApiSource(compiler, symbol))
            return false;
        if (!isModuleLevelSymbol(symbol))
            return false;

        const SourceFile* sourceFile = sourceFileFromRef(compiler, symbol.srcViewRef());
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
        if (isImportedApiSource(compiler, symbol))
            return false;
        if (!isModuleLevelSymbol(symbol))
            return false;

        const SourceFile* sourceFile = sourceFileFromRef(compiler, symbol.srcViewRef());
        return sourceFile && !sourceFile->isRuntime();
    }

    bool shouldTrackCompilerMessageGlobal(const CompilerInstance& compiler, const SymbolVariable& symbol)
    {
        if (!symbol.isSemaCompleted() || symbol.isIgnored())
            return false;
        if (!symbol.hasGlobalStorage() || symbol.globalStorageKind() == DataSegmentKind::Compiler)
            return false;
        if (isImportedApiSource(compiler, symbol))
            return false;
        if (!isModuleLevelSymbol(symbol))
            return false;

        const SourceFile* sourceFile = sourceFileFromRef(compiler, symbol.srcViewRef());
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

        std::ranges::stable_sort(entries, [](const CompilerMessageBacklogEntry& lhs, const CompilerMessageBacklogEntry& rhs) {
            if (lhs.key != rhs.key)
                return lhs.key < rhs.key;
            return static_cast<uint32_t>(lhs.kind) < static_cast<uint32_t>(rhs.kind);
        });

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

        CompilerInstance& compiler  = ctx.compiler();
        const fs::path    directory = !ctx.cmdLine().workDir.empty() ? ctx.cmdLine().workDir : Os::getTemporaryPath().lexically_normal();

        CompilerInstance::GeneratedSourceAppendResult appendResult;
        Utf8                                          because;
        if (compiler.appendGeneratedSource(appendResult, because, directory, generatedCode, 0) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(appendResult.path.empty() ? directory : appendResult.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        compiler.registerInMemoryFile(appendResult.path, appendResult.snapshot.view());
        SourceFile&            sourceFile               = compiler.addFile(appendResult.path, FileFlagsE::CustomSrc | FileFlagsE::SkipFmt);
        const SymbolNamespace* generatedModuleNamespace = moduleNamespace ? moduleNamespace : currentModuleNamespace(ctx);
        if (generatedModuleNamespace)
            sourceFile.setModuleNamespace(*const_cast<SymbolNamespace*>(generatedModuleNamespace));

        if (sourceFile.loadContent(ctx) != Result::Continue)
            return Result::Error;
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

    struct ModuleApiFileInfo
    {
        bool exported           = false;
        bool hasModuleNamespace = false;
    };

    ModuleApiFileInfo analyzeModuleApiFile(const SourceFile& file, std::string_view moduleNamespace)
    {
        ModuleApiFileInfo result;
        const AstNodeRef  rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return result;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return result;

        const auto& fileNode = rootNode.cast<AstFile>();

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, fileNode.spanGlobalsRef);
        for (uint32_t i = 0; i < globalRefs.size(); ++i)
        {
            const AstNodeRef globalRef = globalRefs[i];
            if (globalRef.isInvalid())
                continue;

            const AstNode& globalNode = file.ast().node(globalRef);
            if (globalNode.isNot(AstNodeId::CompilerGlobal))
                continue;

            const auto& global = globalNode.cast<AstCompilerGlobal>();
            if (i == 0 && global.mode == AstCompilerGlobal::Mode::Export)
                result.exported = true;

            if (global.mode != AstCompilerGlobal::Mode::Namespace)
                continue;

            SmallVector<TokenRef> nameRefs;
            file.ast().appendTokens(nameRefs, global.spanNameRef);
            if (nameRefs.size() != 1)
                continue;

            const std::string_view namespaceName = file.ast().srcView().tokenString(nameRefs[0]);
            if (namespaceName == moduleNamespace)
                result.hasModuleNamespace = true;
        }

        return result;
    }

    std::string_view preferredLineEnding(const SourceFile& file)
    {
        const std::string_view content = file.sourceView();
        if (content.find("\r\n") != std::string_view::npos)
            return "\r\n";
        if (content.find('\n') != std::string_view::npos)
            return "\n";
        return "\r\n";
    }

    Utf8 buildExportedModuleApiContent(const SourceFile& file, std::string_view moduleNamespace, const bool hasModuleNamespace)
    {
        const std::string_view source = file.sourceView();
        if (hasModuleNamespace)
            return Utf8{source};

        uint32_t insertOffset = file.ast().srcView().sourceStartOffset();
        if (file.ast().srcView().numTokens())
        {
            const Token& firstToken = file.ast().srcView().token(TokenRef(0));
            if (firstToken.id != TokenId::EndOfFile)
                insertOffset = firstToken.byteStart;
        }

        insertOffset = std::min<uint32_t>(insertOffset, static_cast<uint32_t>(source.size()));

        Utf8 content;
        content.reserve(source.size() + moduleNamespace.size() + 32);
        content.append(source.substr(0, insertOffset));
        content += "#global namespace ";
        content += moduleNamespace;
        content += preferredLineEnding(file);
        content.append(source.substr(insertOffset));
        return content;
    }

    Result ensureModuleApiDirectory(TaskContext& ctx, const fs::path& path)
    {
        if (path.empty())
            return Result::Continue;

        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_dir_create_failed);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        return Result::Continue;
    }

    void initRuntimeContextTlsId()
    {
        g_RuntimeContextTlsId = Os::tlsAlloc();
    }

    uint64_t runtimeContextTlsId()
    {
        std::call_once(g_RuntimeContextTlsIdOnce, initRuntimeContextTlsId);
        return g_RuntimeContextTlsId;
    }

    void collectSwagFilesRec(const CommandLine& cmdLine, const fs::path& folder, std::vector<fs::path>& files, bool canFilter = true)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                ec.clear();
                continue;
            }

            const fs::directory_entry& entry = *it;
            if (!entry.is_regular_file(ec))
            {
                ec.clear();
                continue;
            }

            const fs::path&   path = entry.path();
            const std::string ext  = path.extension().string();
            if (ext != ".swg" && ext != ".swgs")
                continue;

            if (canFilter && !cmdLine.fileFilter.empty())
            {
                const std::string pathString = path.string();
                bool              ignore     = false;
                for (const Utf8& filter : cmdLine.fileFilter)
                {
                    if (!pathString.contains(filter))
                    {
                        ignore = true;
                        break;
                    }
                }

                if (ignore)
                    continue;
            }

            files.push_back(path);
        }
    }

    const Runtime::CompilerMessage* runtimeCompilerGetMessage(const CompilerInstance* owner)
    {
        SWC_ASSERT(owner != nullptr);
        return &owner->runtimeCompilerMessage();
    }

    Runtime::BuildCfg* runtimeCompilerGetBuildCfg(CompilerInstance* owner)
    {
        SWC_ASSERT(owner != nullptr);
        return &owner->buildCfg();
    }

    void runtimeCompilerCompileString(const CompilerInstance* owner, Runtime::String str)
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
}

CompilerInstance::CompilerInstance(const Global& global, const CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global),
    buildCfg_(cmdLine.defaultBuildCfg)
{
    (void) runtimeContextTlsId();

    jobClientId_ = global.jobMgr().newClientId();
    exeFullName_ = Os::getExeFullName();

    const uint32_t numWorkers     = global.jobMgr().numWorkers();
    const uint32_t perThreadSlots = global.jobMgr().isSingleThreaded() ? 1 : numWorkers + 1;
    perThreadData_.resize(perThreadSlots);
    jitMemMgr_         = std::make_unique<JITMemoryManager>();
    jitExecMgr_        = std::make_unique<JITExecManager>();
    externalModuleMgr_ = std::make_unique<ExternalModuleManager>();
    setupRuntimeCompiler();
}

CompilerInstance::~CompilerInstance()
{
    // SymbolFunction instances are arena-allocated, so their JITMemory destructors do not reliably
    // run during compiler teardown. Unregister prepared function tables before executable pages are
    // released or stale Windows unwind entries can survive into the next compiler instance.
    resetPreparedJitFunctions();
}

std::byte* CompilerInstance::dataSegmentAddress(const DataSegmentKind kind, const uint32_t offset)
{
    switch (kind)
    {
        case DataSegmentKind::GlobalZero:
            return globalZeroSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::GlobalInit:
            return globalInitSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Compiler:
            return compilerSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Zero:
            return constantSegment_.ptr<std::byte>(offset);
    }

    SWC_UNREACHABLE();
}

const std::byte* CompilerInstance::dataSegmentAddress(const DataSegmentKind kind, const uint32_t offset) const
{
    switch (kind)
    {
        case DataSegmentKind::GlobalZero:
            return globalZeroSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::GlobalInit:
            return globalInitSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Compiler:
            return compilerSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Zero:
            return constantSegment_.ptr<std::byte>(offset);
    }

    SWC_UNREACHABLE();
}

Result CompilerInstance::setupSema(TaskContext& ctx)
{
    typeMgr_ = std::make_unique<TypeManager>();
    typeGen_ = std::make_unique<TypeGen>();
    cstMgr_  = std::make_unique<ConstantManager>();
    idMgr_   = std::make_unique<IdentifierManager>();

    idMgr_->setup(ctx);
    typeMgr_->setup(ctx);
    cstMgr_->setup(ctx);
    SWC_RESULT(compilerTags_.setup(ctx));
    return Result::Continue;
}

uint32_t CompilerInstance::pendingImplRegistrations() const
{
    return pendingImplRegistrations_.load(std::memory_order_relaxed);
}

void CompilerInstance::incPendingImplRegistrations()
{
    pendingImplRegistrations_.fetch_add(1, std::memory_order_relaxed);
    notifyAlive();
}

void CompilerInstance::decPendingImplRegistrations()
{
    const uint32_t prev = pendingImplRegistrations_.fetch_sub(1, std::memory_order_relaxed);
    SWC_ASSERT(prev > 0);
    notifyAlive();
}

void CompilerInstance::logBefore()
{
    const TaskContext ctx(*this);
    ctx.global().logger().resetStageClaims();
    TimedActionLog::printSessionFlags(ctx);
}

void CompilerInstance::logAfter()
{
    const TaskContext ctx(*this);
    TimedActionLog::printSummary(ctx);
}

void CompilerInstance::logStats()
{
    if (!cmdLine().stats && !cmdLine().statsMem)
        return;

    const TaskContext ctx(*this);
    Stats::get().print(ctx);
}

void CompilerInstance::processCommand()
{
    const Timer time(&Stats::get().timeTotal);
    clearLastArtifactLabel();

    if (cmdLine().dryRun || cmdLine().showConfig)
    {
        if (cmdLine().dryRun)
            Command::dryRun(*this);
        if (cmdLine().showConfig)
            Command::showConfig(*this);
        return;
    }

    switch (cmdLine().command)
    {
        case CommandKind::Format:
            Command::format(*this);
            break;
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Sema:
            Command::sema(*this);
            break;
        case CommandKind::Test:
            Command::test(*this);
            break;
        case CommandKind::Build:
            Command::build(*this);
            break;
        case CommandKind::Run:
            Command::run(*this);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void CompilerInstance::setupRuntimeCompiler()
{
    runtimeCompiler_.obj      = this;
    runtimeCompiler_.itable   = runtimeCompilerITable_;
    runtimeCompilerITable_[0] = nullptr;
    runtimeCompilerITable_[1] = reinterpret_cast<void*>(&runtimeCompilerGetMessage);
    runtimeCompilerITable_[2] = reinterpret_cast<void*>(&runtimeCompilerGetBuildCfg);
    runtimeCompilerITable_[3] = reinterpret_cast<void*>(&runtimeCompilerCompileString);
}

uint64_t* CompilerInstance::runtimeContextTlsIdStorage()
{
    (void) runtimeContextTlsId();
    return &g_RuntimeContextTlsId;
}

Runtime::Context* CompilerInstance::runtimeContextFromTls()
{
    return static_cast<Runtime::Context*>(Os::tlsGetValue(runtimeContextTlsId()));
}

void CompilerInstance::setRuntimeContextForCurrentThread(Runtime::Context* context)
{
    Os::tlsSetValue(runtimeContextTlsId(), context);
}

uint32_t CompilerInstance::nativeRuntimeContextTlsIdOffset()
{
    std::call_once(nativeRuntimeContextTlsIdOffsetOnce_, [this] {
        const auto [offset, storage]     = globalZeroSegment_.reserve<uint64_t>();
        nativeRuntimeContextTlsIdOffset_ = offset;
        *storage                         = runtimeContextTlsId() + 1;
    });

    SWC_ASSERT(nativeRuntimeContextTlsIdOffset_ != UINT32_MAX);
    return nativeRuntimeContextTlsIdOffset_;
}

void CompilerInstance::initPerThreadRuntimeContextForJit()
{
    PerThreadData& td              = perThreadData_[JobManager::threadIndex()];
    td.runtimeContext.runtimeFlags = Runtime::RuntimeFlags::FromCompiler;
    setRuntimeContextForCurrentThread(&td.runtimeContext);

    if (nativeRuntimeContextTlsIdOffset_ != UINT32_MAX)
    {
        uint64_t* const tlsStorage = globalZeroSegment_.ptr<uint64_t>(nativeRuntimeContextTlsIdOffset_);
        SWC_ASSERT(tlsStorage != nullptr);
        *tlsStorage = runtimeContextTlsId() + 1;
    }
}

void CompilerInstance::registerNativeCodeFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (isImportedApiSource(*this, *symbol))
        return;
    if (!isNativeRootFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeCodeSegment_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeTestFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (isImportedApiSource(*this, *symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeTestFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeInitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (isImportedApiSource(*this, *symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeInitFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativePreMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (isImportedApiSource(*this, *symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativePreMainFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeDropFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (isImportedApiSource(*this, *symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeDropFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (isImportedApiSource(*this, *symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeMainFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeGlobalVariable(SymbolVariable* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (isImportedApiSource(*this, *symbol))
        return;
    if (!symbol->hasGlobalStorage())
        return;
    if (symbol->globalStorageKind() == DataSegmentKind::Compiler)
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeGlobalVariables_, symbol);
    }

    if (inserted)
    {
        if (symbol->globalStorageKind() == DataSegmentKind::GlobalInit &&
            symbol->globalFunctionInit() != nullptr)
            invalidateGlobalFunctionBindings();
        notifyAlive();
    }
}

void CompilerInstance::registerNativeGlobalFunctionInitTarget(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    if (isImportedApiSource(*this, *symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeGlobalFunctionInitTargets_, symbol);
    }

    if (inserted)
    {
        nativeGlobalFunctionInitTargetsVersion_.fetch_add(1, std::memory_order_release);
        invalidateGlobalFunctionBindings();
        notifyAlive();
    }
}

void CompilerInstance::registerPreparedJitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);

    const std::unique_lock lock(mutex_);
    if (appendUnique(jitPreparedFunctions_, symbol))
        invalidateGlobalFunctionBindings();
}

void CompilerInstance::invalidateGlobalFunctionBindings()
{
    globalFunctionBindingsVersion_.fetch_add(1, std::memory_order_release);
}

Result CompilerInstance::ensurePatchedGlobalFunctionBindings(TaskContext& ctx)
{
    const uint64_t wantedVersion = globalFunctionBindingsVersion_.load(std::memory_order_acquire);
    if (patchedGlobalFunctionBindingsVersion_.load(std::memory_order_acquire) == wantedVersion)
        return Result::Continue;

    const std::scoped_lock patchLock(globalFunctionBindingsMutex_);
    const uint64_t         lockedVersion = globalFunctionBindingsVersion_.load(std::memory_order_acquire);
    if (patchedGlobalFunctionBindingsVersion_.load(std::memory_order_relaxed) == lockedVersion)
        return Result::Continue;

    SWC_RESULT(JIT::patchGlobalFunctionVariables(ctx));
    if (globalFunctionBindingsVersion_.load(std::memory_order_acquire) == lockedVersion)
        patchedGlobalFunctionBindingsVersion_.store(lockedVersion, std::memory_order_release);

    return Result::Continue;
}

void CompilerInstance::resetPreparedJitFunctions()
{
    std::vector<SymbolFunction*> preparedFunctions;
    {
        const std::unique_lock lock(mutex_);
        preparedFunctions.swap(jitPreparedFunctions_);
    }

    for (SymbolFunction* function : preparedFunctions)
    {
        if (function)
            function->resetJitState();
    }
}

std::vector<SymbolFunction*> CompilerInstance::nativeGlobalFunctionInitTargetsSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return nativeGlobalFunctionInitTargets_;
}

std::vector<SymbolVariable*> CompilerInstance::nativeGlobalVariablesSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return nativeGlobalVariables_;
}

std::vector<SymbolFunction*> CompilerInstance::jitPreparedFunctionsSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return jitPreparedFunctions_;
}

ExitCode CompilerInstance::run()
{
    Stats::resetCommandMetrics();
    logBefore();
    processCommand();
    logAfter();
    logStats();
    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

SourceView& CompilerInstance::addSourceView()
{
    const std::unique_lock lock(mutex_);
    auto                   srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, nullptr));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addSourceView(FileRef fileRef)
{
    SWC_ASSERT(fileRef.isValid());

    const std::unique_lock lock(mutex_);
    SWC_RACE_CONDITION_READ(rcFiles_);
    SWC_ASSERT(fileRef.get() < files_.size());
    auto              srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    SourceFile* const ownerFile  = files_[fileRef.get()].get();
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, ownerFile));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::srcView(SourceViewRef ref)
{
    const std::shared_lock lock(mutex_);
    SWC_ASSERT(ref.get() < srcViews_.size());

    SourceView* const view = srcViews_[ref.get()].get();
    return *(view);
}

const SourceView& CompilerInstance::srcView(SourceViewRef ref) const
{
    const std::shared_lock lock(mutex_);
    SWC_ASSERT(ref.get() < srcViews_.size());

    const SourceView* const view = srcViews_[ref.get()].get();
    return *(view);
}

const SourceView* CompilerInstance::findSourceViewByFileName(const std::string_view fileName) const
{
    if (fileName.empty())
        return nullptr;

    const fs::path wantedPath{std::string(fileName)};
    const Utf8     wantedPathNormalized = Utf8Helper::normalizePathForCompare(wantedPath);

    const std::shared_lock lock(mutex_);
    for (const std::unique_ptr<SourceView>& srcViewPtr : srcViews_)
    {
        const SourceView* const srcView = srcViewPtr.get();
        if (!srcView)
            continue;

        const SourceFile* sourceFile = srcView->file();
        if (!sourceFile)
            continue;

        if (Utf8Helper::normalizePathForCompare(sourceFile->path()) == wantedPathNormalized)
            return srcView;
    }

    return nullptr;
}

bool CompilerInstance::setMainFunc(AstCompilerFunc* node)
{
    const std::unique_lock lock(mutex_);
    if (mainFunc_)
        return false;
    mainFunc_ = node;
    return true;
}

bool CompilerInstance::markNativeOutputsCleared()
{
    return !nativeOutputsCleared_.exchange(true, std::memory_order_acq_rel);
}

bool CompilerInstance::registerForeignLib(std::string_view name)
{
    const std::unique_lock lock(mutex_);
    for (const Utf8& lib : foreignLibs_)
    {
        if (lib == name)
            return false;
    }

    foreignLibs_.emplace_back(name);
    return true;
}

const CompilerTag* CompilerInstance::findCompilerTag(const std::string_view name) const
{
    return compilerTags_.find(name);
}

void CompilerInstance::registerRuntimeFunctionSymbol(const IdentifierRef idRef, SymbolFunction* symbol)
{
    SWC_ASSERT(idRef.isValid());
    SWC_ASSERT(symbol != nullptr);

    bool                   inserted = false;
    const std::unique_lock lock(mutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
    {
        runtimeFunctionSymbols_.emplace(idRef, symbol);
        inserted = true;
    }
    else if (it->second == nullptr)
    {
        it->second = symbol;
        inserted   = true;
    }

    if (inserted)
        notifyAlive();
}

SymbolFunction* CompilerInstance::runtimeFunctionSymbol(const IdentifierRef idRef) const
{
    const std::shared_lock lock(mutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
        return nullptr;
    return it->second;
}

bool CompilerInstance::hasCompilerMessageInterest(const Runtime::CompilerMsgKind kind) const
{
    return (compilerMessageActiveMask_.load(std::memory_order_acquire) & compilerMessageBit(kind)) != 0;
}

bool CompilerInstance::tryGetCompilerMessageTypeInfo(const TypeRef typeRef, const Runtime::TypeInfo*& outType)
{
    outType = nullptr;
    const std::scoped_lock lock(compilerMessageMutex_);
    const auto             it = compilerMessageTypeInfoCache_.find(typeRef);
    if (it == compilerMessageTypeInfoCache_.end())
        return false;

    outType = it->second;
    return true;
}

void CompilerInstance::cacheCompilerMessageTypeInfo(const TypeRef typeRef, const Runtime::TypeInfo* const runtimeTypeInfo)
{
    const std::scoped_lock lock(compilerMessageMutex_);
    compilerMessageTypeInfoCache_[typeRef] = runtimeTypeInfo;
    compilerMessageTypeInfoPrepScheduled_.erase(typeRef);
}

bool CompilerInstance::tryPopCompilerMessageTypeInfoPreparation(CompilerMessageTypeInfoPrepRequest& outRequest)
{
    const std::scoped_lock lock(compilerMessageMutex_);
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

    compilerMessageTypeInfoPrepJobQueued_ = false;
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

    if (!listenerFunction || ownerNodeRef.isInvalid() || sourceFileFromRef(*this, listenerFunction->srcViewRef()) == nullptr)
        return;

    const SourceFile* listenerFile = sourceFileFromRef(*this, listenerFunction->srcViewRef());
    if (!listenerFile)
        return;

    bool enqueueJob = false;
    {
        const std::scoped_lock lock(compilerMessageMutex_);
        if (compilerMessageTypeInfoCache_.contains(typeRef))
            return;

        if (!compilerMessageTypeInfoPrepScheduled_.insert(typeRef).second)
            return;

        CompilerMessageTypeInfoPrepRequest request;
        request.listenerFile = const_cast<SourceFile*>(listenerFile);
        request.ownerNodeRef = ownerNodeRef;
        request.typeRef      = typeRef;
        compilerMessageTypeInfoPrepQueue_.push_back(request);

        enqueueJob                            = !compilerMessageTypeInfoPrepJobQueued_;
        compilerMessageTypeInfoPrepJobQueued_ = true;
    }

    if (enqueueJob)
    {
        auto* job = heapNew<CompilerMessageTypeInfoJob>(ctx);
        global().jobMgr().enqueue(*job, JobPriority::Normal, jobClientId());
    }
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

    if (!listenerFunction || ownerNodeRef.isInvalid() || sourceFileFromRef(*this, listenerFunction->srcViewRef()) == nullptr)
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
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, typeRef, ownerNodeRef));

    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());
    DataSegmentRef typeInfoRef;
    if (!sema.cstMgr().resolveConstantDataSegmentRef(typeInfoRef, typeInfoCstRef, reinterpret_cast<const void*>(typeInfoCst.getValuePointer())))
        return Result::Error;

    runtimeTypeInfo = sema.cstMgr().shardDataSegment(typeInfoRef.shardIndex).ptr<Runtime::TypeInfo>(typeInfoRef.offset);
    if (!runtimeTypeInfo)
        return Result::Error;

    cacheCompilerMessageTypeInfo(typeRef, runtimeTypeInfo);
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
        const std::scoped_lock lock(compilerMessageMutex_);
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

void CompilerInstance::onSymbolSemaCompleted(Symbol& symbol)
{
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
        const std::scoped_lock lock(compilerMessageMutex_);
        compilerMessageLog_.push_back(event);

        for (const CompilerMessageListener& listener : compilerMessageListeners_)
        {
            if (!(listener.mask & compilerMessageBit(event.kind)))
                continue;
            if (!listener.function || listener.nodeRef.isInvalid() || sourceFileFromRef(*this, listener.function->srcViewRef()) == nullptr)
                continue;

            preparationFunction = listener.function;
            preparationNodeRef  = listener.nodeRef;
            break;
        }
    }

    if (preparationFunction)
    {
        TaskContext ctx(*this);
        enqueueCompilerMessageTypeInfoPreparation(ctx, preparationFunction, preparationNodeRef, event);
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
        const std::scoped_lock lock(compilerMessageMutex_);
        const uint64_t         executedMask = compilerMessageExecutedPassMask_.load(std::memory_order_relaxed);
        if (executedMask & passBit)
            return Result::Continue;

        compilerMessageLog_.push_back({
            .kind   = kind,
            .symbol = nullptr,
        });

        compilerMessageExecutedPassMask_.store(executedMask | passBit, std::memory_order_release);
    }

    notifyAlive();
    return Result::Pause;
}

Result CompilerInstance::executePendingCompilerMessages(TaskContext& ctx)
{
    {
        const std::scoped_lock lock(compilerMessageMutex_);
        if (compilerMessageListeners_.empty())
            return Result::Continue;
    }

    std::vector<DeferredCompilerGeneratedSource> deferredGeneratedSources;
    deferredGeneratedSources.reserve(4);
    CompilerMessageListenerExecutionState listenerState;
    while (true)
    {
        CompilerMessageDispatchStep dispatch;
        bool                        found = false;
        {
            const std::scoped_lock lock(compilerMessageMutex_);
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

        const std::scoped_lock lock(compilerMessageMutex_);
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

bool CompilerInstance::tryRegisterReportedDiagnostic(const std::string_view message)
{
    const std::scoped_lock lock(reportedDiagnosticsMutex_);
    Utf8                   messageUtf8(message);
    return reportedDiagnostics_.insert(std::move(messageUtf8)).second;
}

Result CompilerInstance::appendGeneratedSource(GeneratedSourceAppendResult& outResult, Utf8& outBecause, const fs::path& directory, const std::string_view sectionText, const uint32_t codeOffsetInSection)
{
    outResult = {};
    outBecause.clear();

    SWC_ASSERT(directory.is_absolute());
    SWC_ASSERT(codeOffsetInSection <= sectionText.size());

    const auto threadIndex = static_cast<uint32_t>(JobManager::threadIndex());
    const auto sourceId    = generatedSourceId_.fetch_add(1, std::memory_order_relaxed);

    // Keep generated source paths stable across identical compiler runs so debug/source
    // metadata and any path-derived constants remain deterministic.
    outResult.path            = (directory / std::format("thread-{}-g{}-c{}.swg", threadIndex, sourceId, jobClientId_)).lexically_normal();
    outResult.codeStartOffset = codeOffsetInSection;
    outResult.snapshot        = sectionText;

    std::error_code ec;
    fs::create_directories(directory, ec);
    if (ec)
    {
        outBecause = FileSystem::normalizeSystemMessage(ec);
        return Result::Error;
    }

    std::ofstream generatedStream(outResult.path, std::ios::binary | std::ios::trunc);
    if (!generatedStream.is_open())
    {
        outBecause = Os::systemError();
        if (outBecause.empty())
            outBecause = FileSystem::describeIoProblem(FileSystem::IoProblem::OpenWrite);
        else
            outBecause = FileSystem::normalizeSystemMessage(outBecause);
        return Result::Error;
    }

    if (!sectionText.empty())
        generatedStream.write(sectionText.data(), static_cast<std::streamsize>(sectionText.size()));

    if (!generatedStream)
    {
        outBecause = Os::systemError();
        if (outBecause.empty())
            outBecause = FileSystem::describeIoProblem(FileSystem::IoProblem::Write);
        else
            outBecause = FileSystem::normalizeSystemMessage(outBecause);
        return Result::Error;
    }
    generatedStream.close();
    if (!generatedStream)
    {
        outBecause = Os::systemError();
        if (outBecause.empty())
            outBecause = FileSystem::describeIoProblem(FileSystem::IoProblem::CloseWrite);
        else
            outBecause = FileSystem::normalizeSystemMessage(outBecause);
        return Result::Error;
    }

    return Result::Continue;
}

void CompilerInstance::registerInMemoryFile(fs::path path, const std::string_view content)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    path = path.lexically_normal();

    const std::unique_lock lock(mutex_);
    inMemoryFiles_[Utf8Helper::normalizePathForCompare(path)] = Utf8(content);
}

SourceFile& CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedFile(path.lexically_normal(), flags);
}

SourceFile& CompilerInstance::file(const FileRef ref) const
{
    const std::shared_lock lock(mutex_);
    SWC_RACE_CONDITION_READ(rcFiles_);
    SWC_ASSERT(ref.isValid());
    SWC_ASSERT(ref.get() < files_.size());

    SourceFile* const file = files_[ref.get()].get();
    SWC_ASSERT(file != nullptr);
    return *file;
}

std::vector<SourceFile*> CompilerInstance::filesSnapshot() const
{
    const std::shared_lock lock(mutex_);
    SWC_RACE_CONDITION_READ(rcFiles_);
    return filePtrs_;
}

SourceFile& CompilerInstance::addResolvedFile(fs::path path, FileFlags flags)
{
    const std::unique_lock lock(mutex_);
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());
    path = path.lexically_normal();

    auto fileRef = static_cast<FileRef>(static_cast<uint32_t>(files_.size()));
    files_.emplace_back(std::make_unique<SourceFile>(fileRef, std::move(path), flags));
    filePtrs_.push_back(files_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    fileRef.dbgPtr = files_.back().get();
#endif

    const Utf8 key = Utf8Helper::normalizePathForCompare(files_.back()->path());
    const auto it  = inMemoryFiles_.find(key);
    if (it != inMemoryFiles_.end())
        files_.back()->setContent(it->second.view());

    return *files_.back();
}

std::span<SourceFile* const> CompilerInstance::files() const
{
    SWC_RACE_CONDITION_READ(rcFiles_);
    return filePtrs_;
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    filePtrs_.reserve(filePtrs_.size() + paths.size());
    for (fs::path& path : paths)
        addResolvedFile(std::move(path), flags);
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

Result CompilerInstance::collectImportedApiFiles(const TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    for (const fs::path& folder : cmdLine.importApiDirs)
        collectFolderFiles(folder, FileFlagsE::ImportedApi, false);

    if (cmdLine.importApiFiles.empty())
        return Result::Continue;

    files_.reserve(files_.size() + cmdLine.importApiFiles.size());
    filePtrs_.reserve(filePtrs_.size() + cmdLine.importApiFiles.size());
    for (const fs::path& file : cmdLine.importApiFiles)
        addResolvedFile(file, FileFlagsE::ImportedApi);

    return Result::Continue;
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
        collectFolderFiles(folder, FileFlagsE::CustomSrc, true);

    // Collect direct files from the command line
    if (!cmdLine.files.empty())
    {
        files_.reserve(files_.size() + cmdLine.files.size());
        filePtrs_.reserve(filePtrs_.size() + cmdLine.files.size());
        for (const fs::path& file : cmdLine.files)
            addResolvedFile(file, FileFlagsE::CustomSrc);
    }

    // Collect files for the module
    if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        addResolvedFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        SWC_RESULT(FileSystem::resolveFolder(ctx, modulePathSrc_));
        collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
    }

    SWC_RESULT(collectImportedApiFiles(ctx));

    // Collect runtime files
    if (cmdLine.runtime)
    {
        fs::path runtimePath = exeFullName_.parent_path() / "Runtime";
        SWC_RESULT(FileSystem::resolveFolder(ctx, runtimePath));
        collectFolderFiles(runtimePath, FileFlagsE::Runtime, false);
    }

    srcViews_.reserve(files_.size());

    if (files_.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

Result CompilerInstance::exportModuleApi(TaskContext& ctx)
{
    const fs::path& exportApiDir = cmdLine().exportApiDir;
    if (exportApiDir.empty() || modulePathSrc_.empty())
        return Result::Continue;

    SWC_RESULT(ensureModuleApiDirectory(ctx, exportApiDir));
    SWC_RESULT(FileSystem::clearDirectoryContents(ctx, exportApiDir, DiagnosticId::cmd_err_api_dir_clear_failed));

    const Utf8 moduleNamespace = buildCfg().moduleNamespace.ptr ? Utf8(buildCfg().moduleNamespace) : Utf8{};
    for (const SourceFile* file : files())
    {
        if (!file || !file->hasFlag(FileFlagsE::ModuleSrc))
            continue;

        const ModuleApiFileInfo info = analyzeModuleApiFile(*file, moduleNamespace.view());
        if (!info.exported)
            continue;

        fs::path relativePath = file->path().lexically_relative(modulePathSrc_);
        if (relativePath.empty() || relativePath == "." || !FileSystem::pathStartsWith(file->path(), modulePathSrc_))
            relativePath = file->path().filename();

        const fs::path dstPath = exportApiDir / relativePath;
        SWC_RESULT(ensureModuleApiDirectory(ctx, dstPath.parent_path()));

        const Utf8              content = buildExportedModuleApiContent(*file, moduleNamespace.view(), info.hasModuleNamespace);
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(dstPath, content.data(), content.size(), ioError) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_file_write_failed);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, dstPath, FileSystem::describeIoFailure(ioError));
            diag.report(ctx);
            return Result::Error;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();

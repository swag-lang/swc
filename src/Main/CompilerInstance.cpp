#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Native/SymbolSort.h"
#include "Backend/RuntimeName.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
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
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerMessageTypeInfoJob.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/AppendOnlyLookupTable.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/mimalloc/include/mimalloc.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

bool CompilerInstance::dbgDevStop = false;

namespace
{
    uint64_t       g_RuntimeContextTlsId;
    std::once_flag g_RuntimeContextTlsIdOnce;

    fs::path generatedSourceOutputDirectory(const CompilerInstance& compiler);
    fs::path generatedSourceDumpPath(const CompilerInstance& compiler, uint32_t threadIndex);
    Utf8     buildModuleNamespaceName(const CompilerInstance& compiler);

    void reapplyBuildCfgPresetOverrides(Runtime::BuildCfg& buildCfg, const Runtime::BuildCfg& explicitBuildCfg)
    {
        buildCfg.safetyGuards               = explicitBuildCfg.safetyGuards;
        buildCfg.sanity                     = explicitBuildCfg.sanity;
        buildCfg.debugAllocator             = explicitBuildCfg.debugAllocator;
        buildCfg.errorStackTrace            = explicitBuildCfg.errorStackTrace;
        buildCfg.backend.optimize           = explicitBuildCfg.backend.optimize;
        buildCfg.backend.debugInfo          = explicitBuildCfg.backend.debugInfo;
        buildCfg.backend.fpMathFma          = explicitBuildCfg.backend.fpMathFma;
        buildCfg.backend.fpMathNoNaN        = explicitBuildCfg.backend.fpMathNoNaN;
        buildCfg.backend.fpMathNoInf        = explicitBuildCfg.backend.fpMathNoInf;
        buildCfg.backend.fpMathNoSignedZero = explicitBuildCfg.backend.fpMathNoSignedZero;
    }

    void reapplyExplicitBuildCfgOverrides(Runtime::BuildCfg& buildCfg, const CommandLine& cmdLine)
    {
        if (cmdLine.buildCfgExplicit)
            reapplyBuildCfgPresetOverrides(buildCfg, cmdLine.defaultBuildCfg);

        buildCfg.backendKind = effectiveBackendKind(cmdLine, buildCfg.backendKind);
        if (cmdLine.backendOptimize.has_value())
            buildCfg.backend.optimize = cmdLine.backendOptimize.value();

        if (cmdLine.artifactNameExplicit)
            buildCfg.name = cmdLine.defaultBuildCfg.name;
        if (cmdLine.moduleNamespaceExplicit)
            buildCfg.moduleNamespace = cmdLine.defaultBuildCfg.moduleNamespace;
        if (cmdLine.outDirExplicit)
            buildCfg.outDir = cmdLine.defaultBuildCfg.outDir;
        if (cmdLine.workDirExplicit)
            buildCfg.workDir = cmdLine.defaultBuildCfg.workDir;
    }

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
               !symbol.hasUnmaterializedGenericBody() &&
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

    Utf8 buildCfgString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};

        return Utf8{value};
    }

    void ownBuildCfgStrings(Runtime::BuildCfg& buildCfg, std::vector<std::unique_ptr<Utf8>>& ownedStrings)
    {
        std::vector<std::unique_ptr<Utf8>> newOwnedStrings;

        auto copyString = [&](Runtime::String& value) {
            if (!value.ptr || !value.length)
            {
                value = {};
                return;
            }

            auto owned   = std::make_unique<Utf8>(value);
            value.ptr    = owned->data();
            value.length = owned->size();
            newOwnedStrings.push_back(std::move(owned));
        };

        copyString(buildCfg.moduleNamespace);
        copyString(buildCfg.warnAsErrors);
        copyString(buildCfg.warnAsWarning);
        copyString(buildCfg.warnAsDisabled);
        copyString(buildCfg.linkerArgs);
        copyString(buildCfg.name);
        copyString(buildCfg.outDir);
        copyString(buildCfg.workDir);
        copyString(buildCfg.repoPath);
        copyString(buildCfg.resAppIcoFileName);
        copyString(buildCfg.resAppName);
        copyString(buildCfg.resAppDescription);
        copyString(buildCfg.resAppCompany);
        copyString(buildCfg.resAppCopyright);
        copyString(buildCfg.genDoc.outputName);
        copyString(buildCfg.genDoc.outputExtension);
        copyString(buildCfg.genDoc.titleToc);
        copyString(buildCfg.genDoc.titleContent);
        copyString(buildCfg.genDoc.css);
        copyString(buildCfg.genDoc.icon);
        copyString(buildCfg.genDoc.startHead);
        copyString(buildCfg.genDoc.endHead);
        copyString(buildCfg.genDoc.startBody);
        copyString(buildCfg.genDoc.endBody);
        copyString(buildCfg.genDoc.morePages);
        copyString(buildCfg.genDoc.quoteIconNote);
        copyString(buildCfg.genDoc.quoteIconTip);
        copyString(buildCfg.genDoc.quoteIconWarning);
        copyString(buildCfg.genDoc.quoteIconAttention);
        copyString(buildCfg.genDoc.quoteIconExample);
        copyString(buildCfg.genDoc.quoteTitleNote);
        copyString(buildCfg.genDoc.quoteTitleTip);
        copyString(buildCfg.genDoc.quoteTitleWarning);
        copyString(buildCfg.genDoc.quoteTitleAttention);
        copyString(buildCfg.genDoc.quoteTitleExample);
        copyString(buildCfg.registeredConfigs);
        ownedStrings.swap(newOwnedStrings);
    }

    bool endsWithLineBreak(const std::string_view text)
    {
        if (text.empty())
            return false;

        const char last = text.back();
        return last == '\n' || last == '\r';
    }

    uint32_t countLineBreaks(const std::string_view text)
    {
        uint32_t count = 0;
        for (size_t i = 0; i < text.size(); ++i)
        {
            if (text[i] == '\n')
            {
                count++;
                continue;
            }

            if (text[i] != '\r')
                continue;

            count++;
            if (i + 1 < text.size() && text[i + 1] == '\n')
                i++;
        }

        return count;
    }

    Utf8 generatedSourceDumpBaseName(const CompilerInstance& compiler)
    {
        Utf8 baseName = buildCfgString(compiler.buildCfg().name);
        if (baseName.empty())
            baseName = defaultArtifactName(compiler.cmdLine());

        baseName = FileSystem::sanitizeFileName(baseName);
        if (baseName.empty())
            baseName = "module";
        return baseName;
    }

    fs::path generatedSourceOutputDirectory(const CompilerInstance& compiler)
    {
        const Utf8 outDir = buildCfgString(compiler.buildCfg().outDir);
        if (!outDir.empty())
            return FileSystem::absolutePathNoThrow(fs::path(outDir.c_str()));
        if (!compiler.cmdLine().outDir.empty())
            return FileSystem::absolutePathNoThrow(compiler.cmdLine().outDir);
        if (!compiler.cmdLine().exportApiDir.empty())
            return FileSystem::absolutePathNoThrow(compiler.cmdLine().exportApiDir);

        const Utf8 workDir = buildCfgString(compiler.buildCfg().workDir);
        if (!workDir.empty())
            return FileSystem::absolutePathNoThrow(fs::path(workDir.c_str()));

        if (!compiler.cmdLine().workDir.empty())
            return FileSystem::absolutePathNoThrow(compiler.cmdLine().workDir);

        return FileSystem::absolutePathNoThrow(Os::getTemporaryPath());
    }

    fs::path generatedSourceDumpPath(const CompilerInstance& compiler, const uint32_t threadIndex)
    {
        const fs::path directory = generatedSourceOutputDirectory(compiler);
        const Utf8     baseName  = generatedSourceDumpBaseName(compiler);
        return (directory / std::format("{}-generated-source-{}.swgsrc", baseName.c_str(), threadIndex)).lexically_normal();
    }

    Utf8 buildModuleNamespaceName(const CompilerInstance& compiler)
    {
        Utf8 moduleNamespaceName = buildCfgString(compiler.buildCfg().moduleNamespace);
        if (!moduleNamespaceName.empty())
            return moduleNamespaceName;

        Utf8 artifactName = buildCfgString(compiler.buildCfg().name);
        if (artifactName.empty())
            artifactName = defaultArtifactName(compiler.cmdLine());
        return defaultModuleNamespace(artifactName);
    }

    fs::path workspaceModulesDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / "modules").lexically_normal();
    }

    fs::path workspaceModuleDirectory(const fs::path& workspacePath, std::string_view moduleName)
    {
        return (workspaceModulesDirectory(workspacePath) / fs::path(std::string(moduleName))).lexically_normal();
    }

    fs::path workspaceOutputDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".output").lexically_normal();
    }

    fs::path workspaceModuleOutputDirectory(const fs::path& workspacePath, const Utf8& moduleName, const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind backendKind, const bool workDirectory)
    {
        fs::path result = workDirectory ? (workspacePath / ".tmp") : workspaceOutputDirectory(workspacePath);
        result /= fs::path(moduleName.c_str());
        result /= fs::path(backendKindName(backendKind).c_str());
        result /= fs::path(cmdLine.buildCfg.c_str());
        result /= fs::path(targetArchName(cmdLine.targetArch).c_str());
        return result.lexically_normal();
    }

    fs::path dependencyModuleDirectory(const fs::path& dependencyRoot, std::string_view moduleName)
    {
        return (dependencyRoot / fs::path(std::string(moduleName))).lexically_normal();
    }

    Result reportInvalidFolder(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Utf8 dependencyConfigurationLabel(const CommandLine& cmdLine)
    {
        return std::format("build-cfg '{}' and arch '{}'", cmdLine.buildCfg.c_str(), targetArchName(cmdLine.targetArch).c_str());
    }

    struct DependencyConfigCandidate
    {
        fs::path                     path;
        Runtime::BuildCfgBackendKind backendKind = Runtime::BuildCfgBackendKind::None;
    };

    Runtime::BuildCfgBackendKind dependencyBackendKindFromFolderName(const std::string_view name)
    {
        if (name == backendKindName(Runtime::BuildCfgBackendKind::Executable).view())
            return Runtime::BuildCfgBackendKind::Executable;
        if (name == backendKindName(Runtime::BuildCfgBackendKind::SharedLibrary).view())
            return Runtime::BuildCfgBackendKind::SharedLibrary;
        if (name == backendKindName(Runtime::BuildCfgBackendKind::StaticLibrary).view())
            return Runtime::BuildCfgBackendKind::StaticLibrary;
        if (name == backendKindName(Runtime::BuildCfgBackendKind::Export).view())
            return Runtime::BuildCfgBackendKind::Export;
        return Runtime::BuildCfgBackendKind::None;
    }

    bool isSharedDependencyBackendKind(const Runtime::BuildCfgBackendKind backendKind)
    {
        return backendKind == Runtime::BuildCfgBackendKind::SharedLibrary;
    }

    bool isStaticDependencyBackendKind(const Runtime::BuildCfgBackendKind backendKind)
    {
        return backendKind == Runtime::BuildCfgBackendKind::StaticLibrary;
    }

    bool isImportOnlyDependencyBackendKind(const Runtime::BuildCfgBackendKind backendKind)
    {
        return backendKind == Runtime::BuildCfgBackendKind::Export;
    }

    Utf8 joinDependencyPaths(const std::vector<fs::path>& paths)
    {
        Utf8 result;
        for (const fs::path& path : paths)
        {
            if (!result.empty())
                result += ", ";
            result += Utf8(path);
        }

        return result;
    }

    Result collectDependencyConfigurationMatches(std::vector<DependencyConfigCandidate>& outMatches, Utf8& outBecause, const fs::path& dependencyRoot, std::string_view moduleName, const CommandLine& cmdLine)
    {
        outMatches.clear();
        outBecause.clear();

        const fs::path moduleDir         = dependencyModuleDirectory(dependencyRoot, moduleName);
        fs::path       resolvedModuleDir = moduleDir;
        if (FileSystem::resolveExistingFolder(resolvedModuleDir, outBecause) != Result::Continue)
            return Result::Error;

        const auto      buildCfgDir = fs::path(cmdLine.buildCfg.c_str());
        const auto      archDir     = fs::path(targetArchName(cmdLine.targetArch).c_str());
        std::error_code ec;
        for (fs::directory_iterator it(resolvedModuleDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                outBecause = FileSystem::normalizeSystemMessage(ec);
                return Result::Error;
            }

            ec.clear();
            if (!it->is_directory(ec) || ec)
                continue;

            fs::path candidate = (it->path() / buildCfgDir / archDir).lexically_normal();
            ec.clear();
            if (!fs::is_directory(candidate, ec) || ec)
                continue;

            outMatches.push_back({.path        = FileSystem::normalizePath(candidate),
                                  .backendKind = dependencyBackendKindFromFolderName(it->path().filename().string())});
        }

        if (outMatches.empty())
        {
            outBecause = std::format("no configuration folder matches {}", dependencyConfigurationLabel(cmdLine).c_str());
            return Result::Error;
        }

        std::ranges::sort(outMatches, [](const DependencyConfigCandidate& lhs, const DependencyConfigCandidate& rhs) { return lhs.path < rhs.path; });
        outMatches.erase(std::ranges::unique(outMatches, {}, &DependencyConfigCandidate::path).begin(), outMatches.end());
        return Result::Continue;
    }

    Result findDependencyConfigurationDirectory(fs::path& outDir, Utf8& outBecause, const fs::path& dependencyRoot, std::string_view moduleName, const CommandLine& cmdLine, Runtime::BuildCfgBackendKind* outBackendKind = nullptr)
    {
        outDir.clear();
        if (outBackendKind)
            *outBackendKind = Runtime::BuildCfgBackendKind::None;

        std::vector<DependencyConfigCandidate> matches;
        SWC_RESULT(collectDependencyConfigurationMatches(matches, outBecause, dependencyRoot, moduleName, cmdLine));
        const auto selectUniqueMatch = [&](const auto& predicate, fs::path& selectedPath) -> bool {
            fs::path candidatePath;
            auto     candidateBackendKind = Runtime::BuildCfgBackendKind::None;
            for (const DependencyConfigCandidate& match : matches)
            {
                if (!predicate(match.backendKind))
                    continue;

                if (candidatePath.empty())
                {
                    candidatePath        = match.path;
                    candidateBackendKind = match.backendKind;
                    continue;
                }

                selectedPath.clear();
                return false;
            }

            if (candidatePath.empty())
                return false;

            selectedPath = std::move(candidatePath);
            if (outBackendKind)
                *outBackendKind = candidateBackendKind;
            return true;
        };

        fs::path selectedPath;
        if (selectUniqueMatch(isSharedDependencyBackendKind, selectedPath))
        {
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (selectUniqueMatch(isImportOnlyDependencyBackendKind, selectedPath))
        {
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (selectUniqueMatch(isStaticDependencyBackendKind, selectedPath))
        {
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (matches.size() != 1)
        {
            std::vector<fs::path> paths;
            paths.reserve(matches.size());
            for (const DependencyConfigCandidate& match : matches)
                paths.push_back(match.path);

            outBecause = std::format("multiple configuration folders match {} ({})", dependencyConfigurationLabel(cmdLine).c_str(), joinDependencyPaths(paths).c_str());
            return Result::Error;
        }

        if (matches.front().backendKind == Runtime::BuildCfgBackendKind::Executable)
        {
            outBecause = std::format("no importable dependency backend matches {} (found executable output only)", dependencyConfigurationLabel(cmdLine).c_str());
            return Result::Error;
        }

        outDir = matches.front().path;
        if (outBackendKind)
            *outBackendKind = matches.front().backendKind;
        return Result::Continue;
    }

    Result findDependencyConfigurationDirectoryForBackend(fs::path& outDir, Utf8& outBecause, const fs::path& dependencyRoot, std::string_view moduleName, const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind expectedBackendKind)
    {
        outDir.clear();

        std::vector<DependencyConfigCandidate> matches;
        SWC_RESULT(collectDependencyConfigurationMatches(matches, outBecause, dependencyRoot, moduleName, cmdLine));

        const auto it = std::ranges::find(matches, expectedBackendKind, &DependencyConfigCandidate::backendKind);
        if (it == matches.end())
        {
            outBecause = std::format("no '{}' dependency backend matches {}", backendKindName(expectedBackendKind).c_str(), dependencyConfigurationLabel(cmdLine).c_str());
            return Result::Error;
        }

        outDir = it->path;
        return Result::Continue;
    }

    fs::path dependencyRootFromConfigurationDir(const fs::path& configDir)
    {
        fs::path result = configDir;
        for (uint32_t i = 0; i < 4 && result.has_parent_path(); ++i)
            result = result.parent_path();
        return result.lexically_normal();
    }

    fs::path dependencyImportMetadataPath(const fs::path& apiDir, std::string_view moduleName)
    {
        fs::path result = apiDir / fs::path(std::string(moduleName));
        result.replace_extension(".deps");
        return result.lexically_normal();
    }

    bool shouldSkipWorkspaceEntry(const fs::directory_entry& entry)
    {
        std::error_code ec;
        if (!entry.is_directory(ec) || ec)
            return true;

        const std::string name = entry.path().filename().string();
        return !name.empty() && name[0] == '.';
    }

    Utf8 formatWorkspaceStageStat(const TaskContext& ctx, const CompilerInstance::WorkspaceBuildLogState& workspaceLogState)
    {
        std::vector<Utf8> parts;
        if (workspaceLogState.activeModules)
        {
            if (workspaceLogState.builtModules < workspaceLogState.activeModules)
                parts.push_back(TimedActionLog::formatStatRatio(ctx, workspaceLogState.builtModules, workspaceLogState.activeModules, "module"));
            else
                parts.push_back(TimedActionLog::formatStatCount(ctx, workspaceLogState.activeModules, "module"));
        }
        else if (workspaceLogState.discoveredModules)
        {
            parts.push_back(TimedActionLog::formatStatCount(ctx, workspaceLogState.discoveredModules, "module"));
        }

        if (workspaceLogState.ignoredModules)
            parts.push_back(TimedActionLog::formatStatCount(ctx, workspaceLogState.ignoredModules, "ignored module", nullptr, LogColor::Gray));

        return TimedActionLog::joinStatItems(ctx, parts);
    }

    Utf8 formatWorkspaceModuleStageStat(const TaskContext& ctx, const CompilerInstance& compiler, const TimedActionLog::StatsSnapshot& deltaSnapshot)
    {
        std::vector<Utf8> parts;
        if (deltaSnapshot.numFiles)
            parts.push_back(TimedActionLog::formatStatCount(ctx, deltaSnapshot.numFiles, "file"));

        const Utf8& artifactLabel = compiler.lastArtifactLabel();
        if (!artifactLabel.empty())
            parts.push_back(TimedActionLog::formatStatName(ctx, artifactLabel));

        return TimedActionLog::joinStatItems(ctx, parts);
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

    void runtimeAllocatorReq(const CompilerInstance*, Runtime::AllocatorRequest* request)
    {
        if (!request)
            return;

        switch (request->mode)
        {
            case Runtime::AllocatorMode::Free:
                mi_free(request->address);
                request->address = nullptr;
                return;

            case Runtime::AllocatorMode::Alloc:
                request->address = nullptr;
                [[fallthrough]];

            case Runtime::AllocatorMode::Realloc:
            {
                if (request->size == 0)
                {
                    if (request->mode == Runtime::AllocatorMode::Realloc)
                        mi_free(request->address);
                    request->address = nullptr;
                    return;
                }

                const size_t alignment = request->alignment ? request->alignment : sizeof(void*);
                if (request->mode == Runtime::AllocatorMode::Alloc)
                {
                    request->address = alignment > sizeof(void*) ? mi_malloc_aligned(request->size, alignment) : mi_malloc(request->size);
                }
                else
                {
                    request->address = alignment > sizeof(void*) ? mi_realloc_aligned(request->address, request->size, alignment) : mi_realloc(request->address, request->size);
                }

                return;
            }

            case Runtime::AllocatorMode::FreeAll:
            case Runtime::AllocatorMode::AssertIsAllocated:
                return;

            default:
                return;
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

CompilerInstance::SourceViewBuffer::SourceViewBuffer(const std::string_view source)
{
    content.reserve(source.size() + TRAILING_0);
    content.resize(source.size());
    if (!source.empty())
        std::memcpy(content.data(), source.data(), source.size());

    for (uint32_t i = 0; i < TRAILING_0; ++i)
        content.push_back(0);
}

std::string_view CompilerInstance::SourceViewBuffer::view() const
{
    if (content.size() < TRAILING_0)
        return {};

    return {reinterpret_cast<const char*>(content.data()), content.size() - TRAILING_0};
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
    fileLookup_        = std::make_unique<AppendOnlyLookupTable<SourceFile>>();
    srcViewLookup_     = std::make_unique<AppendOnlyLookupTable<SourceView>>();
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

bool CompilerInstance::tryEnqueueCodeGenJob(Sema& sema, SymbolFunction& symbolFunc, const AstNodeRef root) const
{
    if (!symbolFunc.tryMarkCodeGenJobScheduled())
        return false;

    SWC_ASSERT(root.isValid());
    auto* job = heapNew<CodeGenJob>(sema.ctx(), sema, symbolFunc, root);
    global().jobMgr().enqueue(*job, JobPriority::Normal, jobClientId());
    return true;
}

Sema* CompilerInstance::tryGetJobSema(Job* job)
{
    if (!job)
        return nullptr;
    if (auto* semaJob = job->safeCast<SemaJob>())
        return &semaJob->sema();
    if (auto* codeGenJob = job->safeCast<CodeGenJob>())
        return &codeGenJob->sema();
    return nullptr;
}

const Sema* CompilerInstance::tryGetJobSema(const Job* job)
{
    if (!job)
        return nullptr;
    if (const auto* semaJob = job->safeCast<SemaJob>())
        return &semaJob->sema();
    if (const auto* codeGenJob = job->safeCast<CodeGenJob>())
        return &codeGenJob->sema();
    return nullptr;
}

uint32_t CompilerInstance::pendingImplRegistrations(const IdentifierRef idRef) const
{
    if (!idRef.isValid())
        return 0;

    const std::scoped_lock lock(pendingImplRegistrationsMutex_);
    const auto             it = pendingImplRegistrations_.find(idRef);
    if (it == pendingImplRegistrations_.end())
        return 0;

    return it->second;
}

void CompilerInstance::incPendingImplRegistrations(const IdentifierRef idRef)
{
    SWC_ASSERT(idRef.isValid());
    const std::scoped_lock lock(pendingImplRegistrationsMutex_);
    pendingImplRegistrations_[idRef]++;
}

void CompilerInstance::decPendingImplRegistrations(const IdentifierRef idRef)
{
    SWC_ASSERT(idRef.isValid());

    bool notify = false;
    {
        const std::scoped_lock lock(pendingImplRegistrationsMutex_);
        const auto             it = pendingImplRegistrations_.find(idRef);
        SWC_ASSERT(it != pendingImplRegistrations_.end());
        SWC_ASSERT(it->second > 0);
        it->second--;
        if (!it->second)
        {
            pendingImplRegistrations_.erase(it);
            notify = true;
        }
    }

    if (notify)
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
        case CommandKind::Unittest:
            return;
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
    runtimeAllocator_.obj      = this;
    runtimeAllocator_.itable   = runtimeAllocatorITable_;
    runtimeAllocatorITable_[0] = nullptr;
    runtimeAllocatorITable_[1] = reinterpret_cast<void*>(&runtimeAllocatorReq);

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

uint32_t CompilerInstance::nativeProcessInfosOffset()
{
    std::call_once(nativeProcessInfosOffsetOnce_, [this] {
        const auto [offset, storage] = globalZeroSegment_.reserve<Runtime::ProcessInfos>();
        nativeProcessInfosOffset_    = offset;
        *storage                     = {};
    });

    SWC_ASSERT(nativeProcessInfosOffset_ != UINT32_MAX);
    return nativeProcessInfosOffset_;
}

void CompilerInstance::initPerThreadRuntimeContextForJit()
{
    PerThreadData& td              = perThreadData_[JobManager::threadIndex()];
    td.runtimeContext.runtimeFlags = Runtime::RuntimeFlags::FromCompiler;
    if (!td.runtimeContext.allocator.obj || !td.runtimeContext.allocator.itable)
        td.runtimeContext.allocator = runtimeAllocator();
    setRuntimeContextForCurrentThread(&td.runtimeContext);

    if (nativeRuntimeContextTlsIdOffset_ != UINT32_MAX)
    {
        uint64_t* tlsStorage = globalZeroSegment_.ptr<uint64_t>(nativeRuntimeContextTlsIdOffset_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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

    const std::unique_lock lock(stateMutex_);
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
        const std::unique_lock lock(stateMutex_);
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
    const std::shared_lock lock(stateMutex_);
    return nativeGlobalFunctionInitTargets_;
}

std::vector<SymbolVariable*> CompilerInstance::nativeGlobalVariablesSnapshot() const
{
    const std::shared_lock lock(stateMutex_);
    return nativeGlobalVariables_;
}

std::vector<SymbolFunction*> CompilerInstance::jitPreparedFunctionsSnapshot() const
{
    const std::shared_lock lock(stateMutex_);
    return jitPreparedFunctions_;
}

ExitCode CompilerInstance::run()
{
    Stats::resetCommandMetrics();
    logBefore();
    const auto runStart = std::chrono::steady_clock::now();
    ExitCode   exitCode;
    if (!cmdLine().workspacePath.empty())
        exitCode = runWorkspace();
    else
    {
        processCommand();
        if (!cmdLine().dryRun && !cmdLine().showConfig)
        {
            TaskContext ctx(*this);
            (void) flushGeneratedSourceDumps(ctx);
        }

        exitCode = Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
    }
    commandWallTimeNs_ = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - runStart).count();
    logAfter();
    logStats();
    return exitCode;
}

ExitCode CompilerInstance::runWorkspace()
{
    TaskContext                 ctx(*this);
    TimedActionLog::ScopedStage workspaceStage(ctx, TimedActionLog::Stage::Workspace);
    fs::path                    workspacePath = cmdLine().workspacePath;
    fs::path                    modulesPath   = workspaceModulesDirectory(workspacePath);
    Utf8                        because;

    workspaceBuildLogState_ = {};

    if (FileSystem::resolveExistingFolder(modulesPath, because) != Result::Continue)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_modules_missing);
        FileSystem::setDiagnosticPath(diag, &ctx, workspacePath);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    std::vector<WorkspaceModuleBuild> modules;
    std::error_code                   ec;
    for (fs::directory_iterator it(modulesPath, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
    {
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, modulesPath, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        const fs::directory_entry& entry = *it;
        if (shouldSkipWorkspaceEntry(entry))
            continue;

        WorkspaceModuleBuild moduleBuild;
        moduleBuild.moduleDir  = FileSystem::normalizePath(entry.path());
        moduleBuild.moduleFile = (moduleBuild.moduleDir / "module.swg").lexically_normal();
        moduleBuild.sourceDir  = (moduleBuild.moduleDir / "src").lexically_normal();
        moduleBuild.name       = moduleBuild.moduleDir.filename().string();

        if (FileSystem::resolveExistingFile(moduleBuild.moduleFile, because) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_module_file_missing);
            FileSystem::setDiagnosticPath(diag, &ctx, moduleBuild.moduleDir);
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        if (FileSystem::resolveExistingFolder(moduleBuild.sourceDir, because) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_module_src_missing);
            FileSystem::setDiagnosticPath(diag, &ctx, moduleBuild.moduleDir);
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        modules.push_back(std::move(moduleBuild));
    }

    std::ranges::sort(modules, [](const WorkspaceModuleBuild& lhs, const WorkspaceModuleBuild& rhs) { return lhs.name < rhs.name; });
    if (modules.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    std::unordered_map<Utf8, size_t> moduleIndices;
    moduleIndices.reserve(modules.size());
    for (size_t i = 0; i < modules.size(); ++i)
        moduleIndices.emplace(modules[i].name, i);

    for (WorkspaceModuleBuild& moduleBuild : modules)
    {
        CommandLine setupCmdLine = cmdLine();
        setupCmdLine.workspacePath.clear();
        setupCmdLine.modulePath     = moduleBuild.moduleDir;
        setupCmdLine.moduleFilePath = moduleBuild.moduleFile;
        setupCmdLine.directories.clear();
        setupCmdLine.files.clear();
        CommandLineParser::refreshBuildCfg(setupCmdLine);

        if (captureModuleSetupSnapshot(ctx, setupCmdLine, moduleBuild.setup) != Result::Continue)
            return ExitCode::CompileError;

        moduleBuild.ignoreInWorkspace = moduleBuild.setup.buildCfg.ignoreInWorkspace;
        for (const ModuleSetupImport& importRequest : moduleBuild.setup.imports)
        {
            if (!importRequest.location.empty())
                continue;

            if (moduleIndices.contains(importRequest.moduleName))
                moduleBuild.workspaceDependencies.push_back(importRequest.moduleName);
        }
    }

    for (const WorkspaceModuleBuild& moduleBuild : modules)
    {
        if (moduleBuild.ignoreInWorkspace)
            continue;

        for (const Utf8& dependency : moduleBuild.workspaceDependencies)
        {
            const WorkspaceModuleBuild& dependencyModule = modules[moduleIndices.at(dependency)];
            if (!dependencyModule.ignoreInWorkspace)
                continue;

            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_ignored_dependency);
            diag.addArgument(Diagnostic::ARG_SYM, moduleBuild.name);
            diag.addArgument(Diagnostic::ARG_TARGET, dependency);
            diag.report(ctx);
            return ExitCode::CompileError;
        }
    }

    std::vector<uint32_t>            indegree(modules.size(), 0);
    std::vector<std::vector<size_t>> dependents(modules.size());
    size_t                           activeModuleCount = 0;
    for (size_t i = 0; i < modules.size(); ++i)
    {
        if (modules[i].ignoreInWorkspace)
            continue;

        activeModuleCount++;
        for (const Utf8& dependency : modules[i].workspaceDependencies)
        {
            const size_t dependencyIndex = moduleIndices.at(dependency);
            if (modules[dependencyIndex].ignoreInWorkspace)
                continue;

            indegree[i]++;
            dependents[dependencyIndex].push_back(i);
        }
    }

    workspaceBuildLogState_.discoveredModules = modules.size();
    workspaceBuildLogState_.activeModules     = activeModuleCount;
    workspaceBuildLogState_.ignoredModules    = modules.size() - activeModuleCount;
    workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));

    std::vector<size_t> buildOrder;
    buildOrder.reserve(activeModuleCount);
    std::vector scheduled(modules.size(), false);
    while (buildOrder.size() < activeModuleCount)
    {
        size_t nextIndex = static_cast<size_t>(-1);
        for (size_t i = 0; i < modules.size(); ++i)
        {
            if (modules[i].ignoreInWorkspace || scheduled[i] || indegree[i] != 0)
                continue;

            nextIndex = i;
            break;
        }

        if (std::cmp_equal(nextIndex, -1))
        {
            for (size_t i = 0; i < modules.size(); ++i)
            {
                if (modules[i].ignoreInWorkspace || scheduled[i])
                    continue;

                Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_dependency_cycle);
                diag.addArgument(Diagnostic::ARG_SYM, modules[i].name);
                diag.report(ctx);
                return ExitCode::CompileError;
            }

            break;
        }

        scheduled[nextIndex] = true;
        buildOrder.push_back(nextIndex);
        for (const size_t dependentIndex : dependents[nextIndex])
        {
            SWC_ASSERT(indegree[dependentIndex] > 0);
            indegree[dependentIndex]--;
        }
    }

    const uint32_t buildCount = static_cast<uint32_t>(buildOrder.size());
    for (uint32_t buildIndex = 0; buildIndex < buildCount; ++buildIndex)
    {
        const size_t moduleIndex = buildOrder[buildIndex];
        if (runWorkspaceModule(modules[moduleIndex], buildIndex + 1, buildCount) != Result::Continue)
            return ExitCode::CompileError;

        workspaceBuildLogState_.builtModules++;
        workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));
    }

    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

Result CompilerInstance::runWorkspaceModule(const WorkspaceModuleBuild& moduleBuild, const uint32_t moduleIndex, const uint32_t moduleCount) const
{
    CommandLine moduleCmdLine    = cmdLine();
    moduleCmdLine.modulePath     = moduleBuild.moduleDir;
    moduleCmdLine.moduleFilePath = moduleBuild.moduleFile;
    moduleCmdLine.directories.clear();
    moduleCmdLine.directories.insert(moduleBuild.sourceDir);
    moduleCmdLine.files.clear();
    moduleCmdLine.outDir          = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, false);
    moduleCmdLine.workDir         = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, true);
    moduleCmdLine.exportApiDir    = moduleCmdLine.outDir;
    moduleCmdLine.outDirExplicit  = true;
    moduleCmdLine.workDirExplicit = true;
    moduleCmdLine.outDirStorage   = Utf8(moduleCmdLine.outDir);
    moduleCmdLine.workDirStorage  = Utf8(moduleCmdLine.workDir);
    CommandLineParser::refreshBuildCfg(moduleCmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance moduleCompiler(global(), moduleCmdLine);
    moduleCompiler.precomputedModuleSetup_  = &moduleBuild.setup;
    moduleCompiler.workspaceModuleLogState_ = WorkspaceModuleLogState{
        .name  = moduleBuild.name,
        .index = moduleIndex,
        .total = moduleCount,
    };

    const TaskContext           moduleCtx(moduleCompiler);
    TimedActionLog::ScopedStage moduleStage(moduleCtx, TimedActionLog::Stage::Module);
    moduleCompiler.processCommand();
    moduleStage.setStat(formatWorkspaceModuleStageStat(moduleCtx, moduleCompiler, moduleStage.delta()));
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    return Result::Continue;
}

SourceView& CompilerInstance::addSourceView()
{
    const std::unique_lock lock(sourceStorageMutex_);
    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());
    auto srcViewRef = SourceViewRef(srcViewLookup_->size());
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, nullptr));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addSourceView(FileRef fileRef)
{
    SWC_ASSERT(fileRef.isValid());

    const std::unique_lock lock(sourceStorageMutex_);
    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());
    auto        srcViewRef = SourceViewRef(srcViewLookup_->size());
    SourceFile* ownerFile  = fileLookup_->at(fileRef.get());
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, ownerFile));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addBufferedSourceView(const FileRef fileRef, const std::string_view content)
{
    SWC_ASSERT(fileRef.isValid());

    const std::unique_lock lock(sourceStorageMutex_);
    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());

    auto        srcViewRef = SourceViewRef(srcViewLookup_->size());
    SourceFile* ownerFile  = fileLookup_->at(fileRef.get());
    auto        buffer     = std::make_unique<SourceViewBuffer>(content);
    auto        sourceView = std::make_unique<SourceView>(srcViewRef, ownerFile, buffer->view());

    srcViewBuffers_.push_back(std::move(buffer));
    srcViews_.push_back(std::move(sourceView));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::srcView(SourceViewRef ref)
{
    SWC_ASSERT(ref.isValid());
    return *srcViewLookup_->at(ref.get());
}

const SourceView& CompilerInstance::srcView(SourceViewRef ref) const
{
    SWC_ASSERT(ref.isValid());
    return *srcViewLookup_->at(ref.get());
}

const SourceView* CompilerInstance::findSourceViewByFileName(const std::string_view fileName) const
{
    if (fileName.empty())
        return nullptr;

    const fs::path wantedPath{std::string(fileName)};
    const Utf8     wantedPathNormalized = Utf8Helper::normalizePathForCompare(wantedPath);

    const uint32_t numSourceViews = srcViewLookup_->size();
    for (uint32_t i = 0; i < numSourceViews; ++i)
    {
        const SourceView* srcView    = srcViewLookup_->at(i);
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
    const std::unique_lock lock(stateMutex_);
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
    const std::unique_lock lock(stateMutex_);
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
    const std::unique_lock lock(stateMutex_);
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
    const std::shared_lock lock(stateMutex_);
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

void CompilerInstance::cacheCompilerMessageTypeInfo(const TypeRef typeRef, const Runtime::TypeInfo* runtimeTypeInfo)
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
        const std::scoped_lock lock(compilerMessageMutex_);
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
        const std::scoped_lock lock(compilerMessageMutex_);
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

Result CompilerInstance::appendGeneratedSource(GeneratedSourceAppendResult& outResult, Utf8& outBecause, const std::string_view sectionText, const uint32_t codeOffsetInSection)
{
    outResult = {};
    outBecause.clear();

    SWC_ASSERT(codeOffsetInSection <= sectionText.size());

    const auto threadIndex = static_cast<uint32_t>(JobManager::threadIndex());
    auto&      generated   = perThreadData_[threadIndex].generatedSource;
    if (generated.path.empty())
        generated.path = generatedSourceDumpPath(*this, threadIndex);

    outResult.path            = generated.path;
    outResult.codeStartOffset = codeOffsetInSection;
    outResult.lineOffset      = generated.nextLineOffset;
    outResult.snapshot        = sectionText;
    if (!outResult.snapshot.empty() && !endsWithLineBreak(outResult.snapshot.view()))
        outResult.snapshot += "\n";

    if (!outResult.snapshot.empty())
    {
        generated.content += outResult.snapshot;
        generated.nextLineOffset += countLineBreaks(outResult.snapshot.view());
        generated.dirty = true;
    }

    return Result::Continue;
}

Result CompilerInstance::flushGeneratedSourceDumps(TaskContext& ctx)
{
    for (PerThreadData& td : perThreadData_)
    {
        auto& generated = td.generatedSource;
        if (!generated.dirty || generated.path.empty())
            continue;

        std::error_code ec;
        fs::create_directories(generated.path.parent_path(), ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        std::ofstream generatedStream(generated.path, std::ios::binary | std::ios::trunc);
        if (!generatedStream.is_open())
        {
            Utf8 because = Os::systemError();
            if (because.empty())
                because = FileSystem::describeIoProblem(FileSystem::IoProblem::OpenWrite);
            else
                because = FileSystem::normalizeSystemMessage(because);

            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        if (!generated.content.empty())
            generatedStream.write(generated.content.data(), static_cast<std::streamsize>(generated.content.size()));

        if (!generatedStream)
        {
            Utf8 because = Os::systemError();
            if (because.empty())
                because = FileSystem::describeIoProblem(FileSystem::IoProblem::Write);
            else
                because = FileSystem::normalizeSystemMessage(because);

            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        generatedStream.close();
        if (!generatedStream)
        {
            Utf8 because = Os::systemError();
            if (because.empty())
                because = FileSystem::describeIoProblem(FileSystem::IoProblem::CloseWrite);
            else
                because = FileSystem::normalizeSystemMessage(because);

            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        generated.dirty = false;
    }

    return Result::Continue;
}

void CompilerInstance::registerInMemoryFile(fs::path path, const std::string_view content)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    path = path.lexically_normal();

    const std::unique_lock lock(sourceStorageMutex_);
    inMemoryFiles_[Utf8Helper::normalizePathForCompare(path)] = Utf8(content);
}

SourceFile& CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedFile(path.lexically_normal(), flags);
}

SourceFile& CompilerInstance::addLoadedFile(fs::path path, FileFlags flags, const std::string_view content)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedLoadedFile(path.lexically_normal(), flags, content);
}

SourceFile& CompilerInstance::file(const FileRef ref) const
{
    SWC_ASSERT(ref.isValid());
    SourceFile* file = fileLookup_->at(ref.get());
    SWC_ASSERT(file != nullptr);
    return *file;
}

std::vector<SourceFile*> CompilerInstance::filesSnapshot() const
{
    return files();
}

SourceFile& CompilerInstance::addResolvedFile(fs::path path, FileFlags flags)
{
    const std::unique_lock lock(sourceStorageMutex_);
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());
    path = path.lexically_normal();

    SWC_ASSERT(files_.size() == fileLookup_->size());
    auto fileRef = FileRef(fileLookup_->size());
    files_.emplace_back(std::make_unique<SourceFile>(fileRef, std::move(path), flags));
    fileLookup_->pushBack(files_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    fileRef.dbgPtr = files_.back().get();
#endif

    const Utf8 key = Utf8Helper::normalizePathForCompare(files_.back()->path());
    const auto it  = inMemoryFiles_.find(key);
    if (it != inMemoryFiles_.end())
        files_.back()->setContent(it->second.view());

    return *files_.back();
}

SourceFile& CompilerInstance::addResolvedLoadedFile(fs::path path, FileFlags flags, const std::string_view content)
{
    const std::unique_lock lock(sourceStorageMutex_);
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());
    path = path.lexically_normal();

    SWC_ASSERT(files_.size() == fileLookup_->size());
    auto sourceFileRef = FileRef(fileLookup_->size());
    auto sourceFile    = std::make_unique<SourceFile>(sourceFileRef, std::move(path), flags);
    sourceFile->setContent(content);

    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());
    auto sourceViewRef = SourceViewRef(srcViewLookup_->size());
    auto sourceView    = std::make_unique<SourceView>(sourceViewRef, sourceFile.get());
    sourceFile->ast().setSourceView(*sourceView);

    files_.push_back(std::move(sourceFile));
    fileLookup_->pushBack(files_.back().get());
    srcViews_.push_back(std::move(sourceView));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    sourceFileRef.dbgPtr = files_.back().get();
    sourceViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *files_.back();
}

std::vector<SourceFile*> CompilerInstance::files() const
{
    std::vector<SourceFile*> result;
    const uint32_t           numFiles = fileLookup_->size();
    result.reserve(numFiles);
    for (uint32_t i = 0; i < numFiles; ++i)
        result.push_back(fileLookup_->at(i));
    return result;
}

bool CompilerInstance::hasResolvedFilePath(const fs::path& path) const
{
    const Utf8 wantedPathNormalized = Utf8Helper::normalizePathForCompare(path);

    const uint32_t numFiles = fileLookup_->size();
    for (uint32_t i = 0; i < numFiles; ++i)
    {
        const SourceFile* file = fileLookup_->at(i);
        if (Utf8Helper::normalizePathForCompare(file->path()) == wantedPathNormalized)
            return true;
    }

    return false;
}

Result CompilerInstance::registerModuleSetupImport(const std::string_view moduleName, const std::string_view location, const std::string_view version, const Runtime::BuildCfgBackendKind linkBackendKind)
{
    if (moduleName.empty())
        return Result::Continue;

    for (const ModuleSetupImport& existingImport : moduleSetupImports_)
    {
        if (existingImport.moduleName == moduleName &&
            existingImport.location == location &&
            existingImport.version == version &&
            existingImport.linkBackendKind == linkBackendKind)
            return Result::Continue;
    }

    ModuleSetupImport importRequest;
    importRequest.moduleName      = moduleName;
    importRequest.location        = location;
    importRequest.version         = version;
    importRequest.linkBackendKind = linkBackendKind;
    moduleSetupImports_.push_back(std::move(importRequest));
    return Result::Continue;
}

Result CompilerInstance::registerModuleSetupLoad(const fs::path& filePath)
{
    if (filePath.empty())
        return Result::Continue;

    moduleSetupLoadedFiles_.insert(FileSystem::normalizePath(filePath));
    return Result::Continue;
}

void CompilerInstance::registerImportedDependencyLinkDir(const fs::path& path)
{
    if (path.empty())
        return;

    const fs::path normalizedPath = FileSystem::normalizePath(path);
    if (std::ranges::find(importedDependencyLinkDirs_, normalizedPath) != importedDependencyLinkDirs_.end())
        return;

    importedDependencyLinkDirs_.push_back(normalizedPath);
}

void CompilerInstance::registerImportedSharedModuleDir(const fs::path& path)
{
    if (path.empty())
        return;

    externalModuleMgr().registerSearchPath(FileSystem::normalizePath(path));
}

void CompilerInstance::adoptBuildCfg(const Runtime::BuildCfg& buildCfg)
{
    buildCfg_ = buildCfg;
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
}

Result CompilerInstance::captureModuleSetupSnapshot(const TaskContext& ctx, const CommandLine& setupCmdLine, ModuleSetupSnapshot& outSnapshot) const
{
    SWC_UNUSED(ctx);
    outSnapshot = {};
    CompilerInstance setupCompiler(global(), setupCmdLine);
    setupCompiler.moduleSetupMode_ = true;
    struct ConstCallCacheResetGuard
    {
        ~ConstCallCacheResetGuard()
        {
            SemaJIT::clearConstCallCache();
        }
    } constCallCacheResetGuard;

    TaskContext setupCtx(setupCompiler);
    SWC_RESULT(setupCompiler.collectFiles(setupCtx));

    const Global&     global       = setupCtx.global();
    JobManager&       jobMgr       = global.jobMgr();
    const JobClientId clientId     = setupCompiler.jobClientId();
    const uint64_t    errorsBefore = Stats::getNumErrors();

    for (SourceFile* file : setupCompiler.files())
    {
        auto* job = heapNew<ParserJob>(setupCtx, file);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "CompilerInstance::runModuleSetup parser waitAll");
#endif
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    std::vector<SourceFile*> files;
    files.reserve(setupCompiler.files().size());
    for (SourceFile* file : setupCompiler.files())
    {
        const SourceView& srcView = file->ast().srcView();
        if (srcView.mustSkip())
            continue;
        if (!srcView.runsSema())
            continue;
        if (file->hasError())
            continue;
        files.push_back(file);
    }

    if (files.empty())
    {
        outSnapshot.buildCfg    = setupCompiler.buildCfg();
        outSnapshot.imports     = setupCompiler.moduleSetupImports_;
        outSnapshot.loadedFiles = setupCompiler.moduleSetupLoadedFiles_;
        ownBuildCfgStrings(outSnapshot.buildCfg, outSnapshot.ownedStrings);
        return Result::Continue;
    }

    SWC_RESULT(setupCompiler.setupSema(setupCtx));

    auto*      symModule           = Symbol::make<SymbolModule>(setupCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    const Utf8 moduleNamespaceName = buildModuleNamespaceName(setupCompiler);

    constexpr SymbolFlags namespaceFlags  = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
    const IdentifierRef   idRef           = setupCtx.idMgr().addIdentifierOwned(moduleNamespaceName, Math::hash(moduleNamespaceName));
    auto*                 moduleNamespace = Symbol::make<SymbolNamespace>(setupCtx, nullptr, TokenRef::invalid(), idRef, namespaceFlags);
    symModule->addSingleSymbol(setupCtx, moduleNamespace);
    setupCompiler.setSymModule(symModule);

    for (SourceFile* file : files)
    {
        file->setModuleNamespace(*moduleNamespace);
        auto* job = heapNew<SemaJob>(setupCtx, file->nodePayloadContext(), true);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "CompilerInstance::runModuleSetup decl waitAll");
#endif
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    for (SourceFile* file : files)
    {
        auto* job = heapNew<SemaJob>(setupCtx, file->nodePayloadContext(), false);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    Sema::waitDone(setupCtx, clientId);
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "CompilerInstance::runModuleSetup full waitDone");
#endif
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    outSnapshot.buildCfg    = setupCompiler.buildCfg();
    outSnapshot.imports     = setupCompiler.moduleSetupImports_;
    outSnapshot.loadedFiles = setupCompiler.moduleSetupLoadedFiles_;
    ownBuildCfgStrings(outSnapshot.buildCfg, outSnapshot.ownedStrings);
    return Result::Continue;
}

Result CompilerInstance::applyModuleSetupInputs(TaskContext& ctx, const ModuleSetupSnapshot& setupSnapshot)
{
    moduleSetupImports_     = setupSnapshot.imports;
    moduleSetupLoadedFiles_ = setupSnapshot.loadedFiles;

    struct ResolvedModuleImportPaths
    {
        fs::path                     apiDir;
        Runtime::BuildCfgBackendKind apiBackendKind = Runtime::BuildCfgBackendKind::None;
        fs::path                     linkDir;
        fs::path                     sharedDir;
        fs::path                     dependencyRoot;
    };

    const auto resolveExplicitDependencyRoot = [&](fs::path& outRoot, const ModuleSetupImport& importRequest) -> Result {
        if (importRequest.location == "swag@std")
        {
            const std::optional<Utf8> installRoot = Os::readEnvironmentVariable("SWAG_PATH");
            if (!installRoot.has_value() || installRoot->empty())
                return reportInvalidFolder(ctx, "SWAG_PATH", "environment variable is not defined");

            outRoot = fs::path(installRoot->c_str());
            SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
            outRoot = (outRoot / "std" / ".output").lexically_normal();
            return Result::Continue;
        }

        outRoot = fs::path(importRequest.location.c_str());
        if (outRoot.is_relative())
        {
            const fs::path baseDir = cmdLine().moduleFilePath.empty() ? FileSystem::currentPathNoThrow() : cmdLine().moduleFilePath.parent_path();
            if (!baseDir.empty())
                outRoot = (baseDir / outRoot).lexically_normal();
        }

        SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
        return Result::Continue;
    };

    const auto resolveLinkAndSharedDirs = [&](ResolvedModuleImportPaths& outPaths, const fs::path& dependencyRoot, const ModuleSetupImport& importRequest) -> Result {
        outPaths.linkDir.clear();
        outPaths.sharedDir.clear();
        outPaths.dependencyRoot = FileSystem::normalizePath(dependencyRoot);

        Utf8     because;
        fs::path sharedDir;
        if (findDependencyConfigurationDirectoryForBackend(sharedDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), Runtime::BuildCfgBackendKind::SharedLibrary) == Result::Continue)
            outPaths.sharedDir = std::move(sharedDir);

        if (importRequest.linkBackendKind != Runtime::BuildCfgBackendKind::None)
        {
            if (findDependencyConfigurationDirectoryForBackend(outPaths.linkDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), importRequest.linkBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
            return Result::Continue;
        }

        if (!outPaths.sharedDir.empty())
        {
            outPaths.linkDir = outPaths.sharedDir;
            return Result::Continue;
        }

        if (outPaths.apiBackendKind == Runtime::BuildCfgBackendKind::StaticLibrary)
            outPaths.linkDir = outPaths.apiDir;
        return Result::Continue;
    };

    const auto resolveDependencyImportDir = [&](ResolvedModuleImportPaths& outPaths, const ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot) -> Result {
        outPaths = {};

        if (!importRequest.location.empty())
        {
            fs::path dependencyRoot;
            SWC_RESULT(resolveExplicitDependencyRoot(dependencyRoot, importRequest));

            Utf8 because;
            if (findDependencyConfigurationDirectory(outPaths.apiDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), &outPaths.apiBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
            return resolveLinkAndSharedDirs(outPaths, dependencyRoot, importRequest);
        }

        if (preferredDependencyRoot && !preferredDependencyRoot->empty())
        {
            Utf8 because;
            if (findDependencyConfigurationDirectory(outPaths.apiDir, because, *preferredDependencyRoot, importRequest.moduleName.view(), cmdLine(), &outPaths.apiBackendKind) == Result::Continue)
                return resolveLinkAndSharedDirs(outPaths, *preferredDependencyRoot, importRequest);
        }

        if (!cmdLine().workspacePath.empty())
        {
            fs::path        workspaceModuleDir = workspaceModuleDirectory(cmdLine().workspacePath, importRequest.moduleName.view());
            std::error_code ec;
            if (fs::is_directory(workspaceModuleDir, ec))
            {
                const fs::path dependencyRoot = workspaceOutputDirectory(cmdLine().workspacePath);
                Utf8           because;
                if (findDependencyConfigurationDirectory(outPaths.apiDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), &outPaths.apiBackendKind) != Result::Continue)
                    return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
                return resolveLinkAndSharedDirs(outPaths, dependencyRoot, importRequest);
            }
        }

        std::vector<fs::path>                     matches;
        std::vector<Runtime::BuildCfgBackendKind> matchKinds;
        for (const fs::path& dependencyRoot : cmdLine().importApiDirs)
        {
            fs::path configDir;
            Utf8     because;
            auto     backendKind = Runtime::BuildCfgBackendKind::None;
            if (findDependencyConfigurationDirectory(configDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), &backendKind) != Result::Continue)
                continue;

            matches.push_back(std::move(configDir));
            matchKinds.push_back(backendKind);
        }

        std::vector<size_t> order(matches.size());
        std::iota(order.begin(), order.end(), 0);
        std::ranges::sort(order, [&](const size_t lhs, const size_t rhs) { return matches[lhs] < matches[rhs]; });

        std::vector<fs::path>                     uniqueMatches;
        std::vector<Runtime::BuildCfgBackendKind> uniqueMatchKinds;
        uniqueMatches.reserve(matches.size());
        uniqueMatchKinds.reserve(matchKinds.size());
        for (const size_t index : order)
        {
            if (!uniqueMatches.empty() && uniqueMatches.back() == matches[index])
                continue;

            uniqueMatches.push_back(matches[index]);
            uniqueMatchKinds.push_back(matchKinds[index]);
        }

        if (matches.empty())
        {
            if (cmdLine().importApiDirs.empty())
                return reportInvalidFolder(ctx, importRequest.moduleName.c_str(), "no workspace dependency was found and no --import-api-dir root was provided");

            const Utf8 because = std::format("module '{}' was not found in any dependency root for {}", importRequest.moduleName.c_str(), dependencyConfigurationLabel(cmdLine()).c_str());
            return reportInvalidFolder(ctx, importRequest.moduleName.c_str(), because);
        }

        if (uniqueMatches.size() != 1)
        {
            const Utf8 because = std::format("multiple dependency roots match {} ({})", dependencyConfigurationLabel(cmdLine()).c_str(), joinDependencyPaths(uniqueMatches).c_str());
            return reportInvalidFolder(ctx, importRequest.moduleName.c_str(), because);
        }

        outPaths.apiDir         = uniqueMatches.front();
        outPaths.apiBackendKind = uniqueMatchKinds.front();
        return resolveLinkAndSharedDirs(outPaths, dependencyRootFromConfigurationDir(outPaths.apiDir), importRequest);
    };

    const auto captureDependencyImportSnapshot = [&](const fs::path& depsFile, ModuleSetupSnapshot& outSnapshot) -> Result {
        CommandLine setupCmdLine = cmdLine();
        setupCmdLine.directories.clear();
        setupCmdLine.files.clear();
        setupCmdLine.importApiModules.clear();
        setupCmdLine.importApiFiles.clear();
        setupCmdLine.exportApiDir.clear();
        setupCmdLine.modulePath.clear();
        setupCmdLine.moduleFilePath = depsFile;
        CommandLineParser::refreshBuildCfg(setupCmdLine);
        return captureModuleSetupSnapshot(ctx, setupCmdLine, outSnapshot);
    };

    std::unordered_set<Utf8> processedDependencyApis;
    const auto               processImports = [&](auto&& self, std::span<const ModuleSetupImport> imports, const fs::path* preferredDependencyRoot) -> Result {
        for (const ModuleSetupImport& importRequest : imports)
        {
            ResolvedModuleImportPaths importPaths;
            SWC_RESULT(resolveDependencyImportDir(importPaths, importRequest, preferredDependencyRoot));
            collectFolderFiles(importPaths.apiDir, FileFlagsE::ImportedApi, false);
            registerImportedDependencyLinkDir(importPaths.linkDir);
            registerImportedSharedModuleDir(importPaths.sharedDir);

            const auto apiDirKey = Utf8(FileSystem::normalizePath(importPaths.apiDir));
            if (!processedDependencyApis.insert(apiDirKey).second)
                continue;

            fs::path            depsFile = dependencyImportMetadataPath(importPaths.apiDir, importRequest.moduleName.view());
            Utf8                because;
            ModuleSetupSnapshot nestedSnapshot;
            if (FileSystem::resolveExistingFile(depsFile, because) != Result::Continue)
                continue;

            SWC_RESULT(captureDependencyImportSnapshot(depsFile, nestedSnapshot));
            SWC_RESULT(self(self, nestedSnapshot.imports, &importPaths.dependencyRoot));
        }

        return Result::Continue;
    };

    SWC_RESULT(processImports(processImports, setupSnapshot.imports, nullptr));

    for (const fs::path& filePath : setupSnapshot.loadedFiles)
    {
        fs::path resolvedPath = filePath;
        SWC_RESULT(FileSystem::resolveFile(ctx, resolvedPath));
        if (hasResolvedFilePath(resolvedPath))
            continue;

        addResolvedFile(resolvedPath, FileFlagsE::ModuleSrc);
    }

    return Result::Continue;
}

Result CompilerInstance::runModuleSetup(TaskContext& ctx)
{
    if (modulePathFile_.empty() || cmdLine().moduleFilePath.empty())
        return Result::Continue;

    if (precomputedModuleSetup_)
    {
        adoptBuildCfg(precomputedModuleSetup_->buildCfg);
        reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
        ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
        return applyModuleSetupInputs(ctx, *precomputedModuleSetup_);
    }

    CommandLine setupCmdLine = cmdLine();
    setupCmdLine.directories.clear();
    setupCmdLine.files.clear();
    setupCmdLine.importApiModules.clear();
    setupCmdLine.importApiDirs.clear();
    setupCmdLine.importApiFiles.clear();
    setupCmdLine.exportApiDir.clear();
    setupCmdLine.moduleFilePath = modulePathFile_;
    setupCmdLine.modulePath     = modulePathFile_.parent_path();
    setupCmdLine.runtime        = true;
    CommandLineParser::refreshBuildCfg(setupCmdLine);

    ModuleSetupSnapshot setupSnapshot;
    SWC_RESULT(captureModuleSetupSnapshot(ctx, setupCmdLine, setupSnapshot));
    adoptBuildCfg(setupSnapshot.buildCfg);
    reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
    return applyModuleSetupInputs(ctx, setupSnapshot);
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    for (fs::path& path : paths)
    {
        if (hasResolvedFilePath(path))
            continue;
        addResolvedFile(std::move(path), flags);
    }
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

Result CompilerInstance::collectImportedApiFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    if (!cmdLine.importApiModules.empty())
    {
        const fs::path dependencyRoot = (FileSystem::compilerResourceRoot(exeFullName_) / "std" / ".output" / "dep").lexically_normal();
        for (const Utf8& moduleName : cmdLine.importApiModules)
        {
            fs::path importDir;
            auto     importBackendKind = Runtime::BuildCfgBackendKind::None;
            Utf8     because;
            if (findDependencyConfigurationDirectory(importDir, because, dependencyRoot, moduleName.view(), cmdLine, &importBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, moduleName.view()), because);

            collectFolderFiles(importDir, FileFlagsE::ImportedApi, false);
            fs::path sharedDir;
            if (findDependencyConfigurationDirectoryForBackend(sharedDir, because, dependencyRoot, moduleName.view(), cmdLine, Runtime::BuildCfgBackendKind::SharedLibrary) == Result::Continue)
            {
                registerImportedSharedModuleDir(sharedDir);
                registerImportedDependencyLinkDir(sharedDir);
            }
            else if (importBackendKind == Runtime::BuildCfgBackendKind::StaticLibrary)
            {
                registerImportedDependencyLinkDir(importDir);
            }
        }
    }

    if (cmdLine.importApiFiles.empty())
        return Result::Continue;

    files_.reserve(files_.size() + cmdLine.importApiFiles.size());
    for (const fs::path& file : cmdLine.importApiFiles)
    {
        if (hasResolvedFilePath(file))
            continue;
        addResolvedFile(file, FileFlagsE::ImportedApi);
        if (file.has_parent_path())
            registerImportedDependencyLinkDir(file.parent_path());
    }

    return Result::Continue;
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine        = ctx.cmdLine();
    const FileFlags    directSrcFlags = cmdLine.moduleFilePath.empty() ? FileFlagsE::CustomSrc : FileFlagsE::ModuleSrc;

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
        collectFolderFiles(folder, directSrcFlags, true);

    // Collect direct files from the command line
    if (!cmdLine.files.empty())
    {
        files_.reserve(files_.size() + cmdLine.files.size());
        for (const fs::path& file : cmdLine.files)
        {
            if (hasResolvedFilePath(file))
                continue;
            addResolvedFile(file, directSrcFlags);
        }
    }

    // Collect files for the module
    if (!cmdLine.moduleFilePath.empty())
    {
        modulePathFile_ = cmdLine.moduleFilePath;
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        if (!hasResolvedFilePath(modulePathFile_))
            addResolvedFile(modulePathFile_, FileFlagsE::Module);
    }
    else if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        if (!hasResolvedFilePath(modulePathFile_))
            addResolvedFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        Utf8 because;
        if (FileSystem::resolveExistingFolder(modulePathSrc_, because) == Result::Continue)
            collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
        else
            modulePathSrc_.clear();
    }

    SWC_RESULT(collectImportedApiFiles(ctx));

    // Collect runtime files
    if (cmdLine.runtime)
    {
        fs::path runtimePath = FileSystem::compilerResourceRoot(exeFullName_) / "runtime";
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
    return ModuleApi::exportFiles(ctx);
}

SWC_END_NAMESPACE();

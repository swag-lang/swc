#pragma once
#include "Backend/Runtime.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerTagRegistry.h"
#include "Main/ExitCodes.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Utf8.h"
#include "Support/Memory/Arena.h"
#include "Support/Thread/JobManager.h"
#include "Support/Thread/RaceCondition.h"

SWC_BEGIN_NAMESPACE();

struct AstCompilerFunc;
class SourceView;
class Sema;
class TaskContext;
class TypeManager;
class TypeGen;
class ConstantManager;
class IdentifierManager;
class Symbol;
class SymbolModule;
class SymbolFunction;
class SymbolVariable;
class JITMemoryManager;
class ExternalModuleManager;
class Global;
class SourceFile;
class JITExecManager;
class CompilerMessageTypeInfoJob;
struct CommandLine;

class CompilerInstance
{
public:
    struct CompilerMessageEvent
    {
        Runtime::CompilerMsgKind kind   = Runtime::CompilerMsgKind::PassAfterSemantic;
        Symbol*                  symbol = nullptr;
    };

    struct CompilerMessageListener
    {
        SymbolFunction*                   function        = nullptr;
        AstNodeRef                        nodeRef         = AstNodeRef::invalid();
        uint64_t                          mask            = 0;
        size_t                            nextReplayIndex = 0;
        size_t                            nextEventIndex  = 0;
        std::vector<CompilerMessageEvent> replayEvents;
        std::unordered_set<const Symbol*> replayedSymbols;
    };

    struct GeneratedSourceAppendResult
    {
        fs::path path;
        Utf8     snapshot;
        uint32_t codeStartOffset = 0;
    };

    CompilerInstance(const Global& global, const CommandLine& cmdLine);
    ~CompilerInstance();

    ExitCode run();

    const Global&                   global() const { return *(global_); }
    const CommandLine&              cmdLine() const { return *(cmdLine_); }
    JobClientId                     jobClientId() const { return jobClientId_; }
    TypeManager&                    typeMgr() { return *(typeMgr_.get()); }
    const TypeManager&              typeMgr() const { return *(typeMgr_.get()); }
    TypeGen&                        typeGen() { return *(typeGen_.get()); }
    const TypeGen&                  typeGen() const { return *(typeGen_.get()); }
    ConstantManager&                cstMgr() { return *(cstMgr_.get()); }
    const ConstantManager&          cstMgr() const { return *(cstMgr_.get()); }
    IdentifierManager&              idMgr() { return *(idMgr_.get()); }
    const IdentifierManager&        idMgr() const { return *(idMgr_.get()); }
    DataSegment&                    constantSegment() { return constantSegment_; }
    const DataSegment&              constantSegment() const { return constantSegment_; }
    DataSegment&                    globalZeroSegment() { return globalZeroSegment_; }
    const DataSegment&              globalZeroSegment() const { return globalZeroSegment_; }
    DataSegment&                    globalInitSegment() { return globalInitSegment_; }
    const DataSegment&              globalInitSegment() const { return globalInitSegment_; }
    DataSegment&                    compilerSegment() { return compilerSegment_; }
    const DataSegment&              compilerSegment() const { return compilerSegment_; }
    std::byte*                      dataSegmentAddress(DataSegmentKind kind, uint32_t offset);
    const std::byte*                dataSegmentAddress(DataSegmentKind kind, uint32_t offset) const;
    Runtime::BuildCfg&              buildCfg() { return buildCfg_; }
    const Runtime::BuildCfg&        buildCfg() const { return buildCfg_; }
    const Utf8&                     lastArtifactLabel() const { return lastArtifactLabel_; }
    void                            setLastArtifactLabel(Utf8 label) { lastArtifactLabel_ = std::move(label); }
    void                            clearLastArtifactLabel() { lastArtifactLabel_.clear(); }
    Runtime::ICompiler&             runtimeCompiler() { return runtimeCompiler_; }
    const Runtime::ICompiler&       runtimeCompiler() const { return runtimeCompiler_; }
    Runtime::CompilerMessage&       runtimeCompilerMessage() { return runtimeCompilerMessage_; }
    const Runtime::CompilerMessage& runtimeCompilerMessage() const { return runtimeCompilerMessage_; }
    JITMemoryManager&               jitMemMgr() { return *(jitMemMgr_.get()); }
    const JITMemoryManager&         jitMemMgr() const { return *(jitMemMgr_.get()); }
    JITExecManager&                 jitExecMgr() { return *(jitExecMgr_.get()); }
    const JITExecManager&           jitExecMgr() const { return *(jitExecMgr_.get()); }
    ExternalModuleManager&          externalModuleMgr() { return *(externalModuleMgr_.get()); }
    const ExternalModuleManager&    externalModuleMgr() const { return *(externalModuleMgr_.get()); }
    void                            initPerThreadRuntimeContextForJit();
    static uint64_t*                runtimeContextTlsIdStorage();
    static Runtime::Context*        runtimeContextFromTls();
    static void                     setRuntimeContextForCurrentThread(Runtime::Context* context);
    uint32_t                        nativeRuntimeContextTlsIdOffset();

    SymbolModule*       symModule() { return symModule_; }
    const SymbolModule* symModule() const { return symModule_; }
    void                setSymModule(SymbolModule* symModule) { symModule_ = symModule; }

    void                                registerNativeCodeFunction(SymbolFunction* symbol);
    void                                registerNativeTestFunction(SymbolFunction* symbol);
    void                                registerNativeInitFunction(SymbolFunction* symbol);
    void                                registerNativePreMainFunction(SymbolFunction* symbol);
    void                                registerNativeDropFunction(SymbolFunction* symbol);
    void                                registerNativeMainFunction(SymbolFunction* symbol);
    void                                registerNativeGlobalVariable(SymbolVariable* symbol);
    void                                registerNativeGlobalFunctionInitTarget(SymbolFunction* symbol);
    void                                registerPreparedJitFunction(SymbolFunction* symbol);
    void                                invalidateGlobalFunctionBindings();
    Result                              ensurePatchedGlobalFunctionBindings(TaskContext& ctx);
    void                                resetPreparedJitFunctions();
    uint64_t                            nativeGlobalFunctionInitTargetsVersion() const noexcept { return nativeGlobalFunctionInitTargetsVersion_.load(std::memory_order_acquire); }
    std::vector<SymbolFunction*>        nativeGlobalFunctionInitTargetsSnapshot() const;
    std::vector<SymbolVariable*>        nativeGlobalVariablesSnapshot() const;
    std::vector<SymbolFunction*>        jitPreparedFunctionsSnapshot() const;
    const std::vector<SymbolFunction*>& nativeCodeSegment() const { return nativeCodeSegment_; }
    const std::vector<SymbolFunction*>& nativeTestFunctions() const { return nativeTestFunctions_; }
    const std::vector<SymbolFunction*>& nativeInitFunctions() const { return nativeInitFunctions_; }
    const std::vector<SymbolFunction*>& nativePreMainFunctions() const { return nativePreMainFunctions_; }
    const std::vector<SymbolFunction*>& nativeDropFunctions() const { return nativeDropFunctions_; }
    const std::vector<SymbolFunction*>& nativeMainFunctions() const { return nativeMainFunctions_; }
    const std::vector<SymbolVariable*>& nativeGlobalVariables() const { return nativeGlobalVariables_; }

    Result setupSema(TaskContext& ctx);
    void   notifyAlive() { changed_.store(true, std::memory_order_release); }
    bool   changed() const { return changed_.load(std::memory_order_acquire); }
    bool   consumeChanged() { return changed_.exchange(false, std::memory_order_acq_rel); }

    uint32_t pendingImplRegistrations() const;
    void     incPendingImplRegistrations();
    void     decPendingImplRegistrations();

    std::atomic<uint32_t>&       atomicId() { return atomicId_; }
    const std::atomic<uint32_t>& atomicId() const { return atomicId_; }
    bool                         markNativeOutputsCleared();
    bool                         setMainFunc(AstCompilerFunc* node);
    AstCompilerFunc*             mainFunc() const { return mainFunc_; }

    bool                            registerForeignLib(std::string_view name);
    const std::vector<Utf8>&        foreignLibs() const { return foreignLibs_; }
    const CompilerTag*              findCompilerTag(std::string_view name) const;
    const std::vector<CompilerTag>& compilerTags() const { return compilerTags_.all(); }
    void                            registerRuntimeFunctionSymbol(IdentifierRef idRef, SymbolFunction* symbol);
    SymbolFunction*                 runtimeFunctionSymbol(IdentifierRef idRef) const;
    bool                            tryRegisterReportedDiagnostic(std::string_view message);
    void                            registerCompilerMessageFunction(SymbolFunction* symbol, AstNodeRef nodeRef, uint64_t mask);
    void                            onSymbolSemaCompleted(Symbol& symbol);
    Result                          ensureCompilerMessagePass(Runtime::CompilerMsgKind kind);
    Result                          executePendingCompilerMessages(TaskContext& ctx);
    bool                            hasCompilerMessageInterest(Runtime::CompilerMsgKind kind) const;
    Result                          appendGeneratedSource(GeneratedSourceAppendResult& outResult, Utf8& outBecause, const fs::path& directory, std::string_view sectionText, uint32_t codeOffsetInSection);
    void                            registerInMemoryFile(fs::path path, std::string_view content);

    SourceFile&              addFile(fs::path path, FileFlags flags);
    SourceFile&              file(FileRef ref) const;
    std::vector<SourceFile*> filesSnapshot() const;

    SourceView&       addSourceView();
    SourceView&       addSourceView(FileRef fileRef);
    SourceView&       srcView(SourceViewRef ref);
    const SourceView& srcView(SourceViewRef ref) const;
    const SourceView* findSourceViewByFileName(std::string_view fileName) const;

    Result                       collectFiles(TaskContext& ctx);
    Result                       exportModuleApi(TaskContext& ctx);
    std::span<SourceFile* const> files() const;

    template<typename T, typename... ARGS>
    T* allocate(ARGS&&... args)
    {
        PerThreadData& td  = perThreadData_[JobManager::threadIndex()];
        void*          mem = td.arena.allocate(sizeof(T), alignof(T));
        return new (mem) T(std::forward<ARGS>(args)...);
    }

    template<typename T>
    T* allocateArray(size_t count)
    {
        PerThreadData& td  = perThreadData_[JobManager::threadIndex()];
        void*          mem = td.arena.allocate(sizeof(T) * count, alignof(T));
        T*             ptr = static_cast<T*>(mem);
        if constexpr (!std::is_trivially_default_constructible_v<T>)
        {
            for (size_t i = 0; i < count; ++i)
                new (ptr + i) T();
        }

        return ptr;
    }

    static bool dbgDevStop;

private:
    friend class CompilerMessageTypeInfoJob;

    struct CompilerMessageTypeInfoPrepRequest
    {
        SourceFile* listenerFile = nullptr;
        AstNodeRef  ownerNodeRef = AstNodeRef::invalid();
        TypeRef     typeRef      = TypeRef::invalid();
    };

    SourceFile& addResolvedFile(fs::path path, FileFlags flags);
    void        appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags);
    void        collectFolderFiles(const fs::path& folder, FileFlags flags, bool canFilter);
    Result      collectImportedApiFiles(const TaskContext& ctx);

    const CommandLine*                       cmdLine_ = nullptr;
    const Global*                            global_  = nullptr;
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::vector<SourceFile*>                 filePtrs_;
    std::vector<std::unique_ptr<SourceView>> srcViews_;
    std::unique_ptr<TypeManager>             typeMgr_;
    std::unique_ptr<TypeGen>                 typeGen_;
    std::unique_ptr<ConstantManager>         cstMgr_;
    std::unique_ptr<IdentifierManager>       idMgr_;
    std::unique_ptr<JITMemoryManager>        jitMemMgr_;
    std::unique_ptr<ExternalModuleManager>   externalModuleMgr_;
    SymbolModule*                            symModule_   = nullptr;
    JobClientId                              jobClientId_ = 0;
    fs::path                                 modulePathSrc_;
    fs::path                                 modulePathFile_;
    fs::path                                 exeFullName_;
    DataSegment                              constantSegment_;
    DataSegment                              globalZeroSegment_;
    DataSegment                              globalInitSegment_;
    DataSegment                              compilerSegment_;
    Runtime::BuildCfg                        buildCfg_{};
    Utf8                                     lastArtifactLabel_;
    Runtime::ICompiler                       runtimeCompiler_{};
    Runtime::CompilerMessage                 runtimeCompilerMessage_{};
    std::unique_ptr<JITExecManager>          jitExecMgr_;
    void*                                    runtimeCompilerITable_[4]{};
    mutable std::shared_mutex                mutex_;
    std::atomic<bool>                        changed_{true};
    std::mutex                               globalFunctionBindingsMutex_;
    std::atomic<uint64_t>                    globalFunctionBindingsVersion_{1};
    std::atomic<uint64_t>                    patchedGlobalFunctionBindingsVersion_{0};
    std::atomic<uint64_t>                    nativeGlobalFunctionInitTargetsVersion_{1};

    struct PerThreadData
    {
        Arena            arena;
        Runtime::Context runtimeContext{};
    };

    std::vector<PerThreadData>                            perThreadData_;
    std::atomic<uint32_t>                                 atomicId_                 = 0;
    std::atomic<uint32_t>                                 generatedSourceId_        = 0;
    std::atomic<bool>                                     nativeOutputsCleared_     = false;
    std::atomic<uint32_t>                                 pendingImplRegistrations_ = 0;
    AstCompilerFunc*                                      mainFunc_                 = nullptr;
    std::vector<Utf8>                                     foreignLibs_;
    CompilerTagRegistry                                   compilerTags_;
    std::unordered_map<IdentifierRef, SymbolFunction*>    runtimeFunctionSymbols_;
    std::unordered_map<Utf8, Utf8>                        inMemoryFiles_;
    std::mutex                                            reportedDiagnosticsMutex_;
    std::unordered_set<Utf8>                              reportedDiagnostics_;
    std::mutex                                            compilerMessageMutex_;
    std::deque<CompilerMessageListener>                   compilerMessageListeners_;
    std::vector<CompilerMessageEvent>                     compilerMessageLog_;
    std::unordered_map<TypeRef, const Runtime::TypeInfo*> compilerMessageTypeInfoCache_;
    std::unordered_set<TypeRef>                           compilerMessageTypeInfoPrepScheduled_;
    std::deque<CompilerMessageTypeInfoPrepRequest>        compilerMessageTypeInfoPrepQueue_;
    std::atomic<uint64_t>                                 compilerMessageActiveMask_            = 0;
    std::atomic<uint64_t>                                 compilerMessageExecutedPassMask_      = 0;
    std::atomic<bool>                                     compilerMessageTypeInfoPrepFailed_    = false;
    bool                                                  compilerMessageTypeInfoPrepJobQueued_ = false;
    std::once_flag                                        nativeRuntimeContextTlsIdOffsetOnce_;
    uint32_t                                              nativeRuntimeContextTlsIdOffset_ = UINT32_MAX;
    std::vector<SymbolFunction*>                          nativeCodeSegment_;
    std::vector<SymbolFunction*>                          nativeTestFunctions_;
    std::vector<SymbolFunction*>                          nativeInitFunctions_;
    std::vector<SymbolFunction*>                          nativePreMainFunctions_;
    std::vector<SymbolFunction*>                          nativeDropFunctions_;
    std::vector<SymbolFunction*>                          nativeMainFunctions_;
    std::vector<SymbolFunction*>                          nativeGlobalFunctionInitTargets_;
    std::vector<SymbolVariable*>                          nativeGlobalVariables_;
    std::vector<SymbolFunction*>                          jitPreparedFunctions_;

    SWC_RACE_CONDITION_INSTANCE(rcFiles_);

    void   logBefore();
    void   logAfter();
    void   logStats();
    void   processCommand();
    void   setupRuntimeCompiler();
    bool   tryGetCompilerMessageTypeInfo(TypeRef typeRef, const Runtime::TypeInfo*& outType);
    void   cacheCompilerMessageTypeInfo(TypeRef typeRef, const Runtime::TypeInfo* runtimeTypeInfo);
    bool   tryPopCompilerMessageTypeInfoPreparation(CompilerMessageTypeInfoPrepRequest& outRequest);
    void   markCompilerMessageTypeInfoPreparationFailed();
    void   enqueueCompilerMessageTypeInfoPreparation(TaskContext& ctx, SymbolFunction* listenerFunction, AstNodeRef ownerNodeRef, const CompilerMessageEvent& event);
    Result ensureCompilerMessageTypeInfoPrepared(TaskContext& ctx, SymbolFunction* listenerFunction, AstNodeRef ownerNodeRef, const CompilerMessageEvent& event);
    Result prepareCompilerMessageTypeInfo(Sema& sema, TypeRef typeRef, AstNodeRef ownerNodeRef);
    Result fillRuntimeCompilerMessage(Sema& sema, AstNodeRef ownerNodeRef, const CompilerMessageEvent& event);
};

SWC_END_NAMESPACE();

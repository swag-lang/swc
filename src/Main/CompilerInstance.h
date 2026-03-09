#pragma once
#include "Backend/Runtime.h"
#include "Main/ExitCodes.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Utf8.h"
#include "Support/Memory/Arena.h"
#include "Support/Thread/JobManager.h"
#include "Support/Thread/RaceCondition.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

struct AstCompilerFunc;
class SourceView;
class TaskContext;
class TypeManager;
class TypeGen;
class ConstantManager;
class IdentifierManager;
class SymbolModule;
class SymbolFunction;
class JITMemoryManager;
class ExternalModuleManager;
class Global;
class SourceFile;
class JITExecManager;
struct CommandLine;

class CompilerInstance
{
public:
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

    void                                resetNativeCodeSegment();
    void                                addNativeCodeFunction(SymbolFunction* symbol);
    void                                addNativeTestFunction(SymbolFunction* symbol);
    void                                addNativeInitFunction(SymbolFunction* symbol);
    void                                addNativePreMainFunction(SymbolFunction* symbol);
    void                                addNativeDropFunction(SymbolFunction* symbol);
    void                                addNativeMainFunction(SymbolFunction* symbol);
    const std::vector<SymbolFunction*>& nativeCodeSegment() const { return nativeCodeSegment_; }
    const std::vector<SymbolFunction*>& nativeTestFunctions() const { return nativeTestFunctions_; }
    const std::vector<SymbolFunction*>& nativeInitFunctions() const { return nativeInitFunctions_; }
    const std::vector<SymbolFunction*>& nativePreMainFunctions() const { return nativePreMainFunctions_; }
    const std::vector<SymbolFunction*>& nativeDropFunctions() const { return nativeDropFunctions_; }
    const std::vector<SymbolFunction*>& nativeMainFunctions() const { return nativeMainFunctions_; }

    void setupSema(TaskContext& ctx);
    void notifyAlive() { changed_ = true; }
    bool changed() const { return changed_; }
    void clearChanged() { changed_ = false; }

    uint32_t pendingImplRegistrations() const;
    void     incPendingImplRegistrations();
    void     decPendingImplRegistrations();

    std::atomic<uint32_t>&       atomicId() { return atomicId_; }
    const std::atomic<uint32_t>& atomicId() const { return atomicId_; }
    bool                         setMainFunc(AstCompilerFunc* node);
    AstCompilerFunc*             mainFunc() const { return mainFunc_; }

    bool                     registerForeignLib(std::string_view name);
    const std::vector<Utf8>& foreignLibs() const { return foreignLibs_; }
    void                     registerRuntimeFunctionSymbol(IdentifierRef idRef, SymbolFunction* symbol);
    SymbolFunction*          runtimeFunctionSymbol(IdentifierRef idRef) const;

    SourceFile& addFile(fs::path path, FileFlags flags);
    SourceFile& file(FileRef ref) const { return *(files_[ref.get()].get()); }

    SourceView&       addSourceView();
    SourceView&       addSourceView(FileRef fileRef);
    SourceView&       srcView(SourceViewRef ref);
    const SourceView& srcView(SourceViewRef ref) const;
    const SourceView* findSourceViewByFileName(std::string_view fileName) const;

    Result                   collectFiles(TaskContext& ctx);
    std::vector<SourceFile*> files() const;

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

    static bool dbgDevMode;

private:
    const CommandLine*                       cmdLine_ = nullptr;
    const Global*                            global_  = nullptr;
    std::vector<std::unique_ptr<SourceFile>> files_;
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
    Runtime::ICompiler                       runtimeCompiler_{};
    Runtime::CompilerMessage                 runtimeCompilerMessage_{};
    std::unique_ptr<JITExecManager>          jitExecMgr_;
    void*                                    runtimeCompilerITable_[3]{};
    mutable std::shared_mutex                mutex_;
    bool                                     changed_ = true;

    struct PerThreadData
    {
        Arena            arena;
        Runtime::Context runtimeContext{};
    };

    std::vector<PerThreadData>                         perThreadData_;
    std::atomic<uint32_t>                              atomicId_                 = 0;
    std::atomic<uint32_t>                              pendingImplRegistrations_ = 0;
    AstCompilerFunc*                                   mainFunc_                 = nullptr;
    std::vector<Utf8>                                  foreignLibs_;
    std::unordered_map<IdentifierRef, SymbolFunction*> runtimeFunctionSymbols_;
    std::once_flag                                     nativeRuntimeContextTlsIdOffsetOnce_;
    uint32_t                                           nativeRuntimeContextTlsIdOffset_ = UINT32_MAX;
    std::vector<SymbolFunction*>                       nativeCodeSegment_;
    std::vector<SymbolFunction*>                       nativeTestFunctions_;
    std::vector<SymbolFunction*>                       nativeInitFunctions_;
    std::vector<SymbolFunction*>                       nativePreMainFunctions_;
    std::vector<SymbolFunction*>                       nativeDropFunctions_;
    std::vector<SymbolFunction*>                       nativeMainFunctions_;

    SWC_RACE_CONDITION_INSTANCE(rcFiles_);

    void logBefore();
    void logAfter();
    void logStats();
    void processCommand();
    void setupRuntimeCompiler();
};

SWC_END_NAMESPACE();

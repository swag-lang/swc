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
class JITMemoryManager;
class ExternalModuleManager;
class Global;
class SourceFile;
struct CommandLine;

class CompilerInstance
{
public:
    CompilerInstance(const Global& global, const CommandLine& cmdLine);
    ~CompilerInstance();

    ExitCode run();

    const Global&                global() const { return *SWC_CHECK_NOT_NULL(global_); }
    const CommandLine&           cmdLine() const { return *SWC_CHECK_NOT_NULL(cmdLine_); }
    JobClientId                  jobClientId() const { return jobClientId_; }
    TypeManager&                 typeMgr() { return *SWC_CHECK_NOT_NULL(typeMgr_.get()); }
    const TypeManager&           typeMgr() const { return *SWC_CHECK_NOT_NULL(typeMgr_.get()); }
    TypeGen&                     typeGen() { return *SWC_CHECK_NOT_NULL(typeGen_.get()); }
    const TypeGen&               typeGen() const { return *SWC_CHECK_NOT_NULL(typeGen_.get()); }
    ConstantManager&             cstMgr() { return *SWC_CHECK_NOT_NULL(cstMgr_.get()); }
    const ConstantManager&       cstMgr() const { return *SWC_CHECK_NOT_NULL(cstMgr_.get()); }
    IdentifierManager&           idMgr() { return *SWC_CHECK_NOT_NULL(idMgr_.get()); }
    const IdentifierManager&     idMgr() const { return *SWC_CHECK_NOT_NULL(idMgr_.get()); }
    DataSegment&                 constantSegment() { return constantSegment_; }
    const DataSegment&           constantSegment() const { return constantSegment_; }
    DataSegment&                 compilerSegment() { return compilerSegment_; }
    const DataSegment&           compilerSegment() const { return compilerSegment_; }
    Runtime::BuildCfg&           buildCfg() { return buildCfg_; }
    const Runtime::BuildCfg&     buildCfg() const { return buildCfg_; }
    Runtime::ICompiler&          runtimeCompiler() { return runtimeCompiler_; }
    const Runtime::ICompiler&    runtimeCompiler() const { return runtimeCompiler_; }
    JITMemoryManager&        jitMemMgr() { return *SWC_CHECK_NOT_NULL(jitMemMgr_.get()); }
    const JITMemoryManager&  jitMemMgr() const { return *SWC_CHECK_NOT_NULL(jitMemMgr_.get()); }
    ExternalModuleManager&       externalModuleMgr() { return *SWC_CHECK_NOT_NULL(externalModuleMgr_.get()); }
    const ExternalModuleManager& externalModuleMgr() const { return *SWC_CHECK_NOT_NULL(externalModuleMgr_.get()); }

    SymbolModule*       symModule() { return symModule_; }
    const SymbolModule* symModule() const { return symModule_; }

    void setupSema(TaskContext& ctx);
    void notifyAlive() { changed_ = true; }
    bool changed() const { return changed_; }
    void clearChanged() { changed_ = false; }

    uint32_t pendingImplRegistrations() const;
    void     incPendingImplRegistrations();
    void     decPendingImplRegistrations();

    std::atomic<uint32_t>& atomicId() const { return const_cast<CompilerInstance*>(this)->atomicId_; }
    bool                   setMainFunc(AstCompilerFunc* node);
    AstCompilerFunc*       mainFunc() const { return mainFunc_; }

    bool                     registerForeignLib(std::string_view name);
    const std::vector<Utf8>& foreignLibs() const { return foreignLibs_; }

    SourceFile& addFile(fs::path path, FileFlags flags);
    SourceFile& file(FileRef ref) const { return *SWC_CHECK_NOT_NULL(files_[ref.get()].get()); }

    SourceView&       addSourceView();
    SourceView&       addSourceView(FileRef fileRef);
    SourceView&       srcView(SourceViewRef ref) { return *SWC_CHECK_NOT_NULL(srcViews_[ref.get()].get()); }
    const SourceView& srcView(SourceViewRef ref) const { return *SWC_CHECK_NOT_NULL(srcViews_[ref.get()].get()); }

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

private:
    const CommandLine*                       cmdLine_ = nullptr;
    const Global*                            global_  = nullptr;
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::vector<std::unique_ptr<SourceView>> srcViews_;
    std::unique_ptr<TypeManager>             typeMgr_;
    std::unique_ptr<TypeGen>                 typeGen_;
    std::unique_ptr<ConstantManager>         cstMgr_;
    std::unique_ptr<IdentifierManager>       idMgr_;
    std::unique_ptr<JITMemoryManager>    jitMemMgr_;
    std::unique_ptr<ExternalModuleManager>   externalModuleMgr_;
    SymbolModule*                            symModule_   = nullptr;
    JobClientId                              jobClientId_ = 0;
    fs::path                                 modulePathSrc_;
    fs::path                                 modulePathFile_;
    fs::path                                 exeFullName_;
    DataSegment                              constantSegment_;
    DataSegment                              compilerSegment_;
    Runtime::BuildCfg                        buildCfg_{};
    Runtime::ICompiler                       runtimeCompiler_{};
    Runtime::CompilerMessage                 runtimeCompilerMessage_{};
    void*                                    runtimeCompilerITable_[3]{};
    std::mutex                               mutex_;
    bool                                     changed_ = true;

    struct PerThreadData
    {
        Arena arena;
    };

    std::vector<PerThreadData> perThreadData_;
    std::atomic<uint32_t>      atomicId_                 = 0;
    std::atomic<uint32_t>      pendingImplRegistrations_ = 0;
    AstCompilerFunc*           mainFunc_                 = nullptr;
    std::vector<Utf8>          foreignLibs_;

    SWC_RACE_CONDITION_INSTANCE(rcFiles_);

    void logBefore();
    void logAfter();
    void logStats();
    void processCommand();
    void setupRuntimeCompiler();
};

SWC_END_NAMESPACE();

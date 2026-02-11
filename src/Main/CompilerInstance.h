#pragma once
#include "Main/ExitCodes.h"
#include "Runtime/Runtime.h"
#include "Support/Core/Utf8.h"
#include "Support/Memory/Arena.h"
#include "Support/Thread/JobManager.h"
#include "Support/Thread/RaceCondition.h"
#include "Wmf/Module.h"
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
class Global;
class SourceFile;
struct CommandLine;

class CompilerInstance
{
public:
    CompilerInstance(const Global& global, const CommandLine& cmdLine);
    ~CompilerInstance();

    ExitCode run();

    const Global&            global() const { return *global_; }
    const CommandLine&       cmdLine() const { return *cmdLine_; }
    JobClientId              jobClientId() const { return jobClientId_; }
    TypeManager&             typeMgr() { return *typeMgr_; }
    const TypeManager&       typeMgr() const { return *typeMgr_; }
    TypeGen&                 typeGen() { return *typeGen_; }
    const TypeGen&           typeGen() const { return *typeGen_; }
    ConstantManager&         cstMgr() { return *cstMgr_; }
    const ConstantManager&   cstMgr() const { return *cstMgr_; }
    IdentifierManager&       idMgr() { return *idMgr_; }
    const IdentifierManager& idMgr() const { return *idMgr_; }
    Module&                  module() { return module_; }
    const Module&            module() const { return module_; }
    Runtime::BuildCfg&       buildCfg() { return buildCfg_; }
    const Runtime::BuildCfg& buildCfg() const { return buildCfg_; }

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

    bool                       registerForeignLib(std::string_view name);
    const std::vector<Utf8>&   foreignLibs() const { return foreignLibs_; }

    SourceFile& addFile(fs::path path, FileFlags flags);
    SourceFile& file(FileRef ref) const { return *files_[ref.get()].get(); }

    SourceView&       addSourceView();
    SourceView&       addSourceView(FileRef fileRef);
    SourceView&       srcView(SourceViewRef ref) { return *srcViews_[ref.get()].get(); }
    const SourceView& srcView(SourceViewRef ref) const { return *srcViews_[ref.get()].get(); }

    Result                   collectFiles(TaskContext& ctx);
    std::vector<SourceFile*> files() const;

    template<typename T, typename... ARGS>
    T* allocate(ARGS&&... args)
    {
        auto& td  = perThreadData_[JobManager::threadIndex()];
        void* mem = td.arena.allocate(sizeof(T), alignof(T));
        return new (mem) T(std::forward<ARGS>(args)...);
    }

    template<typename T>
    T* allocateArray(size_t count)
    {
        auto& td  = perThreadData_[JobManager::threadIndex()];
        void* mem = td.arena.allocate(sizeof(T) * count, alignof(T));
        T*    ptr = static_cast<T*>(mem);
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
    SymbolModule*                            symModule_   = nullptr;
    JobClientId                              jobClientId_ = 0;
    fs::path                                 modulePathSrc_;
    fs::path                                 modulePathFile_;
    fs::path                                 exeFullName_;
    Module                                   module_;
    Runtime::BuildCfg                        buildCfg_{};
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
};

SWC_END_NAMESPACE();

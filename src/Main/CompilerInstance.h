#pragma once
#include "Core/StrongRef.h"
#include "Report/ExitCodes.h"
#include "Thread/RaceCondition.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()
class SourceView;
class TaskContext;
class TypeManager;
class ConstantManager;
class IdentifierManager;
class SymbolModule;
class Global;
class SourceFile;
struct CommandLine;
using JobClientId = uint32_t;

class CompilerInstance
{
    const CommandLine*                       cmdLine_ = nullptr;
    const Global*                            global_  = nullptr;
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::vector<std::unique_ptr<SourceView>> srcViews_;
    std::unique_ptr<TypeManager>             typeMgr_;
    std::unique_ptr<ConstantManager>         cstMgr_;
    std::unique_ptr<IdentifierManager>       idMgr_;
    std::unique_ptr<SymbolModule>            symModule_;
    JobClientId                              jobClientId_ = 0;
    fs::path                                 modulePathSrc_;
    fs::path                                 modulePathFile_;
    fs::path                                 exeFullName_;

    std::mutex mutex_;
    SWC_RACE_CONDITION_INSTANCE(rcFiles_);

    void logBefore();
    void logAfter();
    void logStats();
    void processCommand();

public:
    CompilerInstance(const Global& global, const CommandLine& cmdLine);
    ~CompilerInstance();

    ExitCode run();

    const Global&            global() const { return *global_; }
    const CommandLine&       cmdLine() const { return *cmdLine_; }
    JobClientId              jobClientId() const { return jobClientId_; }
    TypeManager&             typeMgr() { return *typeMgr_; }
    const TypeManager&       typeMgr() const { return *typeMgr_; }
    ConstantManager&         cstMgr() { return *cstMgr_; }
    const ConstantManager&   cstMgr() const { return *cstMgr_; }
    IdentifierManager&       idMgr() { return *idMgr_; }
    const IdentifierManager& idMgr() const { return *idMgr_; }

    SymbolModule&       symModule() { return *symModule_; }
    const SymbolModule& symModule() const { return *symModule_; }

    void setupSema(TaskContext& ctx);

    SourceFile& addFile(fs::path path, FileFlags flags);
    SourceFile& file(FileRef ref) const { return *files_[ref.get()].get(); }

    SourceView& addSourceView();
    SourceView& addSourceView(FileRef fileRef);
    SourceView& srcView(SourceViewRef ref) const { return *srcViews_[ref.get()].get(); }

    Result                   collectFiles(TaskContext& ctx);
    std::vector<SourceFile*> files() const;
};

SWC_END_NAMESPACE()

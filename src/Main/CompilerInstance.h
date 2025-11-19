#pragma once
#include "Report/ExitCodes.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class TypeManager;
class ConstantManager;
class Global;
class SourceFile;
struct CommandLine;
using JobClientId = uint32_t;

class CompilerInstance
{
    const CommandLine*                       cmdLine_ = nullptr;
    const Global*                            global_  = nullptr;
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::unique_ptr<TypeManager>             typeMgr_;
    std::unique_ptr<ConstantManager>         constMgr_;
    JobClientId                              jobClientId_ = 0;
    fs::path                                 modulePathSrc_;
    fs::path                                 modulePathFile_;
    fs::path                                 exeFullName_;

    void logBefore();
    void logAfter();
    void logStats();
    void processCommand();

public:
    CompilerInstance(const Global& global, const CommandLine& cmdLine);
    ~CompilerInstance();

    ExitCode run();

    const Global&          global() const { return *global_; }
    const CommandLine&     cmdLine() const { return *cmdLine_; }
    JobClientId            jobClientId() const { return jobClientId_; }
    TypeManager&           typeMgr() { return *typeMgr_; }
    const TypeManager&     typeMgr() const { return *typeMgr_; }
    ConstantManager&       constMgr() { return *constMgr_; }
    const ConstantManager& constMgr() const { return *constMgr_; }

    FileRef                  addFile(fs::path path, FileFlags flags);
    Result                   collectFiles(const TaskContext& ctx);
    std::vector<SourceFile*> files() const;
    SourceFile*              file(FileRef ref) const { return files_[ref.get()].get(); }
};

SWC_END_NAMESPACE()

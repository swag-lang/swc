#pragma once
#include "Report/ExitCodes.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;

using JobClientId = uint32_t;
class Global;
class SourceFile;
struct CommandLine;

class CompilerInstance
{
    const CommandLine*                       cmdLine_ = nullptr;
    const Global*                            global_  = nullptr;
    std::vector<std::unique_ptr<SourceFile>> files_;
    JobClientId                              jobClientId_ = 0;
    fs::path                                 modulePathSrc_;
    fs::path                                 modulePathFile_;

    void logBefore();
    void logAfter();
    void logStats();
    void processCommand();

public:
    CompilerInstance(const Global& global, const CommandLine& cmdLine);
    ~CompilerInstance();

    ExitCode run();

    const Global&      global() const { return *global_; }
    const CommandLine& cmdLine() const { return *cmdLine_; }
    JobClientId        jobClientId() const { return jobClientId_; }

    FileRef                  addFile(fs::path path, FileFlags flags);
    Result                   collectFiles(const TaskContext& ctx);
    std::vector<SourceFile*> files() const;
    SourceFile*              file(FileRef ref) const { return files_[ref.get()].get(); }
};

SWC_END_NAMESPACE()

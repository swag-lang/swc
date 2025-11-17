#pragma once
#include "Main/FileManager.h"

SWC_BEGIN_NAMESPACE()

using JobClientId = uint32_t;
struct CommandLine;
class Global;

class CompilerContext
{
    const CommandLine* cmdLine_ = nullptr;
    const Global*      global_  = nullptr;
    FileManager        fileManager_;
    JobClientId        jobClientId_ = 0;

public:
    explicit CompilerContext(const Global& global, const CommandLine& cmdLine) :
        cmdLine_(&cmdLine),
        global_(&global)
    {
    }

    const Global&      global() const { return *global_; }
    const CommandLine& cmdLine() const { return *cmdLine_; }
    JobClientId        jobClientId() const { return jobClientId_; }
    void               setJobClientId(JobClientId clientId) { jobClientId_ = clientId; }
    FileManager&       fileMgr() { return fileManager_; }
    const FileManager& fileMgr() const { return fileManager_; }
};

SWC_END_NAMESPACE()

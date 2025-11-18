#pragma once
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;
class SourceFile;

class TaskContext
{
    CompilerInstance* compilerInstance_ = nullptr;
    bool              silentError_      = false;

public:
    explicit TaskContext(CompilerInstance& compInst) :
        compilerInstance_(&compInst)
    {
    }

    const Global&      global() const { return compilerInstance_->global(); }
    const CommandLine& cmdLine() const { return compilerInstance_->cmdLine(); }
    bool               silentError() const { return silentError_; }
    void               setSilentError(bool silent) { silentError_ = silent; }
};

SWC_END_NAMESPACE()

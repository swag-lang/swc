#pragma once
#include "Main/CompilerContext.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;
class SourceFile;

class TaskContext
{
    const CompilerContext* compilerContext_ = nullptr;
    bool                   silentError_     = false;

public:
    explicit TaskContext(const CompilerContext& compContext) :
        compilerContext_(&compContext)
    {
    }

    const Global&      global() const { return compilerContext_->global(); }
    const CommandLine& cmdLine() const { return compilerContext_->cmdLine(); }
    bool               silentError() const { return silentError_; }
    void               setSilentError(bool silent) { silentError_ = silent; }
};

SWC_END_NAMESPACE()

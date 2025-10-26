#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

struct CommandLine;
class Global;

class CompilerContext
{
    friend class CompilerInstance;
    const CommandLine* cmdLine_     = nullptr;
    const Global*      global_      = nullptr;
    JobClientId        jobClientId_ = 0;

public:
    explicit CompilerContext(const CommandLine& cmdLine, const Global& global) :
        cmdLine_(&cmdLine),
        global_(&global)
    {
    }

    const Global&      global() const { return *global_; }
    const CommandLine& cmdLine() const { return *cmdLine_; }
    JobClientId        jobClientId() const { return jobClientId_; }
};

SWC_END_NAMESPACE();

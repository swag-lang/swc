#pragma once

SWC_BEGIN_NAMESPACE()

using JobClientId = uint32_t;
struct CommandLine;
class Global;

class CompilerContext
{
    friend class CompilerInstance;
    const CommandLine* cmdLine_     = nullptr;
    const Global*      global_      = nullptr;
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
};

SWC_END_NAMESPACE()

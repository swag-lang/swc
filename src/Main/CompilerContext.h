#pragma once

SWC_BEGIN_NAMESPACE()

struct CommandLine;
class Global;
using JobClientId = uint64_t;

class CompilerContext
{
    friend class Compiler;
    const CommandLine& cmdLine_;
    const Global&      global_;
    JobClientId        clientId_;

public:
    explicit CompilerContext(const CommandLine& cmdLine, const Global& global) :
        cmdLine_(cmdLine),
        global_(global)
    {
    }

    const Global&      global() const { return global_; }
    const CommandLine& cmdLine() const { return cmdLine_; }
};

SWC_END_NAMESPACE()

#pragma once
#include "Main/CompilerContext.h"
#include "Report/ExitCodes.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;

class CompilerInstance
{
    CompilerContext context_;
    void            logBefore() const;
    void            logAfter() const;
    void            logStats() const;
    void            processCommand();

public:
    CompilerInstance(const CommandLine& cmdLine, const Global& global);
    ExitCode run();

    CompilerContext&       context() { return context_; }
    const CompilerContext& context() const { return context_; }
};

SWC_END_NAMESPACE()

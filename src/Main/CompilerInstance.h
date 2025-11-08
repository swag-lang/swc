#pragma once
#include "Main/CompilerContext.h"
#include "Report/ExitCodes.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;

class CompilerInstance
{
    CompilerContext context_;

    Result cmdSyntax();

    void logBefore() const;
    void logAfter() const;
    void logStats() const;
    void processCommand();

public:
    CompilerInstance(const CommandLine& cmdLine, const Global& global);
    ExitCode run();
};

SWC_END_NAMESPACE()

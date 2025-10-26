#pragma once
#include "Main/CompilerContext.h"

SWC_BEGIN_NAMESPACE();

class Global;
struct CommandLine;

class CompilerInstance
{
    CompilerContext context_;

    Result cmdSyntax();

public:
    CompilerInstance(const CommandLine& cmdLine, const Global& global);
    int run();
};

SWC_END_NAMESPACE();

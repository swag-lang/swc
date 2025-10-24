#pragma once
#include "Main/CompilerContext.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;

class Compiler
{
    CompilerContext context_;

    void test() const;

public:
    Compiler(const CommandLine& cmdLine, const Global& global);
    int run() const;
};

SWC_END_NAMESPACE()

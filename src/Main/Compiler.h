#pragma once
#include "Global.h"
#include "Main/CommandLine.h"

class Compiler
{
    const CommandLine& cmdLine_;
    Global&            global_;

    void test();

public:
    Compiler(const CommandLine& cmdLine, Global& global) :
        cmdLine_(cmdLine),
        global_(global)
    {
    }

    const CommandLine& cmdLine() const { return cmdLine_; }
    Global&            global() { return global_; }
    const Global&      global() const { return global_; }

    int run();
};

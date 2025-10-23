#pragma once
#include "Main/CommandLine.h"

class Swc
{
    CommandLine cmdLine_;

    void test();
    int  process(int argc, char* argv[]);

public:
    CommandLine&       cmdLine() { return cmdLine_; }
    const CommandLine& cmdLine() const { return cmdLine_; }

    int run(int argc, char* argv[]);
};

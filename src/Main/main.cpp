#include "pch.h"

#include "Main/CommandLineParser.h"
#include "Main/Global.h"
#include "Main/Compiler.h"

int main(int argc, char* argv[])
{
    CommandLine       cmdLine;
    CommandLineParser parser(cmdLine);
    parser.setupCommandLine();
    if (!parser.parse(argc, argv, "build"))
        return -1;

    Global global;
    global.initialize(cmdLine);

    Compiler compiler(cmdLine, global);
    return compiler.run();
}

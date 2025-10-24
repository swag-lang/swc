#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/Compiler.h"
#include "Main/Global.h"

int main(int argc, char* argv[])
{
    swc::Global            global;
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(cmdLine, global);
    if (!parser.parse(argc, argv))
        return -1;

    global.initialize(cmdLine);

    swc::Compiler compiler(cmdLine, global);
    return compiler.run();
}

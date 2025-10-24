#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/Compiler.h"
#include "Main/Global.h"

int main(int argc, char* argv[])
{
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(cmdLine);
    if (!parser.parse(argc, argv))
        return -1;

    swc::Global global;
    global.initialize(cmdLine);

    swc::Compiler compiler(cmdLine, global);
    return compiler.run();
}

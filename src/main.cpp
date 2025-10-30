#include "pch.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Report/ExitCodes.h"

int main(int argc, char* argv[])
{
    swc::Global            global;
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(cmdLine, global);
    if (parser.parse(argc, argv) != swc::Result::Success)
        return static_cast<int>(swc::ExitCode::ErrorCmdLine);

    global.initialize(cmdLine);

    swc::CompilerInstance compiler(cmdLine, global);
    return static_cast<int>(compiler.run());
}

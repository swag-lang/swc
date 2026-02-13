#include "pch.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Support/Report/Logger.h"
#include "Support/Unittest/Unittest.h"

int main(int argc, char* argv[])
{
    swc::Global            global;
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(global, cmdLine);
    if (parser.parse(argc, argv) != swc::Result::Continue)
        return static_cast<int>(swc::ExitCode::ErrorCmdLine);

    global.initialize(cmdLine);

#if SWC_HAS_UNITTEST
    swc::TaskContext ctx(global, cmdLine);
    if (swc::Unittest::runAll(ctx) != swc::Result::Continue)
    {
        swc::Logger::print(ctx, "[unittest] failure detected\n");
        return static_cast<int>(swc::ExitCode::ErrorCommand);
    }
#endif

    swc::CompilerInstance compiler(global, cmdLine);
    return static_cast<int>(compiler.run());
}

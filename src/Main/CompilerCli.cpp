#include "pch.h"
#include "Main/CompilerCli.h"
#include "Backend/Micro/MicroOptimizerStats.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"
#if SWC_HAS_UNITTEST
#include "Unittest/Unittest.h"
#endif

SWC_BEGIN_NAMESPACE();

ExitCode runCompilerCli(const int argc, char* argv[])
{
    // Diagnostics name files relative to the launch directory; fix it before anything runs.
    (void) FileSystem::displayRoot();

    Global            global;
    CommandLine       cmdLine;
    CommandLineParser parser(global, cmdLine);
    if (parser.parse(argc, argv) != Result::Continue)
        return ExitCode::ErrorCmdLine;
    if (cmdLine.helpPrinted)
        return ExitCode::Success;

    if (cmdLine.command == CommandKind::Info)
    {
        const TaskContext ctx(global, cmdLine);
        Command::info(ctx);
        return ExitCode::Success;
    }

    global.initialize(cmdLine);
    TaskContext            startupCtx(global, cmdLine);
    ExitCode               result = ExitCode::ErrorCommand;
    const ScopedCommandLog commandLog(startupCtx, result);

    if (cmdLine.command == CommandKind::New)
    {
        result = Command::createProject(startupCtx) == Result::Continue ? ExitCode::Success : ExitCode::ErrorCommand;
        return result;
    }

    // Cleaning needs no input collection, module setup, or scheduler work.
    if (cmdLine.command == CommandKind::Clean)
    {
        result = Command::clean(startupCtx) == Result::Continue ? ExitCode::Success : ExitCode::ErrorCommand;
        return result;
    }

#if SWC_HAS_UNITTEST
    if (cmdLine.command == CommandKind::Unittest && !cmdLine.dryRun && !cmdLine.showConfig)
    {
        result = Unittest::runAll(startupCtx) == Result::Continue ? ExitCode::Success : ExitCode::ErrorCommand;
        return result;
    }
#endif

    {
        CompilerInstance compiler(global, cmdLine);
        result = compiler.run();
        if (compiler.optimizerStats())
            compiler.optimizerStats()->print(startupCtx);
    }

#if SWC_DEV_MODE
    if (cmdLine.devSchedStats)
        global.jobMgr().printStats(startupCtx);
#endif
    return result;
}

SWC_END_NAMESPACE();

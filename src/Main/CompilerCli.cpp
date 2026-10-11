#include "pch.h"
#include "Main/CompilerCli.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/EditorIndex.h"
#include "Main/EditorService.h"
#include "Main/ExitCodes.h"
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
    Global            global;
    CommandLine       cmdLine;
    CommandLineParser parser(global, cmdLine);
    if (parser.parse(argc, argv) != Result::Continue)
        return ExitCode::ErrorCmdLine;
    if (cmdLine.helpPrinted)
        return ExitCode::Success;

    global.initialize(cmdLine);
    TaskContext            startupCtx(global, cmdLine);
    const ScopedCommandLog commandLog(startupCtx);

    if (cmdLine.command == CommandKind::New)
    {
        const Result result = Command::createProject(startupCtx);
        return result == Result::Continue ? ExitCode::Success : ExitCode::ErrorCommand;
    }

    // Cleaning needs no input collection, module setup, or scheduler work.
    if (cmdLine.command == CommandKind::Clean)
    {
        const Result result = Command::clean(startupCtx);
        return result == Result::Continue ? ExitCode::Success : ExitCode::ErrorCommand;
    }

#if SWC_HAS_UNITTEST
    if (cmdLine.command == CommandKind::Unittest && !cmdLine.dryRun && !cmdLine.showConfig)
    {
        if (Unittest::runAll(startupCtx) != Result::Continue)
            return ExitCode::ErrorCommand;
        return ExitCode::Success;
    }
#endif

    if (!isEditorServiceCommand(cmdLine.command) && EditorIndex::loadOverlays(cmdLine) != Result::Continue)
        return ExitCode::ErrorCmdLine;

    ExitCode result;
    if (isEditorServiceCommand(cmdLine.command))
        result = runEditorService(global, cmdLine);
    else
    {
        CompilerInstance compiler(global, cmdLine);
        result = compiler.run();
        if (!cmdLine.editorIndex.empty() && EditorIndex::write(compiler) != Result::Continue)
            result = ExitCode::ErrorCommand;
    }

#if SWC_DEV_MODE
    if (cmdLine.devSchedStats)
        global.jobMgr().printStats(startupCtx);
#endif
    return result;
}

SWC_END_NAMESPACE();

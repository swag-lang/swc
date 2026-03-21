#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    CommandLine makeStageLogCmdLine(const TaskContext& ctx, const bool ascii = false)
    {
        CommandLine cmdLine = ctx.cmdLine();
        cmdLine.command     = CommandKind::Build;
        cmdLine.logAscii    = ascii;
        cmdLine.name        = "stage_log";
        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }
}

SWC_TEST_BEGIN(StageLog_FunAsciiLineStaysAsciiFriendly)
{
    CommandLine      cmdLine = makeStageLogCmdLine(ctx, true);
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      logCtx(compiler);

    const TimedActionLog::StageSpec spec{
        .key    = "build",
        .label  = "Build",
        .verb   = "forging native artifact",
        .detail = "hello.exe",
    };

    TimedActionLog::StatsSnapshot before;
    TimedActionLog::StatsSnapshot after;

    const Utf8 startLine = TimedActionLog::formatStageStartLine(logCtx, spec, 1);
    const Utf8 endLine   = TimedActionLog::formatStageEndLine(logCtx, spec, 1, TimedActionLog::StageOutcome::Success, before, after, 42000000ULL);

    if (!startLine.contains(">"))
        return Result::Error;
    if (!endLine.contains("*"))
        return Result::Error;
    if (startLine.contains("\xE2") || endLine.contains("\xE2"))
        return Result::Error;
    if (!endLine.contains("42ms") && !endLine.contains("42 ms"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(StageLog_SummaryEndsWithBlankLine)
{
    const CommandLine cmdLine = makeStageLogCmdLine(ctx);
    CompilerInstance  compiler(ctx.global(), cmdLine);
    const TaskContext logCtx(compiler);

    TimedActionLog::StatsSnapshot snapshot;
    snapshot.timeTotal = 42000000ULL;

    const Utf8 line = TimedActionLog::formatSummaryLine(logCtx, snapshot);
    if (line.size() < 2 || line[line.size() - 2] != '\n' || line[line.size() - 1] != '\n')
        return Result::Error;
    if (!line.contains("Landed"))
        return Result::Error;
    if (!line.contains("clean"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

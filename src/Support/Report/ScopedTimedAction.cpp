#include "pch.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Backend/Runtime.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/LogSymbol.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t ACTION_LABEL_WIDTH = 8;

    Utf8 buildCfgBackendKindName(const Runtime::BuildCfgBackendKind value)
    {
        switch (value)
        {
            case Runtime::BuildCfgBackendKind::Executable:
                return "exe";
            case Runtime::BuildCfgBackendKind::Library:
                return "dll";
            case Runtime::BuildCfgBackendKind::Export:
                return "lib";
            case Runtime::BuildCfgBackendKind::None:
                return "none";
        }

        SWC_UNREACHABLE();
    }

    TimedActionLog::StageOutcome classifyOutcome(const TimedActionLog::StatsSnapshot& before, const TimedActionLog::StatsSnapshot& after)
    {
        if (after.numErrors > before.numErrors)
            return TimedActionLog::StageOutcome::Error;
        if (after.numWarnings > before.numWarnings)
            return TimedActionLog::StageOutcome::Warning;
        return TimedActionLog::StageOutcome::Success;
    }

    TimedActionLog::StageOutcome mergeOutcome(const TimedActionLog::StageOutcome lhs, const TimedActionLog::StageOutcome rhs)
    {
        return static_cast<int>(lhs) >= static_cast<int>(rhs) ? lhs : rhs;
    }

    LogColor outcomeColor(const TimedActionLog::StageOutcome outcome)
    {
        switch (outcome)
        {
            case TimedActionLog::StageOutcome::Success:
                return LogColor::BrightGreen;
            case TimedActionLog::StageOutcome::Warning:
                return LogColor::BrightYellow;
            case TimedActionLog::StageOutcome::Error:
                return LogColor::BrightRed;
        }

        SWC_UNREACHABLE();
    }

    LogColor stageColor(const std::string_view key)
    {
        if (key == "config")
            return LogColor::BrightBlue;
        if (key == "syntax")
            return LogColor::BrightCyan;
        if (key == "sema")
            return LogColor::BrightBlue;
        if (key == "jit")
            return LogColor::BrightMagenta;
        if (key == "micro")
            return LogColor::BrightMagenta;
        if (key == "verify")
            return LogColor::BrightCyan;
        if (key == "run")
            return LogColor::BrightGreen;
        return LogColor::BrightYellow;
    }

    LogColor stageOutcomeColor(const TimedActionLog::StageSpec& spec, const TimedActionLog::StageOutcome outcome)
    {
        if (outcome == TimedActionLog::StageOutcome::Success)
            return stageColor(spec.key);

        return outcomeColor(outcome);
    }

    Utf8 stageStartGlyph(const TaskContext& ctx)
    {
        return LogSymbolHelper::toString(ctx, LogSymbol::DotCenter);
    }

    Utf8 stageOutcomeGlyph(const TaskContext& ctx, const TimedActionLog::StageOutcome outcome)
    {
        switch (outcome)
        {
            case TimedActionLog::StageOutcome::Success:
                return LogSymbolHelper::toString(ctx, LogSymbol::Check);
            case TimedActionLog::StageOutcome::Warning:
                return LogSymbolHelper::toString(ctx, LogSymbol::Warning);
            case TimedActionLog::StageOutcome::Error:
                return LogSymbolHelper::toString(ctx, LogSymbol::Error);
        }

        SWC_UNREACHABLE();
    }

    Utf8 colorize(const TaskContext& ctx, LogColor color, std::string_view text);

    Utf8 joinParts(const TaskContext& ctx, const std::vector<Utf8>& parts, const LogColor partColor)
    {
        Utf8       result;
        const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        bool       first  = true;
        for (const Utf8& part : parts)
        {
            if (part.empty())
                continue;

            if (!first)
            {
                result += " ";
                result += colorize(ctx, LogColor::Gray, bullet);
                result += LogColorHelper::toAnsi(ctx, partColor);
                result += " ";
            }
            result += part;
            first = false;
        }

        return result;
    }

    Utf8 colorize(const TaskContext& ctx, const LogColor color, const std::string_view text)
    {
        Utf8 result;
        result += LogColorHelper::toAnsi(ctx, color);
        result += text;
        return result;
    }

    Utf8 resetColor(const TaskContext& ctx)
    {
        return LogColorHelper::toAnsi(ctx, LogColor::Reset);
    }

    void appendStageText(Utf8& line, const TaskContext& ctx, const TimedActionLog::StageSpec& spec)
    {
        const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        line += colorize(ctx, stageColor(spec.key), std::format("{:<{}}", spec.label, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, LogColor::White, spec.verb);
        if (!spec.detail.empty())
        {
            line += " ";
            line += colorize(ctx, LogColor::Gray, bullet);
            line += " ";
            line += colorize(ctx, LogColor::Gray, spec.detail);
        }
    }

    Utf8 formatStageStart(const TaskContext& ctx, const TimedActionLog::StageSpec& spec)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(spec.key), stageStartGlyph(ctx));
        line += "  ";
        appendStageText(line, ctx, spec);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatCompletedStageLine(const TaskContext& ctx, const TimedActionLog::StageSpec& spec)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(spec.key), stageOutcomeGlyph(ctx, TimedActionLog::StageOutcome::Success));
        line += "  ";
        appendStageText(line, ctx, spec);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatStageEnd(const TaskContext& ctx, const TimedActionLog::StageSpec& spec, const TimedActionLog::StageOutcome outcome, const uint64_t durationNs)
    {
        const Utf8 bullet          = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        const Utf8 duration        = Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));
        const auto outcomeLogColor = stageOutcomeColor(spec, outcome);

        Utf8 line;
        line += "  ";
        line += colorize(ctx, outcomeLogColor, stageOutcomeGlyph(ctx, outcome));
        line += "  ";
        appendStageText(line, ctx, spec);
        line += " ";
        line += colorize(ctx, LogColor::Gray, bullet);
        line += " ";
        if (outcome == TimedActionLog::StageOutcome::Error)
        {
            line += colorize(ctx, outcomeLogColor, "aborted");
            line += " ";
            line += colorize(ctx, LogColor::Gray, bullet);
            line += " ";
        }
        line += colorize(ctx, LogColor::White, duration);
        line += resetColor(ctx);
        return line;
    }

    void printLineLocked(const TaskContext& ctx, const Utf8& line)
    {
        if (ctx.cmdLine().silent)
            return;

        ctx.global().logger().ensureTransientLineSeparated(ctx);
        std::cout << line;
        std::cout << std::flush;
    }

    Utf8 formatBuildConfiguration(const TaskContext& ctx)
    {
        const CommandLine&       cmdLine  = ctx.cmdLine();
        const Runtime::BuildCfg& buildCfg = cmdLine.defaultBuildCfg;
        return joinParts(ctx, {cmdLine.buildCfg, buildCfgBackendKindName(buildCfg.backendKind), cmdLine.targetArchName}, LogColor::Gray);
    }
}

TimedActionLog::StatsSnapshot TimedActionLog::StatsSnapshot::capture()
{
    const Stats& stats = Stats::get();

    StatsSnapshot result;
    result.timeTotal   = stats.timeTotal.load(std::memory_order_relaxed);
    result.numErrors   = stats.numErrors.load(std::memory_order_relaxed);
    result.numWarnings = stats.numWarnings.load(std::memory_order_relaxed);
#if SWC_HAS_STATS
    result.numFiles  = stats.numFiles.load(std::memory_order_relaxed);
    result.numTokens = stats.numTokens.load(std::memory_order_relaxed);
#endif

    return result;
}

Utf8 TimedActionLog::formatStageStartLine(const TaskContext& ctx, const StageSpec& spec)
{
    Utf8 line = formatStageStart(ctx, spec);
    line += "\n";
    return line;
}

Utf8 TimedActionLog::formatStageEndLine(const TaskContext& ctx,
                                        const StageSpec&   spec,
                                        const StageOutcome outcome,
                                        const uint64_t     durationNs)
{
    Utf8 line = formatStageEnd(ctx, spec, outcome, durationNs);
    line += "\n";
    return line;
}

void TimedActionLog::printBuildConfiguration(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());

    const StageSpec spec{
        .key    = "config",
        .label  = "Config",
        .verb   = "arming toolchain",
        .detail = formatBuildConfiguration(ctx),
    };

    Utf8 line = formatCompletedStageLine(ctx, spec);
    line += "\n";
    printLineLocked(ctx, line);
}

void TimedActionLog::printSessionFlags(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    std::vector<Utf8> flags;

#if SWC_DEBUG
    flags.push_back("debug");
#elif SWC_DEV_MODE
    flags.emplace_back("devmode");
#elif SWC_STATS
    flags.push_back("stats");
#endif

#if SWC_DEBUG || SWC_DEV_MODE
    if (ctx.cmdLine().randomize)
        flags.emplace_back(std::format("randomize seed={}", ctx.global().jobMgr().randSeed()));
#endif

    if (flags.empty())
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());

    const StageSpec spec{
        .key    = "config",
        .label  = "Modes",
        .verb   = "settling runtime",
        .detail = joinParts(ctx, flags, LogColor::Gray),
    };

    Utf8 line = formatCompletedStageLine(ctx, spec);
    line += "\n";
    printLineLocked(ctx, line);
}

TimedActionLog::ScopedStage::ScopedStage(const TaskContext& ctx, StageSpec spec) :
    ctx_(&ctx),
    spec_(std::move(spec)),
    startTick_(Clock::now())
{
    const StatsSnapshot before = StatsSnapshot::capture();
    startErrors_               = before.numErrors;
    startWarnings_             = before.numWarnings;

    if (ctx_->global().logger().stageOutputMuted())
    {
        ctx_ = nullptr;
        return;
    }

    const Logger::ScopedLock loggerLock(ctx_->global().logger());
    printLineLocked(*ctx_, formatStageStartLine(*ctx_, spec_));
}

TimedActionLog::ScopedStage::~ScopedStage()
{
    if (!ctx_)
        return;

    const uint64_t durationNs =
        std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - startTick_).count();

    StatsSnapshot after = StatsSnapshot::capture();
    after.numErrors     = after.numErrors >= startErrors_ ? after.numErrors - startErrors_ : 0;
    after.numWarnings   = after.numWarnings >= startWarnings_ ? after.numWarnings - startWarnings_ : 0;

    StageOutcome outcome = classifyOutcome({}, after);
    if (forcedOutcome_.has_value())
        outcome = mergeOutcome(outcome, forcedOutcome_.value());

    const Logger::ScopedLock loggerLock(ctx_->global().logger());
    printLineLocked(*ctx_, formatStageEndLine(*ctx_, spec_, outcome, durationNs));
}

void TimedActionLog::ScopedStage::markOutcome(const StageOutcome outcome)
{
    forcedOutcome_ = outcome;
}

void TimedActionLog::ScopedStage::markFailure()
{
    markOutcome(StageOutcome::Error);
}

void TimedActionLog::ScopedStage::markWarning()
{
    markOutcome(StageOutcome::Warning);
}

Utf8 TimedActionLog::formatSummaryLine(const TaskContext& ctx, const StatsSnapshot& snapshot)
{
    std::vector<Utf8> parts;
#if SWC_HAS_STATS
    if (snapshot.numFiles)
        parts.emplace_back(Utf8Helper::countWithLabel(snapshot.numFiles, "file"));
    if (snapshot.numTokens)
        parts.emplace_back(Utf8Helper::countWithLabel(snapshot.numTokens, "token"));
#endif
    parts.push_back(Utf8Helper::toNiceTime(Timer::toSeconds(snapshot.timeTotal)));
    if (snapshot.numWarnings)
        parts.emplace_back(Utf8Helper::countWithLabel(snapshot.numWarnings, "warning"));
    if (snapshot.numErrors)
        parts.emplace_back(Utf8Helper::countWithLabel(snapshot.numErrors, "error"));
    else if (!snapshot.numWarnings)
        parts.emplace_back("clean");

    const Utf8 summaryText    = joinParts(ctx, parts, LogColor::White);
    const bool hasErrors      = snapshot.numErrors != 0;
    const auto summaryColor   = hasErrors ? LogColor::BrightRed : LogColor::BrightGreen;
    const auto summaryOutcome = hasErrors ? StageOutcome::Error : StageOutcome::Success;

    Utf8 line;
    line += "  ";
    line += colorize(ctx, summaryColor, stageOutcomeGlyph(ctx, summaryOutcome));
    line += "  ";
    line += colorize(ctx, summaryColor, std::format("{:<{}}", hasErrors ? "Aborted" : "Landed", ACTION_LABEL_WIDTH));
    line += " ";
    line += colorize(ctx, LogColor::White, summaryText);
    line += resetColor(ctx);
    line += "\n\n";
    return line;
}

void TimedActionLog::printSummary(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    const StatsSnapshot      snapshot = StatsSnapshot::capture();
    const Logger::ScopedLock loggerLock(ctx.global().logger());
    printLineLocked(ctx, formatSummaryLine(ctx, snapshot));
}

void TimedActionLog::printStep(const TaskContext& ctx, const std::string_view action, const std::string_view detail)
{
    const ScopedStage stage(ctx, StageSpec{.key = Utf8Helper::toLowerSnake(action), .label = action, .verb = "processing", .detail = detail});
    SWC_UNUSED(stage);
}

SWC_END_NAMESPACE();

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

    // Each stage has a rotating set of short, craftsman-philosopher phrases.

    constexpr std::string_view CONFIG_VERBS[] = {
        "arming the forge",
        "sharpening instruments",
        "preparing the ground",
        "readying the anvil",
        "gathering tools",
        "setting the stage",
    };

    constexpr std::string_view MODES_VERBS[] = {
        "settling conditions",
        "choosing the stance",
        "aligning intent",
        "tuning the approach",
    };

    constexpr std::string_view SYNTAX_VERBS[] = {
        "shaping syntax",
        "carving structure",
        "tracing outlines",
        "reading the grain",
        "unfolding form",
        "mapping contours",
    };

    constexpr std::string_view SEMA_VERBS[] = {
        "weighing meaning",
        "probing depth",
        "seeking coherence",
        "distilling intent",
        "threading sense",
        "reading between lines",
    };

    constexpr std::string_view JIT_VERBS[] = {
        "sparking proofs",
        "testing mettle",
        "striking sparks",
        "trial under fire",
        "forging certainty",
        "igniting trials",
    };

    constexpr std::string_view MICRO_VERBS[] = {
        "honing the edge",
        "polishing facets",
        "stripping excess",
        "refining precision",
        "cutting to essence",
        "chiseling details",
    };

    constexpr std::string_view BUILD_VERBS[] = {
        "forging substance",
        "casting the mold",
        "hammering form",
        "tempering steel",
        "shaping the artifact",
        "materializing intent",
    };

    constexpr std::string_view RUN_VERBS[] = {
        "releasing creation",
        "handing the reins",
        "setting it free",
        "breathing life",
        "letting it fly",
        "launching forward",
    };

    constexpr std::string_view VERIFY_VERBS[] = {
        "measuring truth",
        "weighing the yield",
        "checking the mark",
        "testing the claim",
        "gauging results",
        "confirming the craft",
    };

    constexpr std::string_view UNITTEST_VERBS[] = {
        "probing foundations",
        "testing the bones",
        "checking integrity",
        "stress-testing roots",
        "verifying the core",
    };

    constexpr std::string_view FALLBACK_VERBS[] = {
        "working the material",
    };

    template<size_t N>
    std::string_view pickVerb(const std::string_view (&pool)[N])
    {
        static std::atomic<uint32_t> counter{0};
        return pool[counter.fetch_add(1, std::memory_order_relaxed) % N];
    }

    std::string_view stageVerb(const std::string_view label)
    {
        if (label == "Config")
            return pickVerb(CONFIG_VERBS);
        if (label == "Modes")
            return pickVerb(MODES_VERBS);
        if (label == "Syntax")
            return pickVerb(SYNTAX_VERBS);
        if (label == "Sema")
            return pickVerb(SEMA_VERBS);
        if (label == "JIT")
            return pickVerb(JIT_VERBS);
        if (label == "Micro")
            return pickVerb(MICRO_VERBS);
        if (label == "Build")
            return pickVerb(BUILD_VERBS);
        if (label == "Run")
            return pickVerb(RUN_VERBS);
        if (label == "Verify")
            return pickVerb(VERIFY_VERBS);
        if (label == "Unittest")
            return pickVerb(UNITTEST_VERBS);
        return pickVerb(FALLBACK_VERBS);
    }

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

    LogColor stageColor(const std::string_view label)
    {
        if (label == "Config" || label == "Modes")
            return LogColor::BrightBlue;
        if (label == "Syntax")
            return LogColor::BrightCyan;
        if (label == "Sema")
            return LogColor::BrightBlue;
        if (label == "JIT")
            return LogColor::BrightMagenta;
        if (label == "Micro")
            return LogColor::BrightMagenta;
        if (label == "Verify" || label == "Unittest")
            return LogColor::BrightCyan;
        if (label == "Run")
            return LogColor::BrightGreen;
        return LogColor::BrightYellow;
    }

    LogColor stageOutcomeColor(const std::string_view label, const TimedActionLog::StageOutcome outcome)
    {
        if (outcome == TimedActionLog::StageOutcome::Success)
            return stageColor(label);

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

    Utf8 colorize(const TaskContext& ctx, const LogColor color, const std::string_view text)
    {
        Utf8 result;
        result += LogColorHelper::toAnsi(ctx, color);
        result += text;
        return result;
    }

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

    Utf8 resetColor(const TaskContext& ctx)
    {
        return LogColorHelper::toAnsi(ctx, LogColor::Reset);
    }

    void appendStageText(Utf8& line, const TaskContext& ctx, const std::string_view label, const std::string_view verb, const std::string_view detail)
    {
        const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        line += colorize(ctx, stageColor(label), std::format("{:<{}}", label, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, LogColor::White, verb);
        if (!detail.empty())
        {
            line += " ";
            line += colorize(ctx, LogColor::Gray, bullet);
            line += " ";
            line += colorize(ctx, LogColor::Gray, detail);
        }
    }

    Utf8 formatStageStart(const TaskContext& ctx, const std::string_view label, const std::string_view detail)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(label), stageStartGlyph(ctx));
        line += "  ";
        appendStageText(line, ctx, label, stageVerb(label), detail);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatCompletedStageLine(const TaskContext& ctx, const std::string_view label, const std::string_view detail)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(label), stageOutcomeGlyph(ctx, TimedActionLog::StageOutcome::Success));
        line += "  ";
        appendStageText(line, ctx, label, stageVerb(label), detail);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatStageEnd(const TaskContext& ctx, const std::string_view label, const TimedActionLog::StageOutcome outcome, const uint64_t durationNs, const Utf8& stat)
    {
        const Utf8 duration        = Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));
        const Utf8 bullet          = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        const auto outcomeLogColor = stageOutcomeColor(label, outcome);

        Utf8 line;
        line += "  ";
        line += colorize(ctx, outcomeLogColor, stageOutcomeGlyph(ctx, outcome));
        line += "  ";
        line += colorize(ctx, outcomeLogColor, std::format("{:<{}}", label, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, LogColor::White, duration);
        if (!stat.empty())
        {
            line += " ";
            line += colorize(ctx, LogColor::Gray, bullet);
            line += " ";
            line += colorize(ctx, LogColor::Gray, stat);
        }
        line += resetColor(ctx);
        return line;
    }

    void printLineLocked(const TaskContext& ctx, const Utf8& line)
    {
        if (ctx.cmdLine().silent)
            return;

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
    result.numFiles    = stats.numFiles.load(std::memory_order_relaxed);
    result.numTokens   = stats.numTokens.load(std::memory_order_relaxed);

    return result;
}

void TimedActionLog::printBuildConfiguration(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());

    Utf8 line = formatCompletedStageLine(ctx, "Config", formatBuildConfiguration(ctx));
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

    Utf8 line = formatCompletedStageLine(ctx, "Modes", joinParts(ctx, flags, LogColor::Gray));
    line += "\n";
    printLineLocked(ctx, line);
}

TimedActionLog::ScopedStage::ScopedStage(const TaskContext& ctx, Utf8 label, Utf8 detail) :
    ctx_(&ctx),
    label_(std::move(label)),
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

    Utf8 line = formatStageStart(*ctx_, label_, detail);
    line += "\n";
    printLineLocked(*ctx_, line);
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

    Utf8 line = formatStageEnd(*ctx_, label_, outcome, durationNs, stat_);
    line += "\n";
    printLineLocked(*ctx_, line);
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

void TimedActionLog::ScopedStage::setStat(Utf8 stat)
{
    stat_ = std::move(stat);
}

Utf8 TimedActionLog::formatSummaryLine(const TaskContext& ctx, const StatsSnapshot& snapshot)
{
    struct ColoredPart
    {
        Utf8     text;
        LogColor color;
    };

    std::vector<ColoredPart> parts;
    if (snapshot.numFiles)
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numFiles, "file"), LogColor::White});
    parts.push_back({Utf8Helper::toNiceTime(Timer::toSeconds(snapshot.timeTotal)), LogColor::White});
    if (snapshot.numWarnings)
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numWarnings, "warning"), LogColor::BrightYellow});
    if (snapshot.numErrors)
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numErrors, "error"), LogColor::BrightRed});
    else if (!snapshot.numWarnings)
        parts.push_back({"clean", LogColor::BrightGreen});

    const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
    Utf8       summaryText;
    bool       first = true;
    for (const auto& [text, color] : parts)
    {
        if (!first)
        {
            summaryText += " ";
            summaryText += colorize(ctx, LogColor::Gray, bullet);
            summaryText += " ";
        }
        summaryText += colorize(ctx, color, text);
        first = false;
    }

    const bool hasErrors      = snapshot.numErrors != 0;
    const auto summaryColor   = hasErrors ? LogColor::BrightRed : LogColor::BrightGreen;
    const auto summaryOutcome = hasErrors ? StageOutcome::Error : StageOutcome::Success;

    Utf8 line;
    line += "  ";
    line += colorize(ctx, summaryColor, stageOutcomeGlyph(ctx, summaryOutcome));
    line += "  ";
    line += colorize(ctx, summaryColor, std::format("{:<{}}", hasErrors ? "Aborted" : "Landed", ACTION_LABEL_WIDTH));
    line += " ";
    line += summaryText;
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

SWC_END_NAMESPACE();

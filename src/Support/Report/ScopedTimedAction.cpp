#include "pch.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t ACTION_LABEL_WIDTH = 8;
    constexpr size_t ACTION_VERB_WIDTH  = 25;

    template<typename T>
    T deltaValue(const T after, const T before)
    {
        return after >= before ? after - before : 0;
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
        if (key == "verify")
            return LogColor::BrightCyan;
        if (key == "run")
            return LogColor::BrightGreen;
        return LogColor::BrightYellow;
    }

    Utf8 funStartGlyph(const TaskContext& ctx, const size_t sequence)
    {
        if (ctx.cmdLine().logAscii)
            return ">";

        constexpr std::string_view frames[] = {
            "\xE2\x97\x90",
            "\xE2\x97\x93",
            "\xE2\x97\x91",
            "\xE2\x97\x92",
        };

        return Utf8(frames[(sequence - 1) % std::size(frames)]);
    }

    Utf8 funOutcomeGlyph(const TaskContext& ctx, const TimedActionLog::StageOutcome outcome)
    {
        if (ctx.cmdLine().logAscii)
        {
            switch (outcome)
            {
                case TimedActionLog::StageOutcome::Success:
                    return "*";
                case TimedActionLog::StageOutcome::Warning:
                    return "!";
                case TimedActionLog::StageOutcome::Error:
                    return "x";
            }
        }

        switch (outcome)
        {
            case TimedActionLog::StageOutcome::Success:
                return "\xE2\x9C\x93";
            case TimedActionLog::StageOutcome::Warning:
                return "\xE2\x9A\xA0";
            case TimedActionLog::StageOutcome::Error:
                return "\xE2\x9C\x96";
        }

        SWC_UNREACHABLE();
    }

    Utf8 joinHumanParts(const TaskContext& ctx, const std::vector<Utf8>& parts)
    {
        Utf8       result;
        const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        bool       first  = true;
        for (const Utf8& part : parts)
        {
            if (part.empty())
                continue;

            if (!first)
                result += std::format(" {} ", bullet);
            result += part;
            first = false;
        }

        return result;
    }

    Utf8 humanDetailSummary(const TaskContext& ctx, const TimedActionLog::StatsSnapshot& before, const TimedActionLog::StatsSnapshot& after, const uint64_t durationNs)
    {
        std::vector<Utf8> parts;

#if SWC_HAS_STATS
        const size_t deltaFiles     = deltaValue(after.numFiles, before.numFiles);
        const size_t deltaTokens    = deltaValue(after.numTokens, before.numTokens);
        const size_t deltaFunctions = deltaValue(after.numCodeGenFunctions, before.numCodeGenFunctions);

        if (deltaFiles)
            parts.push_back(std::format("{} files", Utf8Helper::toNiceBigNumber(deltaFiles)));
        if (deltaTokens)
            parts.push_back(std::format("{} tokens", Utf8Helper::toNiceBigNumber(deltaTokens)));
        if (deltaFunctions)
            parts.push_back(std::format("{} funcs", Utf8Helper::toNiceBigNumber(deltaFunctions)));
#endif

        parts.push_back(Utf8Helper::toNiceTime(Timer::toSeconds(durationNs)));

        const size_t deltaWarnings = deltaValue(after.numWarnings, before.numWarnings);
        const size_t deltaErrors   = deltaValue(after.numErrors, before.numErrors);
        if (deltaWarnings)
            parts.push_back(std::format("{} warnings", Utf8Helper::toNiceBigNumber(deltaWarnings)));
        if (deltaErrors)
            parts.push_back(std::format("{} errors", Utf8Helper::toNiceBigNumber(deltaErrors)));

        return joinHumanParts(ctx, parts);
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

    Utf8 formatFunStageStartLine(const TaskContext& ctx, const TimedActionLog::StageSpec& spec, const size_t sequence)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(spec.key), funStartGlyph(ctx, sequence));
        line += "  ";
        line += colorize(ctx, stageColor(spec.key), std::format("{:<{}}", spec.label, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, LogColor::White, std::format("{:<{}}", spec.verb, ACTION_VERB_WIDTH));
        if (!spec.detail.empty())
            line += colorize(ctx, LogColor::Gray, spec.detail);

        line += resetColor(ctx);
        line += "\n";
        return line;
    }

    Utf8 formatFunStageEndLine(const TaskContext& ctx,
                               const TimedActionLog::StageSpec& spec,
                               const TimedActionLog::StageOutcome outcome,
                               const TimedActionLog::StatsSnapshot& before,
                               const TimedActionLog::StatsSnapshot& after,
                               const uint64_t durationNs)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, outcomeColor(outcome), funOutcomeGlyph(ctx, outcome));
        line += "  ";
        line += colorize(ctx, outcomeColor(outcome), std::format("{:<{}}", spec.label, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, LogColor::White, humanDetailSummary(ctx, before, after, durationNs));
        line += resetColor(ctx);
        line += "\n";
        return line;
    }

    void printLineLocked(const TaskContext& ctx, const Utf8& line)
    {
        if (ctx.cmdLine().silent)
            return;

        ctx.global().logger().ensureTransientLineSeparated(ctx);
        Logger::print(ctx, line);
        std::cout << std::flush;
    }

    Utf8 formatBuildConfiguration(const TaskContext& ctx)
    {
        const CommandLine&       cmdLine  = ctx.cmdLine();
        const Runtime::BuildCfg& buildCfg = cmdLine.defaultBuildCfg;
        return joinHumanParts(ctx, {cmdLine.buildCfg, buildCfgBackendKindName(buildCfg.backendKind), cmdLine.targetArchName});
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
    result.timeLoadFile   = stats.timeLoadFile.load(std::memory_order_relaxed);
    result.timeLexer      = stats.timeLexer.load(std::memory_order_relaxed);
    result.timeParser     = stats.timeParser.load(std::memory_order_relaxed);
    result.timeSema       = stats.timeSema.load(std::memory_order_relaxed);
    result.timeCodeGen    = stats.timeCodeGen.load(std::memory_order_relaxed);
    result.timeMicroLower = stats.timeMicroLower.load(std::memory_order_relaxed);

    result.numFiles             = stats.numFiles.load(std::memory_order_relaxed);
    result.numTokens            = stats.numTokens.load(std::memory_order_relaxed);
    result.numAstNodes          = stats.numAstNodes.load(std::memory_order_relaxed);
    result.numVisitedAstNodes   = stats.numVisitedAstNodes.load(std::memory_order_relaxed);
    result.numConstants         = stats.numConstants.load(std::memory_order_relaxed);
    result.numTypes             = stats.numTypes.load(std::memory_order_relaxed);
    result.numIdentifiers       = stats.numIdentifiers.load(std::memory_order_relaxed);
    result.numSymbols           = stats.numSymbols.load(std::memory_order_relaxed);
    result.numMicroInstrNoOptim = stats.numMicroInstrNoOptim.load(std::memory_order_relaxed);
    result.numMicroInstrFinal   = stats.numMicroInstrFinal.load(std::memory_order_relaxed);
    result.numCodeGenFunctions  = stats.numCodeGenFunctions.load(std::memory_order_relaxed);
#endif

    return result;
}

Utf8 TimedActionLog::formatStageStartLine(const TaskContext& ctx, const StageSpec& spec, const size_t sequence)
{
    return formatFunStageStartLine(ctx, spec, sequence);
}

Utf8 TimedActionLog::formatStageEndLine(const TaskContext& ctx,
                                        const StageSpec& spec,
                                        const size_t sequence,
                                        const StageOutcome outcome,
                                        const StatsSnapshot& before,
                                        const StatsSnapshot& after,
                                        const uint64_t durationNs)
{
    SWC_UNUSED(sequence);
    return formatFunStageEndLine(ctx, spec, outcome, before, after, durationNs);
}

void TimedActionLog::printBuildConfiguration(const TaskContext& ctx)
{
    const Logger::ScopedLock loggerLock(ctx.global().logger());

    const StageSpec spec{
        .key    = "config",
        .label  = "Config",
        .verb   = "arming toolchain",
        .detail = formatBuildConfiguration(ctx),
    };

    printLineLocked(ctx, formatFunStageStartLine(ctx, spec, ctx.global().logger().nextStageSequence()));
}

void TimedActionLog::printSessionFlags(const TaskContext& ctx)
{
    std::vector<Utf8> flags;

#if SWC_DEBUG
    flags.push_back("debug");
#elif SWC_DEV_MODE
    flags.push_back("devmode");
#elif SWC_STATS
    flags.push_back("stats");
#endif

#if SWC_DEBUG || SWC_DEV_MODE
    if (ctx.cmdLine().randomize)
        flags.push_back(std::format("randomize seed={}", ctx.global().jobMgr().randSeed()));
#endif

    if (flags.empty())
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());

    const StageSpec spec{
        .key    = "config",
        .label  = "Modes",
        .verb   = "settling runtime",
        .detail = joinHumanParts(ctx, flags),
    };

    printLineLocked(ctx, formatFunStageStartLine(ctx, spec, ctx.global().logger().nextStageSequence()));
}

TimedActionLog::ScopedStage::ScopedStage(const TaskContext& ctx, StageSpec spec) :
    ctx_(&ctx),
    spec_(std::move(spec)),
    before_(StatsSnapshot::capture()),
    startTick_(Clock::now())
{
    const Logger::ScopedLock loggerLock(ctx_->global().logger());
    sequence_ = ctx_->global().logger().nextStageSequence();
    printLineLocked(*ctx_, formatStageStartLine(*ctx_, spec_, sequence_));
}

TimedActionLog::ScopedStage::~ScopedStage()
{
    if (!ctx_)
        return;

    const StatsSnapshot after = StatsSnapshot::capture();
    const uint64_t      durationNs =
        std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - startTick_).count();

    StageOutcome outcome = classifyOutcome(before_, after);
    if (forcedOutcome_.has_value())
        outcome = mergeOutcome(outcome, forcedOutcome_.value());

    const Logger::ScopedLock loggerLock(ctx_->global().logger());
    printLineLocked(*ctx_, formatStageEndLine(*ctx_, spec_, sequence_, outcome, before_, after, durationNs));
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
    auto outcome = StageOutcome::Success;
    if (snapshot.numErrors)
        outcome = StageOutcome::Error;
    else if (snapshot.numWarnings)
        outcome = StageOutcome::Warning;

    std::vector<Utf8> parts;
#if SWC_HAS_STATS
    if (snapshot.numFiles)
        parts.push_back(std::format("{} files", Utf8Helper::toNiceBigNumber(snapshot.numFiles)));
    if (snapshot.numTokens)
        parts.push_back(std::format("{} tokens", Utf8Helper::toNiceBigNumber(snapshot.numTokens)));
#endif
    parts.push_back(Utf8Helper::toNiceTime(Timer::toSeconds(snapshot.timeTotal)));
    if (snapshot.numWarnings)
        parts.push_back(std::format("{} warnings", Utf8Helper::toNiceBigNumber(snapshot.numWarnings)));
    if (snapshot.numErrors)
        parts.push_back(std::format("{} errors", Utf8Helper::toNiceBigNumber(snapshot.numErrors)));
    else if (!snapshot.numWarnings)
        parts.push_back("clean");

    const Utf8 summaryText = joinHumanParts(ctx, parts);

    Utf8 line;
    line += "  ";
    line += colorize(ctx, outcomeColor(outcome), funOutcomeGlyph(ctx, outcome));
    line += "  ";
    line += colorize(ctx, outcomeColor(outcome), std::format("{:<{}}", outcome == StageOutcome::Error ? "Aborted" : "Landed", ACTION_LABEL_WIDTH));
    line += " ";
    line += colorize(ctx, LogColor::White, summaryText);
    line += resetColor(ctx);
    line += "\n\n";
    return line;
}

void TimedActionLog::printSummary(const TaskContext& ctx)
{
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

#include "pch.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Backend/Runtime.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/LogSymbol.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

using Stage = TimedActionLog::Stage;

namespace
{
    constexpr size_t ACTION_LABEL_WIDTH = 10;

    // ── Philosophy verb pools ──────────────────────────────────────────
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

    constexpr std::string_view FORMAT_VERBS[] = {
        "restoring cadence",
        "aligning the lines",
        "preserving the grain",
        "rewriting with care",
        "settling the text",
        "matching the source",
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

    template<size_t N>
    std::string_view pickVerb(const std::string_view (&pool)[N])
    {
        static std::atomic<uint32_t> counter{0};
        return pool[counter.fetch_add(1, std::memory_order_relaxed) % N];
    }

    std::string_view stageVerb(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Config:
                return pickVerb(CONFIG_VERBS);
            case Stage::Modes:
                return pickVerb(MODES_VERBS);
            case Stage::Format:
                return pickVerb(FORMAT_VERBS);
            case Stage::Syntax:
                return pickVerb(SYNTAX_VERBS);
            case Stage::Sema:
                return pickVerb(SEMA_VERBS);
            case Stage::JIT:
                return pickVerb(JIT_VERBS);
            case Stage::Micro:
                return pickVerb(MICRO_VERBS);
            case Stage::Build:
                return pickVerb(BUILD_VERBS);
            case Stage::Run:
                return pickVerb(RUN_VERBS);
            case Stage::Verify:
                return pickVerb(VERIFY_VERBS);
            case Stage::Unittest:
                return pickVerb(UNITTEST_VERBS);
        }

        SWC_UNREACHABLE();
    }

    // ── Stage properties ───────────────────────────────────────────────

    std::string_view stageLabel(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Config:
                return "Config";
            case Stage::Modes:
                return "Modes";
            case Stage::Format:
                return "Format";
            case Stage::Syntax:
                return "Syntax";
            case Stage::Sema:
                return "Sema";
            case Stage::JIT:
                return "JIT";
            case Stage::Micro:
                return "Micro";
            case Stage::Build:
                return "Build";
            case Stage::Run:
                return "Run";
            case Stage::Verify:
                return "Verify";
            case Stage::Unittest:
                return "Unittest";
        }

        SWC_UNREACHABLE();
    }

    LogColor stageColor(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Config:
            case Stage::Modes:
            case Stage::Sema:
                return LogColor::BrightBlue;
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Verify:
            case Stage::Unittest:
                return LogColor::BrightCyan;
            case Stage::JIT:
            case Stage::Micro:
                return LogColor::BrightMagenta;
            case Stage::Build:
                return LogColor::BrightYellow;
            case Stage::Run:
                return LogColor::BrightGreen;
        }

        SWC_UNREACHABLE();
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

    LogColor stageOutcomeColor(const Stage stage, const TimedActionLog::StageOutcome outcome)
    {
        if (outcome == TimedActionLog::StageOutcome::Success)
            return stageColor(stage);

        return outcomeColor(outcome);
    }

    // ── Source root formatting ──────────────────────────────────────────

    fs::path commonPathPrefix(const fs::path& lhs, const fs::path& rhs)
    {
        fs::path result;
        auto     itLhs = lhs.begin();
        auto     itRhs = rhs.begin();
        while (itLhs != lhs.end() && itRhs != rhs.end() && *itLhs == *itRhs)
        {
            result /= *itLhs;
            ++itLhs;
            ++itRhs;
        }

        return result;
    }

    Utf8 displayPath(const fs::path& path)
    {
        std::error_code ec;
        const fs::path  currentPath = fs::current_path(ec);
        if (!ec)
        {
            std::error_code relEc;
            const fs::path  relative = fs::relative(path, currentPath, relEc);
            if (!relEc && !relative.empty())
                return Utf8{relative.generic_string()};
        }

        return Utf8{path.generic_string()};
    }

    Utf8 formatSourceRoots(const std::vector<fs::path>& roots)
    {
        if (roots.empty())
            return "sources";

        fs::path          commonRoot;
        std::vector<Utf8> labels;
        for (const fs::path& root : roots)
        {
            const fs::path normalized = root.lexically_normal();
            if (commonRoot.empty())
                commonRoot = normalized;
            else
                commonRoot = commonPathPrefix(commonRoot, normalized);

            labels.push_back(displayPath(normalized));
        }

        std::ranges::sort(labels);
        labels.erase(std::ranges::unique(labels).begin(), labels.end());

        if (labels.size() == 1)
            return labels.front();

        if (!commonRoot.empty() && commonRoot != "." && commonRoot != commonRoot.root_path())
            return displayPath(commonRoot);

        return std::format("{} locations", Utf8Helper::toNiceBigNumber(labels.size()));
    }

    Utf8 formatCommandSourceRoots(const CommandLine& cmdLine)
    {
        std::vector<fs::path> roots;
        if (!cmdLine.modulePath.empty())
            roots.push_back(cmdLine.modulePath);
        for (const fs::path& folder : cmdLine.directories)
            roots.push_back(folder);
        for (const fs::path& file : cmdLine.files)
            roots.push_back(file.parent_path().empty() ? file : file.parent_path());

        return formatSourceRoots(roots);
    }

    Utf8 stageDetail(const TaskContext& ctx, const Stage stage)
    {
        switch (stage)
        {
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Sema:
                return formatCommandSourceRoots(ctx.cmdLine());
            default:
                return {};
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────

    Utf8 buildCfgBackendKindName(const Runtime::BuildCfgBackendKind value)
    {
        switch (value)
        {
            case Runtime::BuildCfgBackendKind::Executable:
                return "executable";
            case Runtime::BuildCfgBackendKind::SharedLibrary:
                return "shared-library";
            case Runtime::BuildCfgBackendKind::StaticLibrary:
                return "static-library";
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

    void appendStageText(Utf8& line, const TaskContext& ctx, const Stage stage, const std::string_view detail)
    {
        const auto label  = stageLabel(stage);
        const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        line += colorize(ctx, stageColor(stage), std::format("{:<{}}", label, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, LogColor::White, stageVerb(stage));
        if (!detail.empty())
        {
            line += " ";
            line += colorize(ctx, LogColor::Gray, bullet);
            line += " ";
            line += colorize(ctx, LogColor::Gray, detail);
        }
    }

    Utf8 formatStageStart(const TaskContext& ctx, const Stage stage, const std::string_view detail)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(stage), stageStartGlyph(ctx));
        line += "  ";
        appendStageText(line, ctx, stage, detail);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatCompletedStageLine(const TaskContext& ctx, const Stage stage, const std::string_view detail)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, stageColor(stage), stageOutcomeGlyph(ctx, TimedActionLog::StageOutcome::Success));
        line += "  ";
        appendStageText(line, ctx, stage, detail);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatStageEnd(const TaskContext& ctx, const Stage stage, const TimedActionLog::StageOutcome outcome, const uint64_t durationNs, const Utf8& stat)
    {
        const auto label           = stageLabel(stage);
        const Utf8 duration        = Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));
        const Utf8 bullet          = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        const auto outcomeLogColor = stageOutcomeColor(stage, outcome);

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
        return joinParts(ctx, {cmdLine.buildCfg, buildCfgBackendKindName(buildCfg.backendKind), commandLineTargetArchName(cmdLine.targetArch)}, LogColor::Gray);
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

    Utf8 line = formatCompletedStageLine(ctx, Stage::Config, formatBuildConfiguration(ctx));
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

    Utf8 line = formatCompletedStageLine(ctx, Stage::Modes, joinParts(ctx, flags, LogColor::Gray));
    line += "\n";
    printLineLocked(ctx, line);
}

TimedActionLog::ScopedStage::ScopedStage(const TaskContext& ctx, const Stage stage) :
    ctx_(&ctx),
    stage_(stage),
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

    Utf8 line = formatStageStart(*ctx_, stage_, stageDetail(*ctx_, stage_));
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

    Utf8 line = formatStageEnd(*ctx_, stage_, outcome, durationNs, stat_);
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
    {
        const Utf8 artifactLabel = ctx.hasCompiler() ? ctx.compiler().lastArtifactLabel() : Utf8{};
        if (!artifactLabel.empty())
            parts.push_back({artifactLabel, LogColor::Gray});
    }

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

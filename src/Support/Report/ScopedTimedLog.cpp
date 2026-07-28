#include "pch.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/LogSymbol.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

using Stage         = ScopedTimedLog::Stage;
using StatsSnapshot = ScopedTimedLog::StatsSnapshot;

namespace
{
    // Everything the compiler prints on its own behalf starts with these three columns:
    // a two-space margin, an outcome glyph, and a label naming the work.
    struct LinePrefix
    {
        LogColor  glyphColor = LogColor::Gray;
        LogSymbol glyph      = LogSymbol::DotCenter;
        LogColor  labelColor = LogColor::Gray;
    };

    Utf8 colorize(const TaskContext& ctx, const LogColor color, const std::string_view text)
    {
        Utf8 result = LogColorHelper::toAnsi(ctx, color);
        result += text;
        return result;
    }

    Utf8 plural(const size_t value, const std::string_view singular, const char* plural)
    {
        if (value == 1)
            return Utf8{singular};
        if (plural)
            return Utf8{plural};
        return Utf8{singular} + "s";
    }

    // A stage names itself with a verb: what it is doing while it runs, what it has done once it
    // is over. The two scope stages are the exception, because they report a whole workspace or
    // module rather than one kind of work.
    std::string_view stageActiveLabel(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace: return "workspace";
            case Stage::Module: return "module";
            case Stage::Format: return "formatting";
            case Stage::Syntax: return "reading";
            case Stage::Sema: return "checking";
            case Stage::JIT: return "executing";
            case Stage::Micro: return "tuning";
            case Stage::Build: return "forging";
            case Stage::Run: return "running";
            case Stage::Test: return "testing";
            case Stage::Verify: return "verifying";
            case Stage::Unittest: return "testing";
        }
        SWC_UNREACHABLE();
    }

    std::string_view stageDoneLabel(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace: return "workspace";
            case Stage::Module: return "module";
            case Stage::Format: return "formatted";
            case Stage::Syntax: return "read";
            case Stage::Sema: return "checked";
            case Stage::JIT: return "executed";
            case Stage::Micro: return "tuned";
            case Stage::Build: return "forged";
            case Stage::Run: return "ran";
            case Stage::Test: return "tested";
            case Stage::Verify: return "verified";
            case Stage::Unittest: return "tested";
        }
        SWC_UNREACHABLE();
    }

    // The last word of a run. It says how the command ended, not what it produced.
    std::string_view commandOutcomeLabel(const ScopedTimedLog::StageOutcome outcome)
    {
        switch (outcome)
        {
            case ScopedTimedLog::StageOutcome::Success: return "clean";
            case ScopedTimedLog::StageOutcome::Warning: return "passed";
            case ScopedTimedLog::StageOutcome::Error: return "stopped";
        }
        SWC_UNREACHABLE();
    }

    LinePrefix stageOutcomePrefix(const ScopedTimedLog::StageOutcome outcome, const bool upToDate)
    {
        if (outcome == ScopedTimedLog::StageOutcome::Error)
            return {.glyphColor = LogColor::BrightRed, .glyph = LogSymbol::Error};
        if (outcome == ScopedTimedLog::StageOutcome::Warning)
            return {.glyphColor = LogColorHelper::diagnosticSeverityColor(DiagnosticSeverity::Warning), .glyph = LogSymbol::Warning};
        if (upToDate)
            return {.glyphColor = LogColor::BrightBlue, .glyph = LogSymbol::UpToDate};
        return {.glyphColor = LogColor::BrightGreen, .glyph = LogSymbol::Check};
    }

    // What the command operates on: workspace / module / directory name.
    Utf8 scopeName(const CommandLine& cmd)
    {
        if (!cmd.workspacePath.empty())
        {
            Utf8 name{cmd.workspacePath.filename().string()};
            if (!cmd.workspaceModuleFilter.empty())
                name += " [" + cmd.workspaceModuleFilter + "]";
            return name;
        }
        if (!cmd.modulePath.empty())
            return Utf8{cmd.modulePath.filename().string()};
        if (!cmd.moduleFilePath.empty())
            return Utf8{cmd.moduleFilePath.parent_path().filename().string()};

        const auto relative = [](const fs::path& path) {
            std::error_code ec;
            const fs::path  rel = fs::relative(path, fs::current_path(ec), ec);
            return Utf8{(!ec && !rel.empty() ? rel : path).generic_string()};
        };
        if (!cmd.directories.empty())
            return cmd.directories.size() == 1 ? relative(*cmd.directories.begin()) : Utf8{std::format("{} locations", cmd.directories.size())};
        if (!cmd.files.empty())
            return cmd.files.size() == 1 ? relative(*cmd.files.begin()) : Utf8{std::format("{} files", cmd.files.size())};
        return "sources";
    }

    // The one and only line printer: <margin><glyph>  <label> part • part • part
    void printLine(const TaskContext& ctx, const LinePrefix& prefix, const std::string_view label, const std::vector<Utf8>& parts)
    {
        if (ctx.cmdLine().silent)
            return;

        const Logger::ScopedLock lock(ctx.global().logger());

        Utf8 line;
        line.append(2, ' ');
        line += colorize(ctx, prefix.glyphColor, LogSymbolHelper::toString(ctx, prefix.glyph));
        line += "  ";
        if (!label.empty())
            line += colorize(ctx, prefix.labelColor, std::format("{:<10}", label));

        const Utf8 bullet = colorize(ctx, LogColor::Gray, LogSymbolHelper::toString(ctx, LogSymbol::DotList));
        bool       first  = true;
        for (const Utf8& part : parts)
        {
            if (part.empty())
                continue;
            if (!first)
                line += " " + bullet + " ";
            line += part;
            first = false;
        }

        line += LogColorHelper::toAnsi(ctx, LogColor::Reset);
        line += "\n";
        std::cout << line << std::flush;
    }
}

StatsSnapshot StatsSnapshot::capture()
{
    const Stats& stats = Stats::get();

    StatsSnapshot result;
    result.timeTotal               = stats.timeTotal.load(std::memory_order_relaxed);
    result.numErrors               = stats.numErrors.load(std::memory_order_relaxed);
    result.numWarnings             = stats.numWarnings.load(std::memory_order_relaxed);
    result.numFiles                = stats.numFiles.load(std::memory_order_relaxed);
    result.numTests                = stats.numTests.load(std::memory_order_relaxed);
    result.numTestsFailed          = stats.numTestsFailed.load(std::memory_order_relaxed);
    result.numTokens               = stats.numTokens.load(std::memory_order_relaxed);
    result.numFormatRewrittenFiles = stats.numFormatRewrittenFiles.load(std::memory_order_relaxed);
    return result;
}

// "N tests [• M did not pass]" parts of a test-command stage line. The executed count is
// always shown, even when zero: in test mode, "no test ran" is a result in itself.
void ScopedTimedLog::appendTestStats(const TaskContext& ctx, std::vector<Utf8>& parts, const size_t executed, const size_t failed)
{
    parts.push_back(formatStatCount(ctx, executed, "test"));
    if (failed)
        parts.push_back(colorize(ctx, LogColor::BrightRed, Utf8Helper::toNiceBigNumber(failed) + " did not pass"));
}

Utf8 ScopedTimedLog::formatStatCount(const TaskContext& ctx, const size_t value, const std::string_view singular, const char* pluralForm)
{
    return colorize(ctx, LogColor::Gray, Utf8Helper::toNiceBigNumber(value)) + " " + colorize(ctx, LogColor::Gray, plural(value, singular, pluralForm));
}

Utf8 ScopedTimedLog::formatStatRatio(const TaskContext& ctx, const size_t value, const size_t total, const std::string_view singular)
{
    return colorize(ctx, LogColor::Gray, std::format("{}/{}", Utf8Helper::toNiceBigNumber(value), Utf8Helper::toNiceBigNumber(total))) + " " + colorize(ctx, LogColor::Gray, plural(total, singular, nullptr));
}

Utf8 ScopedTimedLog::formatStatName(const TaskContext& ctx, const std::string_view name)
{
    return colorize(ctx, LogColor::Gray, name);
}

Utf8 ScopedTimedLog::joinStatItems(const TaskContext& ctx, const std::vector<Utf8>& items)
{
    const Utf8 bullet = colorize(ctx, LogColor::Gray, LogSymbolHelper::toString(ctx, LogSymbol::DotList));
    Utf8       result;
    bool       first = true;
    for (const Utf8& item : items)
    {
        if (item.empty())
            continue;
        if (!first)
            result += " " + bullet + " ";
        result += item;
        first = false;
    }
    return result;
}

bool ScopedTimedLog::isOutputEnabled(const TaskContext& ctx, const Stage stage)
{
    if (ctx.cmdLine().silent || ctx.global().logger().stageOutputMuted())
        return false;

    const auto* moduleLog = ctx.hasCompiler() ? ctx.compiler().workspaceModuleLogState() : nullptr;
    return !moduleLog || stage == Stage::Module || ctx.global().logger().stagesDetailed();
}

ScopedTimedLog::ScopedTimedLog(const TaskContext& ctx, const Stage stage, Utf8 detail) :
    ctx_(&ctx),
    stage_(stage),
    startTick_(Clock::now()),
    startSnapshot_(StatsSnapshot::capture()),
    printEnabled_(isOutputEnabled(ctx, stage))
{
    const auto* moduleLog = ctx.hasCompiler() ? ctx.compiler().workspaceModuleLogState() : nullptr;

    if (!detail.empty())
        detail_ = std::move(detail);
    else if (stage == Stage::Workspace)
        detail_ = colorize(ctx, LogColor::Yellow, scopeName(ctx.cmdLine()));
    else if (stage == Stage::Module)
        detail_ = colorize(ctx, LogColor::Yellow, moduleLog ? moduleLog->name : scopeName(ctx.cmdLine()));
}

ScopedTimedLog::~ScopedTimedLog()
{
    if (!ctx_ || !printEnabled_)
        return;

    const StatsSnapshot d = delta();

    auto outcome = StageOutcome::Success;
    if (d.numErrors)
        outcome = StageOutcome::Error;
    else if (d.numWarnings)
        outcome = StageOutcome::Warning;
    if (forcedOutcome_ && static_cast<int>(*forcedOutcome_) > static_cast<int>(outcome))
        outcome = *forcedOutcome_;

    const uint64_t durationNs = std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - startTick_).count();
    const Utf8     time       = colorize(*ctx_, LogColor::Gray, Utf8Helper::toNiceTime(Timer::toSeconds(durationNs)));

    // The workspace line covers every module of a test run, so its test tally has to
    // be computed at print time from the stage delta: the caller-provided stat is
    // refreshed per module and would be stale when a module fails mid-run.
    Utf8 testStat;
    if (stage_ == Stage::Workspace && ctx_->cmdLine().command == CommandKind::Test)
    {
        std::vector<Utf8> parts;
        appendTestStats(*ctx_, parts, d.numTests, d.numTestsFailed);
        testStat = joinStatItems(*ctx_, parts);
    }

    // A stage that failed did not do what its past tense claims: it names the work it was busy
    // with instead, so the line reads as the point where the run stopped.
    const std::string_view label = outcome == StageOutcome::Error ? stageActiveLabel(stage_) : stageDoneLabel(stage_);
    printLine(*ctx_, stageOutcomePrefix(outcome, upToDate_), label, {detail_, stat_, testStat, time});
}

StatsSnapshot ScopedTimedLog::delta() const
{
    const StatsSnapshot now = StatsSnapshot::capture();
    StatsSnapshot       result;
    result.timeTotal               = now.timeTotal - std::min(now.timeTotal, startSnapshot_.timeTotal);
    result.numErrors               = now.numErrors - std::min(now.numErrors, startSnapshot_.numErrors);
    result.numWarnings             = now.numWarnings - std::min(now.numWarnings, startSnapshot_.numWarnings);
    result.numFiles                = now.numFiles - std::min(now.numFiles, startSnapshot_.numFiles);
    result.numTests                = now.numTests - std::min(now.numTests, startSnapshot_.numTests);
    result.numTestsFailed          = now.numTestsFailed - std::min(now.numTestsFailed, startSnapshot_.numTestsFailed);
    result.numTokens               = now.numTokens - std::min(now.numTokens, startSnapshot_.numTokens);
    result.numFormatRewrittenFiles = now.numFormatRewrittenFiles - std::min(now.numFormatRewrittenFiles, startSnapshot_.numFormatRewrittenFiles);
    return result;
}

void ScopedTimedLog::markFailure()
{
    forcedOutcome_ = StageOutcome::Error;
}

void ScopedTimedLog::markUpToDate()
{
    upToDate_ = true;
}

void ScopedTimedLog::setStat(Utf8 stat)
{
    stat_ = std::move(stat);
}

ScopedCommandLog::ScopedCommandLog(const TaskContext& ctx) :
    ctx_(&ctx),
    startTick_(ScopedTimedLog::Clock::now())
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    const CommandLine& cmd = ctx.cmdLine();

    std::vector<Utf8> parts;
    parts.emplace_back(colorize(ctx, LogColor::White, commandName(cmd.command)));
    parts.emplace_back(colorize(ctx, LogColor::Yellow, scopeName(cmd)));
    if (cmd.command == CommandKind::Build || cmd.command == CommandKind::Run || cmd.command == CommandKind::Test)
        parts.push_back(colorize(ctx, LogColor::Gray, cmd.buildCfg));

    const LinePrefix prefix{.glyphColor = LogColor::BrightBlue, .glyph = LogSymbol::CommandMark, .labelColor = LogColor::BrightBlue};
    printLine(ctx, prefix, "swag", parts);
}

ScopedCommandLog::~ScopedCommandLog()
{
    if (ctx_->global().logger().stageOutputMuted())
        return;

    const Stats& stats       = Stats::get();
    const size_t numErrors   = stats.numErrors.load(std::memory_order_relaxed);
    const size_t numWarnings = stats.numWarnings.load(std::memory_order_relaxed);

    auto outcome = ScopedTimedLog::StageOutcome::Success;
    if (numErrors)
        outcome = ScopedTimedLog::StageOutcome::Error;
    else if (numWarnings)
        outcome = ScopedTimedLog::StageOutcome::Warning;

    std::vector<Utf8> parts;
    if (numErrors)
        parts.push_back(colorize(*ctx_, LogColor::BrightRed, Utf8Helper::toNiceBigNumber(numErrors) + " " + plural(numErrors, "error", nullptr)));
    if (numWarnings)
        parts.push_back(colorize(*ctx_, LogColorHelper::diagnosticSeverityColor(DiagnosticSeverity::Warning), Utf8Helper::toNiceBigNumber(numWarnings) + " " + plural(numWarnings, "warning", nullptr)));

    const uint64_t durationNs = std::chrono::duration_cast<std::chrono::nanoseconds>(ScopedTimedLog::Clock::now() - startTick_).count();
    parts.push_back(colorize(*ctx_, LogColor::Gray, Utf8Helper::toNiceTime(Timer::toSeconds(durationNs))));

    printLine(*ctx_, stageOutcomePrefix(outcome, false), commandOutcomeLabel(outcome), parts);
}

SWC_END_NAMESPACE();

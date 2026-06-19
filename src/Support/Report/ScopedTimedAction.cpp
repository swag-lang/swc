#include "pch.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/LogSymbol.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

using Stage         = TimedActionLog::Stage;
using StatsSnapshot = TimedActionLog::StatsSnapshot;

namespace
{
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

    std::string_view stageLabel(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace: return "Workspace";
            case Stage::Module: return "Module";
            case Stage::Config: return "Config";
            case Stage::Modes: return "Mode";
            case Stage::Format: return "Format";
            case Stage::Syntax: return "Syntax";
            case Stage::Sema: return "Sema";
            case Stage::JIT: return "JIT";
            case Stage::Micro: return "Micro";
            case Stage::Build: return "Build";
            case Stage::Run: return "Run";
            case Stage::Test: return "Test";
            case Stage::Verify: return "Verify";
            case Stage::Unittest: return "Unittest";
        }
        SWC_UNREACHABLE();
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

    // The one and only line printer: <indent><glyph>  <label> part • part • part
    void printLine(const TaskContext& ctx, const size_t indent, const LogColor glyphColor, const LogSymbol glyph, const std::string_view label, const std::vector<Utf8>& parts)
    {
        if (ctx.cmdLine().silent)
            return;

        const Logger::ScopedLock lock(ctx.global().logger());

        Utf8 line;
        line.append(2 + indent * 2, ' ');
        line += colorize(ctx, glyphColor, LogSymbolHelper::toString(ctx, glyph));
        line += "  ";
        if (!label.empty())
            line += colorize(ctx, LogColor::Gray, std::format("{:<10}", label));

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
    result.numTokens               = stats.numTokens.load(std::memory_order_relaxed);
    result.numFormatRewrittenFiles = stats.numFormatRewrittenFiles.load(std::memory_order_relaxed);
    return result;
}

Utf8 TimedActionLog::formatStatCount(const TaskContext& ctx, const size_t value, const std::string_view singular, const char* pluralForm)
{
    return colorize(ctx, LogColor::Gray, Utf8Helper::toNiceBigNumber(value)) + " " + colorize(ctx, LogColor::Gray, plural(value, singular, pluralForm));
}

Utf8 TimedActionLog::formatStatRatio(const TaskContext& ctx, const size_t value, const size_t total, const std::string_view singular)
{
    return colorize(ctx, LogColor::Gray, std::format("{}/{}", Utf8Helper::toNiceBigNumber(value), Utf8Helper::toNiceBigNumber(total))) + " " + colorize(ctx, LogColor::Gray, plural(total, singular, nullptr));
}

Utf8 TimedActionLog::formatStatName(const TaskContext& ctx, const std::string_view name)
{
    return colorize(ctx, LogColor::Gray, name);
}

Utf8 TimedActionLog::joinStatItems(const TaskContext& ctx, const std::vector<Utf8>& items)
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

void TimedActionLog::printCommandHeader(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    const CommandLine& cmd = ctx.cmdLine();

    std::vector<Utf8> parts;
    parts.emplace_back(colorize(ctx, LogColor::White, commandName(cmd.command)) + " " + colorize(ctx, LogColor::Yellow, scopeName(cmd)));
    if (cmd.command == CommandKind::Build || cmd.command == CommandKind::Run || cmd.command == CommandKind::Test)
        parts.push_back(colorize(ctx, LogColor::Gray, cmd.buildCfg));

    printLine(ctx, 0, LogColor::Gray, LogSymbol::DotCenter, {}, parts);
}

TimedActionLog::ScopedStage::ScopedStage(const TaskContext& ctx, const Stage stage, Utf8 detail) :
    ctx_(&ctx),
    stage_(stage),
    startTick_(Clock::now()),
    startSnapshot_(StatsSnapshot::capture()),
    printEnabled_(!ctx.global().logger().stageOutputMuted())
{
    const auto* moduleLog = ctx.hasCompiler() ? ctx.compiler().workspaceModuleLogState() : nullptr;

    // Inside a workspace module only the Module line is interesting; its sub-stages stay quiet.
    if (moduleLog && stage != Stage::Module)
        printEnabled_ = false;

    if (!detail.empty())
        detail_ = std::move(detail);
    else if (stage == Stage::Workspace)
        detail_ = colorize(ctx, LogColor::Yellow, scopeName(ctx.cmdLine()));
    else if (stage == Stage::Module)
        detail_ = colorize(ctx, LogColor::Yellow, moduleLog ? moduleLog->name : scopeName(ctx.cmdLine()));
}

TimedActionLog::ScopedStage::~ScopedStage()
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

    auto color = LogColor::BrightGreen;
    auto glyph = LogSymbol::Check;
    if (outcome == StageOutcome::Error)
    {
        color = LogColor::BrightRed;
        glyph = LogSymbol::Error;
    }
    else if (outcome == StageOutcome::Warning)
    {
        color = LogColor::BrightYellow;
        glyph = LogSymbol::Warning;
    }

    const uint64_t durationNs = std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - startTick_).count();
    const Utf8     time       = colorize(*ctx_, LogColor::Gray, Utf8Helper::toNiceTime(Timer::toSeconds(durationNs)));

    printLine(*ctx_, 0, color, glyph, stageLabel(stage_), {detail_, stat_, time});
}

StatsSnapshot TimedActionLog::ScopedStage::delta() const
{
    const StatsSnapshot now = StatsSnapshot::capture();
    StatsSnapshot       result;
    result.timeTotal               = now.timeTotal - std::min(now.timeTotal, startSnapshot_.timeTotal);
    result.numErrors               = now.numErrors - std::min(now.numErrors, startSnapshot_.numErrors);
    result.numWarnings             = now.numWarnings - std::min(now.numWarnings, startSnapshot_.numWarnings);
    result.numFiles                = now.numFiles - std::min(now.numFiles, startSnapshot_.numFiles);
    result.numTests                = now.numTests - std::min(now.numTests, startSnapshot_.numTests);
    result.numTokens               = now.numTokens - std::min(now.numTokens, startSnapshot_.numTokens);
    result.numFormatRewrittenFiles = now.numFormatRewrittenFiles - std::min(now.numFormatRewrittenFiles, startSnapshot_.numFormatRewrittenFiles);
    return result;
}

void TimedActionLog::ScopedStage::markOutcome(const StageOutcome outcome) { forcedOutcome_ = outcome; }
void TimedActionLog::ScopedStage::markFailure() { markOutcome(StageOutcome::Error); }
void TimedActionLog::ScopedStage::markWarning() { markOutcome(StageOutcome::Warning); }
void TimedActionLog::ScopedStage::setStat(Utf8 stat) { stat_ = std::move(stat); }

SWC_END_NAMESPACE();

#include "pch.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

using Stage         = ScopedTimedLog::Stage;
using StatsSnapshot = ScopedTimedLog::StatsSnapshot;

namespace
{
    Utf8 plural(const size_t value, const std::string_view singular, const char* plural)
    {
        if (value == 1)
            return Utf8{singular};

        if (plural)
            return Utf8{plural};

        return Utf8{singular} + "s";
    }

    std::string_view stageName(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace: return "workspace";
            case Stage::Module: return "module";
            case Stage::Format: return "format";
            case Stage::Syntax: return "syntax";
            case Stage::Sema: return "sema";
            case Stage::Doc: return "doc";
            case Stage::JIT: return "jit";
            case Stage::Micro: return "micro";
            case Stage::Build: return "build";
            case Stage::Run: return "run";
            case Stage::Test: return "test";
            case Stage::Verify: return "verify";
            case Stage::Unittest: return "unittest";
        }

        SWC_UNREACHABLE();
    }

    std::string_view outcomeName(const ScopedTimedLog::StageOutcome outcome, const bool upToDate)
    {
        switch (outcome)
        {
            case ScopedTimedLog::StageOutcome::Success: return upToDate ? "up-to-date" : "ok";
            case ScopedTimedLog::StageOutcome::Warning: return "warning";
            case ScopedTimedLog::StageOutcome::Error: return "error";
        }

        SWC_UNREACHABLE();
    }

    // What the command operates on: workspace / module / directory name.
    Utf8 scopeName(const CommandLine& cmd)
    {
        if (cmd.command == CommandKind::New)
        {
            if (cmd.newProjectKind == NewProjectKind::Script)
            {
                fs::path scriptPath = cmd.newScriptPath.empty() ? fs::path{"hello.swgs"} : cmd.newScriptPath;
                if (scriptPath.extension().empty())
                    scriptPath += ".swgs";

                return Utf8{scriptPath.string()};
            }

            if (!cmd.workspacePath.empty())
                return Utf8{cmd.workspacePath.filename().string()};

            return cmd.newProjectName;
        }

        if (!cmd.workspacePath.empty())
        {
            Utf8 name{cmd.workspacePath.filename().string()};
            if (!cmd.workspaceModuleFilter.empty())
                name += " [" + cmd.workspaceModuleFilter + "]";
            else if (cmd.workspaceModuleSelection.size() == 1)
                name += " [" + *cmd.workspaceModuleSelection.begin() + "]";
            else if (!cmd.workspaceModuleSelection.empty())
                name += std::format(" [{} roots]", cmd.workspaceModuleSelection.size());

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

    // Every stage line has the same shape: <name> <outcome>: part, part, part
    void printLine(const TaskContext& ctx, const std::string_view name, const std::string_view outcome, const std::vector<Utf8>& parts)
    {
        if (ctx.cmdLine().silent)
            return;

        Utf8 line{name};
        line += " ";
        line += outcome;

        const Utf8 joined = ScopedTimedLog::joinStatItems(parts);
        if (!joined.empty())
        {
            line += ": ";
            line += joined;
        }

        line += "\n";

        const Logger::ScopedLock lock(ctx.global().logger());
        std::cout << line << std::flush;
    }
}

StatsSnapshot StatsSnapshot::capture()
{
    const Stats& stats = Stats::get();

    StatsSnapshot result;
    result.numErrors               = stats.numErrors.load(std::memory_order_relaxed);
    result.numWarnings             = stats.numWarnings.load(std::memory_order_relaxed);
    result.numFiles                = stats.numFiles.load(std::memory_order_relaxed);
    result.numTests                = stats.numTests.load(std::memory_order_relaxed);
    result.numTestsFailed          = stats.numTestsFailed.load(std::memory_order_relaxed);
    result.numTokens               = stats.numTokens.load(std::memory_order_relaxed);
    result.numFormatRewrittenFiles = stats.numFormatRewrittenFiles.load(std::memory_order_relaxed);
    return result;
}

// "N passed[, M did not pass]" parts of a test-command stage line. A zero total stays
// "0 tests": in test mode, "no test ran" is a result in itself.
void ScopedTimedLog::appendTestStats(std::vector<Utf8>& parts, const size_t executed, const size_t failed)
{
    if (!executed)
        parts.push_back(formatStatCount(0, "test"));
    else
        parts.push_back(Utf8{std::to_string(executed - std::min(executed, failed))} + " passed");

    if (failed)
        parts.push_back(Utf8{std::to_string(failed)} + " did not pass");
}

Utf8 ScopedTimedLog::formatTestLocation(const TaskContext& ctx, const SymbolFunction& function)
{
    if (!function.decl() || function.tokRef().isInvalid())
        return "test";

    const SourceView& srcView = ctx.compiler().srcView(function.srcViewRef());
    if (function.tokRef().get() >= srcView.numTokens())
        return "test";

    const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, function.tokRef());
    const SourceFile*     file      = srcView.file();
    return std::format("{}:{}", file ? file->name() : Utf8{"test"}, codeRange.line);
}

Utf8 ScopedTimedLog::formatStatCount(const size_t value, const std::string_view singular, const char* pluralForm)
{
    return Utf8{std::to_string(value)} + " " + plural(value, singular, pluralForm);
}

Utf8 ScopedTimedLog::formatStatRatio(const size_t value, const size_t total, const std::string_view singular)
{
    return std::format("{}/{} {}", std::to_string(value), std::to_string(total), plural(total, singular, nullptr));
}

Utf8 ScopedTimedLog::joinStatItems(const std::vector<Utf8>& items)
{
    Utf8 result;
    for (const Utf8& item : items)
    {
        if (item.empty())
            continue;

        if (!result.empty())
            result += ", ";
        result += item;
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
        detail_ = scopeName(ctx.cmdLine());
    else if (stage == Stage::Module)
        detail_ = moduleLog ? moduleLog->name : scopeName(ctx.cmdLine());
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
    const Utf8     time       = Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));

    // The workspace line covers every module of a test run, so its test tally has to
    // be computed at print time from the stage delta: the caller-provided stat is
    // refreshed per module and would be stale when a module fails mid-run.
    Utf8 testStat;
    if (stage_ == Stage::Workspace && ctx_->cmdLine().command == CommandKind::Test)
    {
        std::vector<Utf8> parts;
        appendTestStats(parts, d.numTests, d.numTestsFailed);
        testStat = joinStatItems(parts);
    }

    printLine(*ctx_, stageName(stage_), outcomeName(outcome, upToDate_), {detail_, stat_, testStat, time});
}

StatsSnapshot ScopedTimedLog::delta() const
{
    const StatsSnapshot now = StatsSnapshot::capture();
    StatsSnapshot       result;
    result.numErrors               = now.numErrors - std::min(now.numErrors, startSnapshot_.numErrors);
    result.numWarnings             = now.numWarnings - std::min(now.numWarnings, startSnapshot_.numWarnings);
    result.numFiles                = now.numFiles - std::min(now.numFiles, startSnapshot_.numFiles);
    result.numTests                = now.numTests - std::min(now.numTests, startSnapshot_.numTests);
    result.numTestsFailed          = now.numTestsFailed - std::min(now.numTestsFailed, startSnapshot_.numTestsFailed);
    result.numTokens               = now.numTokens - std::min(now.numTokens, startSnapshot_.numTokens);
    result.numFormatRewrittenFiles = now.numFormatRewrittenFiles - std::min(now.numFormatRewrittenFiles, startSnapshot_.numFormatRewrittenFiles);
    return result;
}

void ScopedTimedLog::dismiss()
{
    printEnabled_ = false;
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

ScopedCommandLog::ScopedCommandLog(const TaskContext& ctx, const ExitCode& result) :
    ctx_(&ctx),
    result_(&result),
    startTick_(ScopedTimedLog::Clock::now())
{
}

// The closing line of a run names the command, what it operated on, and how it ended.
ScopedCommandLog::~ScopedCommandLog()
{
    if (ctx_->global().logger().stageOutputMuted())
        return;

    const CommandLine& cmd         = ctx_->cmdLine();
    const Stats&       stats       = Stats::get();
    const size_t       numErrors   = stats.numErrors.load(std::memory_order_relaxed);
    const size_t       numWarnings = stats.numWarnings.load(std::memory_order_relaxed);

    auto outcome = ScopedTimedLog::StageOutcome::Success;
    if (*result_ != ExitCode::Success || numErrors)
        outcome = ScopedTimedLog::StageOutcome::Error;
    else if (numWarnings)
        outcome = ScopedTimedLog::StageOutcome::Warning;

    std::vector<Utf8> parts;
    parts.push_back(Utf8{commandName(cmd.command)} + " " + scopeName(cmd));
    if (cmd.command == CommandKind::Build || isRunLikeCommand(cmd.command) || cmd.command == CommandKind::Test)
        parts.emplace_back(artifactConfigurationName(cmd));
    if (numErrors)
        parts.push_back(ScopedTimedLog::formatStatCount(numErrors, "error"));
    if (numWarnings)
        parts.push_back(ScopedTimedLog::formatStatCount(numWarnings, "warning"));

    const uint64_t durationNs = std::chrono::duration_cast<std::chrono::nanoseconds>(ScopedTimedLog::Clock::now() - startTick_).count();
    parts.push_back(Utf8Helper::toNiceTime(Timer::toSeconds(durationNs)));

    printLine(*ctx_, "command", outcomeName(outcome, false), parts);
}

SWC_END_NAMESPACE();

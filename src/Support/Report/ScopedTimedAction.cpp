#include "pch.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Backend/Runtime.h"
#include "Backend/RuntimeName.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
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

    uint64_t saturatingSub64(const uint64_t lhs, const uint64_t rhs)
    {
        return lhs >= rhs ? lhs - rhs : 0;
    }

    size_t saturatingSubSize(const size_t lhs, const size_t rhs)
    {
        return lhs >= rhs ? lhs - rhs : 0;
    }

    TimedActionLog::StatsSnapshot subtractSnapshot(const TimedActionLog::StatsSnapshot& after, const TimedActionLog::StatsSnapshot& before)
    {
        TimedActionLog::StatsSnapshot result;
        result.timeTotal               = saturatingSub64(after.timeTotal, before.timeTotal);
        result.numErrors               = saturatingSubSize(after.numErrors, before.numErrors);
        result.numWarnings             = saturatingSubSize(after.numWarnings, before.numWarnings);
        result.numFiles                = saturatingSubSize(after.numFiles, before.numFiles);
        result.numTokens               = saturatingSubSize(after.numTokens, before.numTokens);
        result.numFormatRewrittenFiles = saturatingSubSize(after.numFormatRewrittenFiles, before.numFormatRewrittenFiles);
        return result;
    }

    std::string_view stageLabel(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace:
                return "Workspace";
            case Stage::Module:
                return "Module";
            case Stage::Config:
                return "Config";
            case Stage::Modes:
                return "Mode";
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
            case Stage::Workspace:
            case Stage::Module:
                return LogColor::BrightCyan;
            case Stage::Config:
            case Stage::Modes:
            case Stage::Verify:
            case Stage::Unittest:
                return LogColor::Cyan;
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Sema:
                return LogColor::BrightBlue;
            case Stage::JIT:
                return LogColor::BrightCyan;
            case Stage::Micro:
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
                commonRoot = FileSystem::commonPathPrefix(commonRoot, normalized);

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

    Utf8 workspaceDisplayName(const CommandLine& cmdLine)
    {
        if (cmdLine.workspacePath.empty())
            return "workspace";

        Utf8 result = Utf8(cmdLine.workspacePath.filename().string());
        if (!result.empty())
            return result;

        return displayPath(cmdLine.workspacePath);
    }

    Utf8 moduleDisplayName(const CommandLine& cmdLine)
    {
        if (!cmdLine.modulePath.empty())
        {
            Utf8 result = Utf8(cmdLine.modulePath.filename().string());
            if (!result.empty())
                return result;
        }

        if (!cmdLine.moduleFilePath.empty())
        {
            Utf8 result = Utf8(cmdLine.moduleFilePath.parent_path().filename().string());
            if (!result.empty())
                return result;
        }

        return defaultArtifactName(cmdLine);
    }

    bool isModuleInput(const CommandLine& cmdLine)
    {
        return !cmdLine.modulePath.empty() || !cmdLine.moduleFilePath.empty();
    }

    Utf8 formatFileScopeDetail(const CommandLine& cmdLine)
    {
        const Utf8 roots = formatCommandSourceRoots(cmdLine);
        if (roots.empty() || roots == "sources")
            return "files";

        return std::format("files in {}", roots);
    }

    Utf8 formatWorkspaceModuleProgress(const CompilerInstance::WorkspaceModuleLogState& moduleLogState)
    {
        if (!moduleLogState.total)
            return std::format("module {}", moduleLogState.name);

        return std::format("{}/{} {}", moduleLogState.index, moduleLogState.total, moduleLogState.name);
    }

    Utf8 formatCompileScopeDetail(const TaskContext& ctx)
    {
        if (ctx.hasCompiler())
        {
            if (const auto* moduleLogState = ctx.compiler().workspaceModuleLogState())
                return std::format("module {}", moduleLogState->name);
        }

        if (!ctx.cmdLine().workspacePath.empty())
            return std::format("workspace {}", workspaceDisplayName(ctx.cmdLine()));

        if (isModuleInput(ctx.cmdLine()))
            return std::format("module {}", moduleDisplayName(ctx.cmdLine()));

        return formatFileScopeDetail(ctx.cmdLine());
    }

    Utf8 formatCommandValue(const TaskContext& ctx)
    {
        Utf8 result = Utf8(commandName(ctx.cmdLine().command));
        const Utf8 scope = formatCompileScopeDetail(ctx);
        if (!scope.empty())
        {
            result += " ";
            result += scope;
        }

        return result;
    }

    Utf8 stageDetail(const TaskContext& ctx, const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace:
                return std::format("workspace {}", workspaceDisplayName(ctx.cmdLine()));
            case Stage::Module:
                if (ctx.hasCompiler())
                {
                    if (const auto* moduleLogState = ctx.compiler().workspaceModuleLogState())
                        return formatWorkspaceModuleProgress(*moduleLogState);
                }
                return formatCompileScopeDetail(ctx);
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Sema:
            case Stage::JIT:
            case Stage::Micro:
            case Stage::Build:
            case Stage::Run:
                return formatCompileScopeDetail(ctx);
            case Stage::Verify:
                return "expected checks";
            case Stage::Unittest:
                return "internal compiler tests";
            default:
                return {};
        }
    }

    Utf8 formatWorkspaceProgress(const CompilerInstance::WorkspaceBuildLogState& workspaceLogState, const bool hasErrors)
    {
        if (!workspaceLogState.activeModules)
            return {};

        if (hasErrors && workspaceLogState.builtModules < workspaceLogState.activeModules)
            return std::format("{}/{} modules", Utf8Helper::toNiceBigNumber(workspaceLogState.builtModules), Utf8Helper::toNiceBigNumber(workspaceLogState.activeModules));

        const size_t completedModules = workspaceLogState.builtModules ? workspaceLogState.builtModules : workspaceLogState.activeModules;
        return Utf8Helper::countWithLabel(completedModules, "module");
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

    Utf8 formatTitleValueLine(const TaskContext& ctx, const Utf8& glyph, const LogColor glyphColor, const std::string_view title, const LogColor titleColor, const std::string_view value, const LogColor valueColor)
    {
        Utf8 line;
        line += "  ";
        line += colorize(ctx, glyphColor, glyph);
        line += "  ";
        line += colorize(ctx, titleColor, std::format("{:<{}}", title, ACTION_LABEL_WIDTH));
        line += " ";
        line += colorize(ctx, valueColor, value);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatCommandHeader(const TaskContext& ctx)
    {
        return formatTitleValueLine(ctx, stageStartGlyph(ctx), LogColor::BrightCyan, "Command", LogColor::BrightCyan, formatCommandValue(ctx), LogColor::White);
    }

    void appendStageText(Utf8& line, const TaskContext& ctx, const Stage stage, const std::string_view detail)
    {
        line += colorize(ctx, stageColor(stage), std::format("{:<{}}", stageLabel(stage), ACTION_LABEL_WIDTH));
        if (!detail.empty())
        {
            line += " ";
            line += colorize(ctx, LogColor::White, detail);
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

    void appendStageMetric(Utf8& line, const TaskContext& ctx, const Utf8& metric)
    {
        if (metric.empty())
            return;

        const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
        line += " ";
        line += colorize(ctx, LogColor::Gray, bullet);
        line += " ";
        line += colorize(ctx, LogColor::White, metric);
    }

    Utf8 formatStageEnd(const TaskContext& ctx, const Stage stage, const std::string_view detail, const TimedActionLog::StageOutcome outcome, const uint64_t durationNs, const Utf8& stat)
    {
        const auto label           = stageLabel(stage);
        const Utf8 duration        = Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));
        const auto outcomeLogColor = stageOutcomeColor(stage, outcome);

        Utf8 line;
        line += "  ";
        line += colorize(ctx, outcomeLogColor, stageOutcomeGlyph(ctx, outcome));
        line += "  ";
        line += colorize(ctx, outcomeLogColor, std::format("{:<{}}", label, ACTION_LABEL_WIDTH));
        if (!detail.empty())
        {
            line += " ";
            line += colorize(ctx, LogColor::White, detail);
        }
        appendStageMetric(line, ctx, duration);
        appendStageMetric(line, ctx, stat);
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

        std::vector<Utf8> parts;
        if (ctx.hasCompiler())
        {
            if (const auto* moduleLogState = ctx.compiler().workspaceModuleLogState())
                parts.push_back(std::format("module {}", moduleLogState->name));
        }
        if (parts.empty() && isModuleInput(cmdLine))
        {
            parts.push_back(std::format("module {}", moduleDisplayName(cmdLine)));
        }

        parts.push_back(cmdLine.buildCfg);
        parts.push_back(backendKindName(buildCfg.backendKind));
        parts.push_back(targetArchName(cmdLine.targetArch));
        return joinParts(ctx, parts, LogColor::Gray);
    }
}

TimedActionLog::StatsSnapshot TimedActionLog::StatsSnapshot::capture()
{
    const Stats& stats = Stats::get();

    StatsSnapshot result;
    result.timeTotal               = stats.timeTotal.load(std::memory_order_relaxed);
    result.numErrors               = stats.numErrors.load(std::memory_order_relaxed);
    result.numWarnings             = stats.numWarnings.load(std::memory_order_relaxed);
    result.numFiles                = stats.numFiles.load(std::memory_order_relaxed);
    result.numTokens               = stats.numTokens.load(std::memory_order_relaxed);
    result.numFormatRewrittenFiles = stats.numFormatRewrittenFiles.load(std::memory_order_relaxed);

    return result;
}

Utf8 TimedActionLog::formatCommandHeaderLine(const TaskContext& ctx)
{
    return formatCommandHeader(ctx);
}

void TimedActionLog::printCommandHeader(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());
    Utf8                     line = formatCommandHeader(ctx);
    line += "\n";
    printLineLocked(ctx, line);
}

void TimedActionLog::printBuildConfiguration(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;
    if (ctx.hasCompiler() && ctx.compiler().suppressBuildConfigurationLog())
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

TimedActionLog::ScopedStage::ScopedStage(const TaskContext& ctx, const Stage stage, Utf8 detail) :
    ctx_(&ctx),
    stage_(stage),
    startTick_(Clock::now()),
    startSnapshot_(StatsSnapshot::capture()),
    detail_(detail.empty() ? stageDetail(ctx, stage) : std::move(detail)),
    printEnabled_(!ctx.global().logger().stageOutputMuted())
{
    if (!printEnabled_)
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());

    Utf8 line = formatStageStart(ctx, stage_, detail_);
    line += "\n";
    printLineLocked(ctx, line);
}

TimedActionLog::ScopedStage::~ScopedStage()
{
    if (!ctx_)
        return;

    const uint64_t durationNs =
        std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - startTick_).count();

    const StatsSnapshot deltaSnapshot = delta();

    StageOutcome outcome = classifyOutcome({}, deltaSnapshot);
    if (forcedOutcome_.has_value())
        outcome = mergeOutcome(outcome, forcedOutcome_.value());

    if (!printEnabled_)
        return;

    const Logger::ScopedLock loggerLock(ctx_->global().logger());

    Utf8 line = formatStageEnd(*ctx_, stage_, detail_, outcome, durationNs, stat_);
    line += "\n";
    printLineLocked(*ctx_, line);
}

TimedActionLog::StatsSnapshot TimedActionLog::ScopedStage::delta() const
{
    return subtractSnapshot(StatsSnapshot::capture(), startSnapshot_);
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

    const bool hasErrors    = snapshot.numErrors != 0;
    const bool hasWarnings  = snapshot.numWarnings != 0;
    const bool isWorkspace  = !ctx.cmdLine().workspacePath.empty() && (!ctx.hasCompiler() || ctx.compiler().workspaceModuleLogState() == nullptr);
    const bool isModuleMode = !isWorkspace && isModuleInput(ctx.cmdLine());

    std::vector<ColoredPart> parts;

    if (isWorkspace)
    {
        parts.push_back({std::format("workspace {}", workspaceDisplayName(ctx.cmdLine())), LogColor::White});
        if (ctx.hasCompiler())
        {
            const auto& workspaceLogState = ctx.compiler().workspaceBuildLogState();
            const Utf8  workspaceProgress  = formatWorkspaceProgress(workspaceLogState, hasErrors);
            if (!workspaceProgress.empty())
                parts.push_back({workspaceProgress, LogColor::White});
            if (workspaceLogState.ignoredModules)
                parts.push_back({Utf8Helper::countWithLabel(workspaceLogState.ignoredModules, "ignored module"), LogColor::Gray});
        }
    }
    else if (isModuleMode)
    {
        parts.push_back({std::format("module {}", moduleDisplayName(ctx.cmdLine())), LogColor::White});
    }

    if (snapshot.numFiles)
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numFiles, "file"), LogColor::White});

    uint64_t summaryTimeNs = snapshot.timeTotal;
    if (ctx.hasCompiler() && ctx.compiler().commandWallTimeNs())
        summaryTimeNs = ctx.compiler().commandWallTimeNs();
    parts.push_back({Utf8Helper::toNiceTime(Timer::toSeconds(summaryTimeNs)), LogColor::White});

    if (ctx.cmdLine().command == CommandKind::Format && !ctx.cmdLine().dryRun && snapshot.numErrors == 0)
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numFormatRewrittenFiles, "written file"), LogColor::Gray});

    if (snapshot.numWarnings)
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numWarnings, "warning"), LogColor::BrightYellow});
    if (snapshot.numErrors)
    {
        parts.push_back({Utf8Helper::countWithLabel(snapshot.numErrors, "error"), LogColor::BrightRed});
    }
    else if (!hasWarnings && !isWorkspace)
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

    const auto summaryColor   = hasErrors ? LogColor::BrightRed : LogColor::BrightGreen;
    const auto summaryOutcome = hasErrors ? StageOutcome::Error : StageOutcome::Success;

    Utf8 line;
    line += "  ";
    line += colorize(ctx, summaryColor, stageOutcomeGlyph(ctx, summaryOutcome));
    line += "  ";
    line += colorize(ctx, summaryColor, std::format("{:<{}}", hasErrors ? "Failed" : "Completed", ACTION_LABEL_WIDTH));
    if (!summaryText.empty())
    {
        line += " ";
        line += summaryText;
    }
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

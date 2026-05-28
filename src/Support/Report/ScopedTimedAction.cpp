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
    constexpr size_t LINE_BASE_INDENT   = 2;
    constexpr size_t LINE_INDENT_STEP   = 2;
    constexpr size_t VALUE_COLUMN       = LINE_BASE_INDENT + 2 * LINE_INDENT_STEP + 1 + 2 + ACTION_LABEL_WIDTH + 1;

    constexpr LogColor structureColor()
    {
        return LogColor::Cyan;
    }

    constexpr LogColor emphasisColor()
    {
        return LogColor::BrightCyan;
    }

    constexpr LogColor primaryTextColor()
    {
        return LogColor::White;
    }

    constexpr LogColor secondaryTextColor()
    {
        return LogColor::Gray;
    }

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

    LogColor stageLabelColor(const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace:
            case Stage::Module:
            case Stage::Config:
            case Stage::Modes:
            case Stage::Verify:
            case Stage::Unittest:
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Sema:
            case Stage::JIT:
            case Stage::Micro:
            case Stage::Build:
            case Stage::Run:
                return structureColor();
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
        SWC_UNUSED(stage);
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
        Utf8 result;
        if (cmdLine.workspacePath.empty())
            result = "workspace";
        else
        {
            result = Utf8(cmdLine.workspacePath.filename().string());
            if (result.empty())
                result = displayPath(cmdLine.workspacePath);
        }

        if (cmdLine.workspaceModuleFilter.empty())
            return result;

        result += " [";
        result += cmdLine.workspaceModuleFilter;
        result += "]";
        return result;
    }

    Utf8 moduleDisplayName(const CommandLine& cmdLine)
    {
        if (!cmdLine.modulePath.empty())
        {
            auto result = Utf8(cmdLine.modulePath.filename().string());
            if (!result.empty())
                return result;
        }

        if (!cmdLine.moduleFilePath.empty())
        {
            auto result = Utf8(cmdLine.moduleFilePath.parent_path().filename().string());
            if (!result.empty())
                return result;
        }

        return defaultArtifactName(cmdLine);
    }

    bool isModuleInput(const CommandLine& cmdLine)
    {
        return !cmdLine.modulePath.empty() || !cmdLine.moduleFilePath.empty();
    }

    Utf8 colorize(const TaskContext& ctx, const LogColor color, const std::string_view text)
    {
        Utf8 result;
        result += LogColorHelper::toAnsi(ctx, color);
        result += text;
        return result;
    }

    size_t stageIndentLevel(const TaskContext& ctx, const Stage stage)
    {
        if (!ctx.hasCompiler() || !ctx.compiler().workspaceModuleLogState())
            return 0;
        if (stage == Stage::Module)
            return 1;
        return 2;
    }

    bool shouldPrintSpacerBeforeStage(const TaskContext& ctx, const Stage stage)
    {
        SWC_UNUSED(ctx);
        SWC_UNUSED(stage);
        return false;
    }

    void appendLineIndent(Utf8& line, const size_t indentLevel)
    {
        line.append(LINE_BASE_INDENT + indentLevel * LINE_INDENT_STEP, ' ');
    }

    size_t actionPrefixWidth(const size_t indentLevel, const std::string_view glyph)
    {
        return LINE_BASE_INDENT + indentLevel * LINE_INDENT_STEP + Utf8Helper::countChars(glyph) + 2 + ACTION_LABEL_WIDTH;
    }

    void appendAlignedValue(Utf8& line, const size_t prefixWidth, const Utf8& value)
    {
        if (value.empty())
            return;

        const size_t valuePadding = prefixWidth < VALUE_COLUMN ? VALUE_COLUMN - prefixWidth : 1;
        line.append(valuePadding, ' ');
        line += value;
    }

    Utf8 formatScopeEntity(const TaskContext& ctx, const std::string_view kind, const std::string_view name)
    {
        return TimedActionLog::formatStatEntity(ctx, kind, name, secondaryTextColor(), emphasisColor());
    }

    Utf8 formatFileScopeDetail(const TaskContext& ctx)
    {
        const Utf8 roots = formatCommandSourceRoots(ctx.cmdLine());
        if (roots.empty() || roots == "sources")
            return colorize(ctx, secondaryTextColor(), "files");

        Utf8 result;
        result += colorize(ctx, secondaryTextColor(), "files");
        result += " ";
        result += colorize(ctx, secondaryTextColor(), "in");
        result += " ";
        result += colorize(ctx, emphasisColor(), roots);
        return result;
    }

    Utf8 formatWorkspaceModuleProgress(const TaskContext& ctx, const CompilerInstance::WorkspaceModuleLogState& moduleLogState)
    {
        if (!moduleLogState.total)
            return colorize(ctx, emphasisColor(), moduleLogState.name);

        Utf8 result;
        result += colorize(ctx, primaryTextColor(), std::format("{}/{}", moduleLogState.index, moduleLogState.total));
        result += " ";
        result += colorize(ctx, emphasisColor(), moduleLogState.name);
        return result;
    }

    Utf8 formatCompileScopeDetail(const TaskContext& ctx)
    {
        if (!ctx.cmdLine().workspacePath.empty() && (!ctx.hasCompiler() || !ctx.compiler().workspaceModuleLogState()))
            return formatScopeEntity(ctx, "workspace", workspaceDisplayName(ctx.cmdLine()));

        if (isModuleInput(ctx.cmdLine()))
            return formatScopeEntity(ctx, "module", moduleDisplayName(ctx.cmdLine()));

        return formatFileScopeDetail(ctx);
    }

    Utf8 formatCommandValue(const TaskContext& ctx)
    {
        Utf8       result = colorize(ctx, emphasisColor(), commandName(ctx.cmdLine().command));
        const Utf8 scope  = formatCompileScopeDetail(ctx);
        if (!scope.empty())
        {
            result += " ";
            result += scope;
        }

        return result;
    }

    bool shouldElideModuleScopeInStageDetail(const TaskContext& ctx, const Stage stage)
    {
        if (ctx.cmdLine().command != CommandKind::Test)
            return false;
        if (!isModuleInput(ctx.cmdLine()))
            return false;

        switch (stage)
        {
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Sema:
            case Stage::JIT:
            case Stage::Micro:
            case Stage::Build:
            case Stage::Run:
                return true;
            default:
                return false;
        }
    }

    Utf8 stageDetail(const TaskContext& ctx, const Stage stage)
    {
        switch (stage)
        {
            case Stage::Workspace:
                return colorize(ctx, emphasisColor(), workspaceDisplayName(ctx.cmdLine()));
            case Stage::Module:
                if (ctx.hasCompiler())
                {
                    if (const auto* moduleLogState = ctx.compiler().workspaceModuleLogState())
                        return formatWorkspaceModuleProgress(ctx, *moduleLogState);
                }
                return formatCompileScopeDetail(ctx);
            case Stage::Format:
            case Stage::Syntax:
            case Stage::Sema:
            case Stage::JIT:
            case Stage::Micro:
            case Stage::Build:
            case Stage::Run:
                if (ctx.hasCompiler() && ctx.compiler().workspaceModuleLogState())
                    return {};
                if (shouldElideModuleScopeInStageDetail(ctx, stage))
                    return {};
                return formatCompileScopeDetail(ctx);
            case Stage::Verify:
                return TimedActionLog::formatStatText(ctx, "expected checks");
            case Stage::Unittest:
                return TimedActionLog::formatStatText(ctx, "internal compiler tests");
            default:
                return {};
        }
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

    Utf8 joinParts(const TaskContext& ctx, const std::vector<Utf8>& parts)
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
                result += colorize(ctx, secondaryTextColor(), bullet);
                result += " ";
            }
            result += part;
            first = false;
        }

        return result;
    }

    Utf8 pluralLabel(const size_t value, const std::string_view singular, const char* plural)
    {
        if (value == 1)
            return Utf8{singular};

        if (plural)
            return Utf8{plural};

        Utf8 result(singular);
        result += "s";
        return result;
    }

    Utf8 resetColor(const TaskContext& ctx)
    {
        return LogColorHelper::toAnsi(ctx, LogColor::Reset);
    }

    Utf8 formatTitleValueLine(const TaskContext& ctx, const Utf8& glyph, const LogColor glyphColor, const std::string_view title, const LogColor titleColor, const Utf8& value)
    {
        Utf8 line;
        appendLineIndent(line, 0);
        line += colorize(ctx, glyphColor, glyph);
        line += "  ";
        line += colorize(ctx, titleColor, std::format("{:<{}}", title, ACTION_LABEL_WIDTH));
        appendAlignedValue(line, actionPrefixWidth(0, glyph), value);
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatCommandHeader(const TaskContext& ctx)
    {
        return formatTitleValueLine(ctx, stageStartGlyph(ctx), emphasisColor(), "Command", emphasisColor(), formatCommandValue(ctx));
    }

    Utf8 stagePayload(const TaskContext& ctx, const std::string_view detail, const Utf8& stat, const std::optional<uint64_t> durationNs = {})
    {
        std::vector<Utf8> parts;
        if (!detail.empty())
            parts.emplace_back(detail);
        if (!stat.empty())
            parts.push_back(stat);
        if (durationNs.has_value())
            parts.push_back(TimedActionLog::formatStatDuration(ctx, durationNs.value()));
        return joinParts(ctx, parts);
    }

    void appendStageText(Utf8& line, const TaskContext& ctx, const Stage stage)
    {
        line += colorize(ctx, stageLabelColor(stage), std::format("{:<{}}", stageLabel(stage), ACTION_LABEL_WIDTH));
    }

    Utf8 formatStageStart(const TaskContext& ctx, const Stage stage, const std::string_view detail)
    {
        const size_t indentLevel = stageIndentLevel(ctx, stage);
        const Utf8   glyph       = stageStartGlyph(ctx);
        Utf8         line;
        appendLineIndent(line, indentLevel);
        line += colorize(ctx, stageLabelColor(stage), glyph);
        line += "  ";
        appendStageText(line, ctx, stage);
        appendAlignedValue(line, actionPrefixWidth(indentLevel, glyph), stagePayload(ctx, detail, {}));
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatInfoStageLine(const TaskContext& ctx, const Stage stage, const std::string_view detail)
    {
        const size_t indentLevel = stageIndentLevel(ctx, stage);
        const Utf8   glyph       = stageStartGlyph(ctx);
        Utf8         line;
        appendLineIndent(line, indentLevel);
        line += colorize(ctx, stageLabelColor(stage), glyph);
        line += "  ";
        appendStageText(line, ctx, stage);
        appendAlignedValue(line, actionPrefixWidth(indentLevel, glyph), stagePayload(ctx, detail, {}));
        line += resetColor(ctx);
        return line;
    }

    Utf8 formatStageEnd(const TaskContext& ctx, const Stage stage, const std::string_view detail, const TimedActionLog::StageOutcome outcome, const uint64_t durationNs, const Utf8& stat)
    {
        const size_t indentLevel = stageIndentLevel(ctx, stage);
        const Utf8   glyph       = stageOutcomeGlyph(ctx, outcome);
        const auto   labelColor  = stageLabelColor(stage);
        const auto   glyphColor  = stageOutcomeColor(stage, outcome);

        Utf8 line;
        appendLineIndent(line, indentLevel);
        line += colorize(ctx, glyphColor, glyph);
        line += "  ";
        line += colorize(ctx, labelColor, std::format("{:<{}}", stageLabel(stage), ACTION_LABEL_WIDTH));
        appendAlignedValue(line, actionPrefixWidth(indentLevel, glyph), stagePayload(ctx, detail, stat, durationNs));
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
        const Runtime::BuildCfg& buildCfg = ctx.hasCompiler() ? ctx.compiler().buildCfg() : cmdLine.defaultBuildCfg;

        std::vector<Utf8> parts;
        parts.push_back(TimedActionLog::formatStatText(ctx, cmdLine.buildCfg));
        parts.push_back(TimedActionLog::formatStatText(ctx, backendKindName(buildCfg.backendKind)));
        parts.push_back(TimedActionLog::formatStatText(ctx, targetArchName(cmdLine.targetArch)));
        return joinParts(ctx, parts);
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

Utf8 TimedActionLog::formatStatText(const TaskContext& ctx, const std::string_view text, const LogColor color)
{
    return colorize(ctx, color, text);
}

Utf8 TimedActionLog::formatStatCount(const TaskContext& ctx, const size_t value, const std::string_view singular, const char* plural, const LogColor color)
{
    Utf8 result;
    result += colorize(ctx, color, Utf8Helper::toNiceBigNumber(value));
    result += " ";
    result += colorize(ctx, color, pluralLabel(value, singular, plural));
    return result;
}

Utf8 TimedActionLog::formatStatRatio(const TaskContext& ctx, const size_t value, const size_t total, const std::string_view singular, const char* plural, const LogColor color)
{
    Utf8 result;
    result += colorize(ctx, color, Utf8Helper::toNiceBigNumber(value));
    result += colorize(ctx, color, "/");
    result += colorize(ctx, color, Utf8Helper::toNiceBigNumber(total));
    result += " ";
    result += colorize(ctx, color, pluralLabel(total, singular, plural));
    return result;
}

Utf8 TimedActionLog::formatStatDuration(const TaskContext& ctx, const uint64_t durationNs, const LogColor color)
{
    return colorize(ctx, color, Utf8Helper::toNiceTime(Timer::toSeconds(durationNs)));
}

Utf8 TimedActionLog::formatStatName(const TaskContext& ctx, const std::string_view name, const LogColor color)
{
    return colorize(ctx, color, name);
}

Utf8 TimedActionLog::formatStatEntity(const TaskContext& ctx, const std::string_view kind, const std::string_view name, const LogColor kindColor, const LogColor nameColor)
{
    Utf8 result;
    if (!kind.empty())
        result += colorize(ctx, kindColor, kind);
    if (!kind.empty() && !name.empty())
        result += " ";
    if (!name.empty())
        result += colorize(ctx, nameColor, name);
    return result;
}

Utf8 TimedActionLog::joinStatItems(const TaskContext& ctx, const std::vector<Utf8>& items)
{
    return joinParts(ctx, items);
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

    Utf8 line = formatInfoStageLine(ctx, Stage::Config, formatBuildConfiguration(ctx));
    line += "\n";
    printLineLocked(ctx, line);
}

void TimedActionLog::printSessionFlags(const TaskContext& ctx)
{
    if (ctx.global().logger().stageOutputMuted())
        return;

    std::vector<Utf8> flags;

#if SWC_DEBUG
    flags.push_back(formatStatText(ctx, "debug"));
#elif SWC_DEV_MODE
    flags.push_back(formatStatText(ctx, "devmode"));
#elif SWC_STATS
    flags.push_back(formatStatText(ctx, "stats"));
#endif

#if SWC_DEBUG || SWC_DEV_MODE
    if (ctx.cmdLine().randomize)
        flags.push_back(formatStatText(ctx, std::format("randomize seed={}", ctx.global().jobMgr().randSeed())));
#endif

    if (flags.empty())
        return;

    const Logger::ScopedLock loggerLock(ctx.global().logger());

    Utf8 line = formatInfoStageLine(ctx, Stage::Modes, joinParts(ctx, flags));
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
    if (shouldPrintSpacerBeforeStage(ctx, stage_))
        printLineLocked(ctx, "\n");

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
    const bool hasErrors    = snapshot.numErrors != 0;
    const bool hasWarnings  = snapshot.numWarnings != 0;
    const bool isWorkspace  = !ctx.cmdLine().workspacePath.empty() && (!ctx.hasCompiler() || ctx.compiler().workspaceModuleLogState() == nullptr);
    const bool isModuleMode = !isWorkspace && isModuleInput(ctx.cmdLine());

    std::vector<Utf8> parts;

    if (isWorkspace)
    {
        parts.push_back(formatStatEntity(ctx, "workspace", workspaceDisplayName(ctx.cmdLine())));
        if (ctx.hasCompiler())
        {
            const auto& workspaceLogState = ctx.compiler().workspaceBuildLogState();
            if (workspaceLogState.activeModules)
            {
                if (hasErrors && workspaceLogState.builtModules < workspaceLogState.activeModules)
                    parts.push_back(formatStatRatio(ctx, workspaceLogState.builtModules, workspaceLogState.activeModules, "module"));
                else
                    parts.push_back(formatStatCount(ctx, workspaceLogState.activeModules, "module"));
            }
        }
    }
    else if (isModuleMode)
    {
        parts.push_back(formatStatEntity(ctx, "module", moduleDisplayName(ctx.cmdLine())));
    }

    if (snapshot.numFiles)
        parts.push_back(formatStatCount(ctx, snapshot.numFiles, "file"));

    uint64_t summaryTimeNs = snapshot.timeTotal;
    if (ctx.hasCompiler() && ctx.compiler().commandWallTimeNs())
        summaryTimeNs = ctx.compiler().commandWallTimeNs();

    if (ctx.cmdLine().command == CommandKind::Format && !ctx.cmdLine().dryRun && snapshot.numErrors == 0)
        parts.push_back(formatStatCount(ctx, snapshot.numFormatRewrittenFiles, "written file"));

    if (snapshot.numWarnings)
        parts.push_back(formatStatCount(ctx, snapshot.numWarnings, "warning", nullptr, LogColor::BrightYellow));
    if (snapshot.numErrors)
    {
        parts.push_back(formatStatCount(ctx, snapshot.numErrors, "error", nullptr, LogColor::BrightRed));
    }
    else if (!hasWarnings && !isWorkspace)
    {
        const Utf8 artifactLabel = ctx.hasCompiler() ? ctx.compiler().lastArtifactLabel() : Utf8{};
        if (!artifactLabel.empty())
            parts.push_back(formatStatName(ctx, artifactLabel));
    }
    parts.push_back(formatStatDuration(ctx, summaryTimeNs));

    const Utf8 bullet = LogSymbolHelper::toString(ctx, LogSymbol::DotList);
    Utf8       summaryText;
    bool       first = true;
    for (const Utf8& part : parts)
    {
        if (part.empty())
            continue;

        if (!first)
        {
            summaryText += " ";
            summaryText += colorize(ctx, secondaryTextColor(), bullet);
            summaryText += " ";
        }
        summaryText += part;
        first = false;
    }

    const auto summaryColor   = hasErrors ? LogColor::BrightRed : LogColor::BrightGreen;
    const auto summaryOutcome = hasErrors ? StageOutcome::Error : StageOutcome::Success;
    const Utf8 summaryGlyph   = stageOutcomeGlyph(ctx, summaryOutcome);

    Utf8 line;
    appendLineIndent(line, 0);
    line += colorize(ctx, summaryColor, summaryGlyph);
    line += "  ";
    line += colorize(ctx, summaryColor, std::format("{:<{}}", hasErrors ? "Failed" : "Completed", ACTION_LABEL_WIDTH));
    appendAlignedValue(line, actionPrefixWidth(0, summaryGlyph), summaryText);
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

#include "pch.h"

#include "Command/CommandLine.h"
#include "Command/CommandPrint.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::nextInfoGroupStyle;

    void addField(std::vector<Logger::FieldEntry>& entries, const std::string_view label, Utf8 value, LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0)
    {
        if (value.empty())
        {
            value      = "<empty>";
            valueColor = LogColor::Gray;
        }

        Logger::FieldEntry entry;
        entry.label       = Utf8(label);
        entry.value       = std::move(value);
        entry.valueColor  = valueColor;
        entry.indentLevel = indentLevel;
        entries.push_back(std::move(entry));
    }

    void addFieldParts(std::vector<Logger::FieldEntry>& entries, const std::string_view label, std::vector<Logger::FieldValuePart> valueParts, LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0)
    {
        if (valueParts.empty())
        {
            addField(entries, label, "<empty>", LogColor::Gray, indentLevel);
            return;
        }

        Logger::FieldEntry entry;
        entry.label       = Utf8(label);
        entry.valueParts  = std::move(valueParts);
        entry.valueColor  = valueColor;
        entry.indentLevel = indentLevel;
        entries.push_back(std::move(entry));
    }
}

#if SWC_HAS_STATS
namespace
{
    struct TreeNode
    {
        Utf8                                      segment;
        size_t                                    peakBytes    = 0;
        size_t                                    currentBytes = 0;
        size_t                                    totalBytes   = 0;
        size_t                                    allocCount   = 0;
        size_t                                    freeCount    = 0;
        const MemoryProfile::CategorySnapshot*    leaf         = nullptr;
        std::map<Utf8, std::unique_ptr<TreeNode>> children;
    };

    TreeNode& getOrCreateChild(TreeNode& node, std::string_view segment)
    {
        Utf8 key(segment);
        auto it = node.children.find(key);
        if (it == node.children.end())
        {
            auto child     = std::make_unique<TreeNode>();
            child->segment = key;
            it             = node.children.emplace(std::move(key), std::move(child)).first;
        }

        return *it->second;
    }

    void insertIntoTree(TreeNode& root, const MemoryProfile::CategorySnapshot& snap)
    {
        TreeNode*        node = &root;
        std::string_view name = snap.name;

        while (!name.empty())
        {
            const size_t     sep = name.find('/');
            std::string_view segment;
            if (sep == std::string_view::npos)
            {
                segment = name;
                name    = {};
            }
            else
            {
                segment = name.substr(0, sep);
                name    = name.substr(sep + 1);
            }

            node = &getOrCreateChild(*node, segment);
        }

        node->peakBytes += snap.peakBytes;
        node->currentBytes += snap.currentBytes;
        node->totalBytes += snap.totalBytes;
        node->allocCount += snap.allocCount;
        node->freeCount += snap.freeCount;
        node->leaf = &snap;
    }

    void propagateStats(TreeNode& node)
    {
        for (auto& child : node.children | std::views::values)
        {
            propagateStats(*child);
            node.peakBytes += child->peakBytes;
            node.currentBytes += child->currentBytes;
            node.totalBytes += child->totalBytes;
            node.allocCount += child->allocCount;
            node.freeCount += child->freeCount;
        }
    }

    void appendValuePart(std::vector<Logger::FieldValuePart>& parts, Utf8 text, const LogColor color)
    {
        if (text.empty())
            return;

        Logger::FieldValuePart part;
        part.text  = std::move(text);
        part.color = color;
        parts.push_back(std::move(part));
    }

    std::vector<Logger::FieldValuePart> formatMemoryValueParts(const size_t totalPeakBytes, const size_t peakBytes, const size_t totalBytes, const size_t allocCount, const MemoryProfile::CategorySnapshot* leaf)
    {
        const double peakPct = totalPeakBytes ? 100.0 * static_cast<double>(peakBytes) / static_cast<double>(totalPeakBytes) : 0.0;

        std::vector<Logger::FieldValuePart> parts;
        appendValuePart(parts, "peak ", LogColor::Gray);
        appendValuePart(parts, Utf8Helper::toNiceSize(peakBytes), LogColor::White);
        appendValuePart(parts, " (", LogColor::Gray);
        appendValuePart(parts, std::format("{:.1f}%", peakPct), LogColor::White);
        appendValuePart(parts, ")", LogColor::Gray);

        if (totalBytes && totalBytes != peakBytes)
        {
            appendValuePart(parts, ", ", LogColor::Gray);
            appendValuePart(parts, "churn ", LogColor::Gray);
            appendValuePart(parts, Utf8Helper::toNiceSize(totalBytes), LogColor::White);
        }

        if (allocCount)
        {
            appendValuePart(parts, ", ", LogColor::Gray);
            appendValuePart(parts, "allocs ", LogColor::Gray);
            appendValuePart(parts, Utf8Helper::toNiceBigNumber(allocCount), LogColor::White);
        }

        if (leaf && leaf->file)
        {
            std::string_view filePath = leaf->file;
            const size_t     lastSep  = filePath.find_last_of("\\/");
            if (lastSep != std::string_view::npos)
                filePath = filePath.substr(lastSep + 1);

            appendValuePart(parts, ", ", LogColor::Gray);
            appendValuePart(parts, Utf8(filePath), LogColor::Gray);
            appendValuePart(parts, ":", LogColor::Gray);
            appendValuePart(parts, std::format("{}", leaf->line), LogColor::White);
        }

        return parts;
    }

    void appendMemoryTree(std::vector<Logger::FieldEntry>& entries, const TreeNode& node, const size_t totalPeakBytes, const uint32_t depth)
    {
        std::vector<const TreeNode*> sorted;
        sorted.reserve(node.children.size());
        for (const auto& child : node.children | std::views::values)
            sorted.push_back(child.get());
        std::ranges::sort(sorted, [](const TreeNode* lhs, const TreeNode* rhs) { return lhs->peakBytes > rhs->peakBytes; });

        for (const TreeNode* child : sorted)
        {
            if (!child->peakBytes && !child->totalBytes)
                continue;

            addFieldParts(entries, child->segment, formatMemoryValueParts(totalPeakBytes, child->peakBytes, child->totalBytes, child->allocCount, child->leaf), LogColor::White, depth);
            if (!child->children.empty())
                appendMemoryTree(entries, *child, totalPeakBytes, depth + 1);
        }
    }

    struct MicroStageTransition
    {
        const char* countLabel    = nullptr;
        size_t      previousCount = 0;
        size_t      currentCount  = 0;
    };

    void printFormatStats(const TaskContext& ctx, const Stats& stats, bool& hasPrintedGroup)
    {
        std::vector<Logger::FieldEntry> entries;

        const size_t totalFiles         = stats.numFiles.load();
        const size_t rewrittenFiles     = stats.numFormatRewrittenFiles.load();
        const size_t skippedFmtFiles    = stats.numFormatSkipFmtFiles.load();
        const size_t skippedInvalidFile = stats.numFormatSkippedInvalidFiles.load();
        const size_t classifiedFiles    = rewrittenFiles + skippedFmtFiles + skippedInvalidFile;
        const size_t unchangedFiles     = totalFiles >= classifiedFiles ? totalFiles - classifiedFiles : 0;

        addField(entries, "Files", Utf8Helper::countWithLabel(totalFiles, "file"));
        addField(entries, "Rewritten", Utf8Helper::countWithLabel(rewrittenFiles, "file"));
        addField(entries, "Unchanged", Utf8Helper::countWithLabel(unchangedFiles, "file"));
        addField(entries, "SkipFmt", Utf8Helper::countWithLabel(skippedFmtFiles, "file"));
        addField(entries, "Skipped invalid", Utf8Helper::countWithLabel(skippedInvalidFile, "file"));
        addField(entries, "Tokens", Utf8Helper::toNiceBigNumber(stats.numTokens.load()));
        addField(entries, "AST nodes", Utf8Helper::toNiceBigNumber(stats.numAstNodes.load()));
        Logger::printFieldGroup(ctx, "Format", entries, nextInfoGroupStyle(hasPrintedGroup, 32));

        entries.clear();
        addField(entries, "Load file", Utf8Helper::toNiceTime(Timer::toSeconds(stats.timeLoadFile.load())));
        addField(entries, "Lexer", Utf8Helper::toNiceTime(Timer::toSeconds(stats.timeLexer.load())));
        addField(entries, "Parser", Utf8Helper::toNiceTime(Timer::toSeconds(stats.timeParser.load())));
        addField(entries, "Format emit", Utf8Helper::toNiceTime(Timer::toSeconds(stats.timeFormat.load())));
        addField(entries, "File write", Utf8Helper::toNiceTime(Timer::toSeconds(stats.timeFormatWrite.load())));
        Logger::printFieldGroup(ctx, "Timings", entries, nextInfoGroupStyle(hasPrintedGroup, 30));
    }
}
#endif

void Stats::resetCommandMetrics()
{
    Stats& stats = get();

    stats.timeTotal.store(0, std::memory_order_relaxed);
    stats.numErrors.store(0, std::memory_order_relaxed);
    stats.numWarnings.store(0, std::memory_order_relaxed);
    stats.numFiles.store(0, std::memory_order_relaxed);
    stats.numTokens.store(0, std::memory_order_relaxed);
    stats.numFormatRewrittenFiles.store(0, std::memory_order_relaxed);

#if SWC_HAS_STATS
    stats.timeLoadFile.store(0, std::memory_order_relaxed);
    stats.timeLexer.store(0, std::memory_order_relaxed);
    stats.timeParser.store(0, std::memory_order_relaxed);
    stats.timeSema.store(0, std::memory_order_relaxed);
    stats.timeCodeGen.store(0, std::memory_order_relaxed);
    stats.timeMicroLower.store(0, std::memory_order_relaxed);
    stats.timeFormat.store(0, std::memory_order_relaxed);
    stats.timeFormatWrite.store(0, std::memory_order_relaxed);

    stats.numFormatSkipFmtFiles.store(0, std::memory_order_relaxed);
    stats.numFormatSkippedInvalidFiles.store(0, std::memory_order_relaxed);
    stats.numAstNodes.store(0, std::memory_order_relaxed);
    stats.numVisitedAstNodes.store(0, std::memory_order_relaxed);
    stats.numConstants.store(0, std::memory_order_relaxed);
    stats.numConstantBuiltinFastHits.store(0, std::memory_order_relaxed);
    stats.numConstantSmallScalarCacheHits.store(0, std::memory_order_relaxed);
    stats.numConstantSmallScalarCacheMisses.store(0, std::memory_order_relaxed);
    stats.numConstantSlowPathCalls.store(0, std::memory_order_relaxed);
    stats.numConstantMaterializedPayloadFastPath.store(0, std::memory_order_relaxed);
    stats.numTypes.store(0, std::memory_order_relaxed);
    stats.numIdentifiers.store(0, std::memory_order_relaxed);
    stats.numSymbols.store(0, std::memory_order_relaxed);
    stats.numMicroInstrInitial.store(0, std::memory_order_relaxed);
    stats.numMicroInstrAfterStart.store(0, std::memory_order_relaxed);
    stats.numMicroInstrAfterPreRaOptim.store(0, std::memory_order_relaxed);
    stats.numMicroInstrAfterRa.store(0, std::memory_order_relaxed);
    stats.numMicroInstrAfterPostRaSetup.store(0, std::memory_order_relaxed);
    stats.numMicroInstrAfterPostRaOptim.store(0, std::memory_order_relaxed);
    stats.numMicroInstrFinal.store(0, std::memory_order_relaxed);
    stats.numCodeGenFunctions.store(0, std::memory_order_relaxed);
    stats.numMicroSsaBuilds.store(0, std::memory_order_relaxed);
    stats.numMicroSsaInvalidations.store(0, std::memory_order_relaxed);
    stats.timeMicroSsaBuild.store(0, std::memory_order_relaxed);
    stats.timeMicroSsaBlocks.store(0, std::memory_order_relaxed);
    stats.timeMicroSsaDominators.store(0, std::memory_order_relaxed);
    stats.timeMicroSsaPhiPlacement.store(0, std::memory_order_relaxed);
    stats.timeMicroSsaRename.store(0, std::memory_order_relaxed);
#endif
}

void Stats::print(const TaskContext& ctx) const
{
    const Logger::ScopedLock        loggerLock(ctx.global().logger());
    bool                            hasPrintedGroup = false;
    std::vector<Logger::FieldEntry> entries;

    if (ctx.cmdLine().stats)
    {
        entries.clear();
        addField(entries, "Workers", Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
        addField(entries, "Total time", Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));
        addField(entries, "OS peak memory", Utf8Helper::toNiceSize(Os::peakProcessMemoryUsage()));
        Logger::printFieldGroup(ctx, "Session", entries, nextInfoGroupStyle(hasPrintedGroup, 32));
    }

#if SWC_HAS_STATS
    if (ctx.cmdLine().stats)
    {
        if (ctx.cmdLine().command == CommandKind::Format)
        {
            printFormatStats(ctx, *this, hasPrintedGroup);
        }
        else
        {
            entries.clear();
            addField(entries, "Files", Utf8Helper::toNiceBigNumber(numFiles.load()));
            addField(entries, "Tokens", Utf8Helper::toNiceBigNumber(numTokens.load()));
            addField(entries, "AST nodes", Utf8Helper::toNiceBigNumber(numAstNodes.load()));
            addField(entries, "Visited AST nodes", Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));
            Logger::printFieldGroup(ctx, "Frontend", entries, nextInfoGroupStyle(hasPrintedGroup, 32));

            entries.clear();
            addField(entries, "Constants", Utf8Helper::toNiceBigNumber(numConstants.load()));
            addField(entries, "Builtin fast hits", Utf8Helper::toNiceBigNumber(numConstantBuiltinFastHits.load()));
            addField(entries, "Small scalar cache hits", Utf8Helper::toNiceBigNumber(numConstantSmallScalarCacheHits.load()));
            addField(entries, "Small scalar cache misses", Utf8Helper::toNiceBigNumber(numConstantSmallScalarCacheMisses.load()));
            addField(entries, "Slow path calls", Utf8Helper::toNiceBigNumber(numConstantSlowPathCalls.load()));
            addField(entries, "Materialized payload fast path", Utf8Helper::toNiceBigNumber(numConstantMaterializedPayloadFastPath.load()));
            addField(entries, "Types", Utf8Helper::toNiceBigNumber(numTypes.load()));
            addField(entries, "Identifiers", Utf8Helper::toNiceBigNumber(numIdentifiers.load()));
            addField(entries, "Symbols", Utf8Helper::toNiceBigNumber(numSymbols.load()));
            addField(entries, "Codegen functions", Utf8Helper::toNiceBigNumber(numCodeGenFunctions.load()));
            Logger::printFieldGroup(ctx, "Semantic Model", entries, nextInfoGroupStyle(hasPrintedGroup, 34));

            entries.clear();
            const size_t numMicroInitial          = numMicroInstrInitial.load();
            const size_t numMicroAfterStart       = numMicroInstrAfterStart.load();
            const size_t numMicroAfterPreRaOptim  = numMicroInstrAfterPreRaOptim.load();
            const size_t numMicroAfterRa          = numMicroInstrAfterRa.load();
            const size_t numMicroAfterPostRaSetup = numMicroInstrAfterPostRaSetup.load();
            const size_t numMicroAfterPostRaOptim = numMicroInstrAfterPostRaOptim.load();
            const size_t numMicroFinal            = numMicroInstrFinal.load();

            addField(entries, "Initial lowered instructions", Utf8Helper::toNiceBigNumber(numMicroInitial));

            const std::array transitions = {
                MicroStageTransition{"After stack adjust normalize", numMicroInitial, numMicroAfterStart},
                MicroStageTransition{"After pre-RA optim loop", numMicroAfterStart, numMicroAfterPreRaOptim},
                MicroStageTransition{"After legalize/regalloc loop", numMicroAfterPreRaOptim, numMicroAfterRa},
                MicroStageTransition{"After prolog/epilog setup", numMicroAfterRa, numMicroAfterPostRaSetup},
                MicroStageTransition{"After post-RA optim passes", numMicroAfterPostRaSetup, numMicroAfterPostRaOptim},
                MicroStageTransition{"Final sanitized instructions", numMicroAfterPostRaOptim, numMicroFinal},
            };

            for (const MicroStageTransition& transition : transitions)
            {
                const int64_t delta = static_cast<int64_t>(transition.currentCount) - static_cast<int64_t>(transition.previousCount);
                const char    sign  = delta >= 0 ? '+' : '-';
                const size_t  abs   = static_cast<size_t>(std::abs(delta));
                const double  pct   = transition.previousCount != 0 ? 100.0 * static_cast<double>(delta) / static_cast<double>(transition.previousCount) : 0.0;
                addField(entries, transition.countLabel, std::format("{} ({}{} ({:+.2f}%))", Utf8Helper::toNiceBigNumber(transition.currentCount), sign, Utf8Helper::toNiceBigNumber(abs), pct));
            }

            const int64_t pipelineDelta = static_cast<int64_t>(numMicroFinal) - static_cast<int64_t>(numMicroInitial);
            const char    pipelineSign  = pipelineDelta >= 0 ? '+' : '-';
            const size_t  pipelineAbs   = static_cast<size_t>(std::abs(pipelineDelta));
            const double  pipelinePct   = numMicroInitial != 0 ? 100.0 * static_cast<double>(pipelineDelta) / static_cast<double>(numMicroInitial) : 0.0;
            addField(entries, "Initial to final delta", std::format("{}{} ({:+.2f}%)", pipelineSign, Utf8Helper::toNiceBigNumber(pipelineAbs), pipelinePct));
            addField(entries, "SSA builds", Utf8Helper::toNiceBigNumber(numMicroSsaBuilds.load()));
            addField(entries, "SSA invalidations", Utf8Helper::toNiceBigNumber(numMicroSsaInvalidations.load()));
            Logger::printFieldGroup(ctx, "Micro Pipeline", entries, nextInfoGroupStyle(hasPrintedGroup, 36));

            entries.clear();
            addField(entries, "Load file", Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
            addField(entries, "Lexer", Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
            addField(entries, "Parser", Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));
            addField(entries, "Semantic analysis", Utf8Helper::toNiceTime(Timer::toSeconds(timeSema.load())));
            addField(entries, "Codegen", Utf8Helper::toNiceTime(Timer::toSeconds(timeCodeGen.load())));
            addField(entries, "Micro lower", Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroLower.load())));
            addField(entries, "Micro SSA build", Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroSsaBuild.load())));
            addField(entries, "Micro SSA blocks", Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroSsaBlocks.load())));
            addField(entries, "Micro SSA dominators", Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroSsaDominators.load())));
            addField(entries, "Micro SSA phi placement", Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroSsaPhiPlacement.load())));
            addField(entries, "Micro SSA rename", Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroSsaRename.load())));
            Logger::printFieldGroup(ctx, "Timings", entries, nextInfoGroupStyle(hasPrintedGroup, 34));
        }
    }

    if (ctx.cmdLine().statsMem)
    {
        MemoryProfile::Summary summary;
        MemoryProfile::buildSummary(summary);

        entries.clear();
        addField(entries, "Tracked peak", Utf8Helper::toNiceSize(summary.totalPeakBytes));
        addField(entries, "Tracked current", Utf8Helper::toNiceSize(summary.totalCurrentBytes));
        Logger::printFieldGroup(ctx, "Memory Summary", entries, nextInfoGroupStyle(hasPrintedGroup, 32));

        if (!summary.categories.empty())
        {
            TreeNode root;
            for (const auto& cat : summary.categories)
                insertIntoTree(root, cat);
            propagateStats(root);

            entries.clear();
            const size_t taggedPeak = root.peakBytes;
            if (taggedPeak < summary.totalPeakBytes)
            {
                const size_t untaggedPeak = summary.totalPeakBytes - taggedPeak;
                addFieldParts(entries, "Untagged", formatMemoryValueParts(summary.totalPeakBytes, untaggedPeak, 0, 0, nullptr));
            }

            appendMemoryTree(entries, root, summary.totalPeakBytes, 0);
            if (!entries.empty())
                Logger::printFieldGroup(ctx, "Memory Breakdown", entries, nextInfoGroupStyle(hasPrintedGroup, 30));
        }
    }
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

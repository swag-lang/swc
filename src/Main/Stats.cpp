#include "pch.h"

#include "Command/CommandLine.h"
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
    Logger::FieldGroupStyle statsGroupStyle(const bool blankLineBefore, const size_t maxLabelWidth = 32)
    {
        Logger::FieldGroupStyle style;
        style.blankLineBefore = blankLineBefore;
        style.maxLabelWidth   = maxLabelWidth;
        return style;
    }

    Logger::FieldGroupStyle nextStatsGroupStyle(bool& hasPrintedGroup, const size_t maxLabelWidth = 32)
    {
        const Logger::FieldGroupStyle style = statsGroupStyle(hasPrintedGroup, maxLabelWidth);
        hasPrintedGroup                     = true;
        return style;
    }

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

    bool comparePeakBytesDesc(const TreeNode* lhs, const TreeNode* rhs)
    {
        return lhs->peakBytes > rhs->peakBytes;
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

    Utf8 formatMemoryValue(const size_t totalPeakBytes, const size_t peakBytes, const size_t totalBytes, const size_t allocCount, const MemoryProfile::CategorySnapshot* leaf)
    {
        const double peakPct = totalPeakBytes ? 100.0 * static_cast<double>(peakBytes) / static_cast<double>(totalPeakBytes) : 0.0;

        Utf8 value = std::format("peak {} ({:.1f}%)", Utf8Helper::toNiceSize(peakBytes), peakPct);
        if (totalBytes && totalBytes != peakBytes)
            value += std::format(", churn {}", Utf8Helper::toNiceSize(totalBytes));
        if (allocCount)
            value += std::format(", allocs {}", Utf8Helper::toNiceBigNumber(allocCount));

        if (leaf && leaf->file)
        {
            std::string_view filePath = leaf->file;
            const size_t     lastSep  = filePath.find_last_of("\\/");
            if (lastSep != std::string_view::npos)
                filePath = filePath.substr(lastSep + 1);
            value += std::format(", {}:{}", filePath, leaf->line);
        }

        return value;
    }

    void appendMemoryTree(std::vector<Logger::FieldEntry>& entries, const TreeNode& node, const size_t totalPeakBytes, const uint32_t depth)
    {
        std::vector<const TreeNode*> sorted;
        sorted.reserve(node.children.size());
        for (const auto& child : node.children | std::views::values)
            sorted.push_back(child.get());
        std::ranges::sort(sorted, comparePeakBytesDesc);

        for (const TreeNode* child : sorted)
        {
            if (!child->peakBytes && !child->totalBytes)
                continue;

            addField(entries, child->segment, formatMemoryValue(totalPeakBytes, child->peakBytes, child->totalBytes, child->allocCount, child->leaf), LogColor::White, depth);
            if (!child->children.empty())
                appendMemoryTree(entries, *child, totalPeakBytes, depth + 1);
        }
    }

    std::string formatMicroInstrDelta(const int64_t delta, const size_t base)
    {
        const char   sign = delta >= 0 ? '+' : '-';
        const size_t abs  = static_cast<size_t>(std::abs(delta));
        const double pct  = base != 0 ? 100.0 * static_cast<double>(delta) / static_cast<double>(base) : 0.0;
        return std::format("{}{} ({:+.2f}%)", sign, Utf8Helper::toNiceBigNumber(abs), pct);
    }

    std::string formatMicroInstrTotalWithDelta(const size_t currentCount, const size_t previousCount)
    {
        const int64_t delta = static_cast<int64_t>(currentCount) - static_cast<int64_t>(previousCount);
        return std::format("{} ({})", Utf8Helper::toNiceBigNumber(currentCount), formatMicroInstrDelta(delta, previousCount));
    }

    struct MicroStageTransition
    {
        const char* countLabel    = nullptr;
        size_t      previousCount = 0;
        size_t      currentCount  = 0;
    };
}
#endif

void Stats::print(const TaskContext& ctx) const
{
    const Logger::ScopedLock loggerLock(ctx.global().logger());
    bool                     hasPrintedGroup = false;
    std::vector<Logger::FieldEntry> entries;

    if (ctx.cmdLine().stats)
    {
        entries.clear();
        addField(entries, "Workers", Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
        addField(entries, "Total time", Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));
        addField(entries, "OS peak memory", Utf8Helper::toNiceSize(Os::peakProcessMemoryUsage()));
        Logger::printFieldGroup(ctx, "Session", entries, nextStatsGroupStyle(hasPrintedGroup));
    }

#if SWC_HAS_STATS
    if (ctx.cmdLine().stats)
    {
        entries.clear();
        addField(entries, "Files", Utf8Helper::toNiceBigNumber(numFiles.load()));
        addField(entries, "Tokens", Utf8Helper::toNiceBigNumber(numTokens.load()));
        addField(entries, "AST nodes", Utf8Helper::toNiceBigNumber(numAstNodes.load()));
        addField(entries, "Visited AST nodes", Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));
        Logger::printFieldGroup(ctx, "Frontend", entries, nextStatsGroupStyle(hasPrintedGroup));

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
        Logger::printFieldGroup(ctx, "Semantic Model", entries, nextStatsGroupStyle(hasPrintedGroup, 34));

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
            addField(entries, transition.countLabel, formatMicroInstrTotalWithDelta(transition.currentCount, transition.previousCount));

        const int64_t pipelineDelta = static_cast<int64_t>(numMicroFinal) - static_cast<int64_t>(numMicroInitial);
        addField(entries, "Initial to final delta", formatMicroInstrDelta(pipelineDelta, numMicroInitial));
        addField(entries, "SSA builds", Utf8Helper::toNiceBigNumber(numMicroSsaBuilds.load()));
        addField(entries, "SSA invalidations", Utf8Helper::toNiceBigNumber(numMicroSsaInvalidations.load()));
        Logger::printFieldGroup(ctx, "Micro Pipeline", entries, nextStatsGroupStyle(hasPrintedGroup, 36));

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
        Logger::printFieldGroup(ctx, "Timings", entries, nextStatsGroupStyle(hasPrintedGroup, 34));
    }

    if (ctx.cmdLine().statsMem)
    {
        MemoryProfile::Summary summary;
        MemoryProfile::buildSummary(summary);

        entries.clear();
        addField(entries, "Tracked peak", Utf8Helper::toNiceSize(summary.totalPeakBytes));
        addField(entries, "Tracked current", Utf8Helper::toNiceSize(summary.totalCurrentBytes));
        Logger::printFieldGroup(ctx, "Memory Summary", entries, nextStatsGroupStyle(hasPrintedGroup));

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
                addField(entries, "Untagged", formatMemoryValue(summary.totalPeakBytes, untaggedPeak, 0, 0, nullptr));
            }

            appendMemoryTree(entries, root, summary.totalPeakBytes, 0);
            if (!entries.empty())
                Logger::printFieldGroup(ctx, "Memory Breakdown", entries, nextStatsGroupStyle(hasPrintedGroup, 30));
        }
    }
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

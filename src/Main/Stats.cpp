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

#if SWC_HAS_STATS
namespace
{
    constexpr size_t K_NAME_COLUMN = 40;

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

            Utf8 key(segment);
            auto it = node->children.find(key);
            if (it == node->children.end())
            {
                auto child     = std::make_unique<TreeNode>();
                child->segment = key;
                it             = node->children.emplace(std::move(key), std::move(child)).first;
            }

            node = it->second.get();
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

    void printMemLine(const TaskContext& ctx, const Utf8& name, const size_t nameIndent, const size_t totalPeakBytes, const size_t peakBytes, const size_t totalBytes, const size_t allocCount, const MemoryProfile::CategorySnapshot* leaf)
    {
        const auto   gray    = LogColorHelper::toAnsi(ctx, LogColor::Gray);
        const auto   white   = LogColorHelper::toAnsi(ctx, LogColor::White);
        const double peakPct = totalPeakBytes ? 100.0 * static_cast<double>(peakBytes) / static_cast<double>(totalPeakBytes) : 0.0;

        // Name with indent
        std::cout << LogColorHelper::toAnsi(ctx, LogColor::Yellow);
        for (size_t i = 0; i < nameIndent; ++i)
            std::cout << ' ';
        std::cout << name;

        // Dots to fill
        const size_t usedCols = nameIndent + name.length();
        std::cout << gray;
        if (usedCols < K_NAME_COLUMN)
        {
            std::cout << ' ';
            for (size_t i = usedCols + 1; i < K_NAME_COLUMN; ++i)
                std::cout << '.';
        }
        else
        {
            std::cout << "..";
        }

        // Peak (always shown)
        std::cout << ' ' << gray << "peak " << white << std::format("{:>9s} ({:5.1f}%)", Utf8Helper::toNiceSize(peakBytes), peakPct);

        // Churn (fixed width)
        if (totalBytes && totalBytes != peakBytes)
            std::cout << "  " << gray << "churn " << white << std::format("{:>9s}", Utf8Helper::toNiceSize(totalBytes));
        else
            std::cout << std::format("{:17s}", "");

        // Allocs (fixed width)
        if (allocCount)
            std::cout << "  " << gray << "allocs " << white << std::format("{:>9s}", Utf8Helper::toNiceBigNumber(allocCount));
        else
            std::cout << std::format("{:18s}", "");

        // File:line for leaf nodes (now aligned)
        if (leaf && leaf->file)
        {
            std::string_view filePath = leaf->file;
            const auto       lastSep  = filePath.find_last_of("\\/");
            if (lastSep != std::string_view::npos)
                filePath = filePath.substr(lastSep + 1);
            std::cout << "  " << gray << std::format("[{}:{}]", filePath, leaf->line);
        }

        std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
        std::cout << '\n';
    }

    void printTree(const TaskContext& ctx, const TreeNode& node, const size_t totalPeakBytes, const uint32_t depth)
    {
        std::vector<const TreeNode*> sorted;
        sorted.reserve(node.children.size());
        for (const auto& child : node.children | std::views::values)
            sorted.push_back(child.get());
        std::ranges::sort(sorted, [](const TreeNode* a, const TreeNode* b) {
            return a->peakBytes > b->peakBytes;
        });

        for (const auto* child : sorted)
        {
            if (!child->peakBytes && !child->totalBytes)
                continue;

            printMemLine(ctx, child->segment, depth * 2ull, totalPeakBytes, child->peakBytes, child->totalBytes, child->allocCount, child->leaf);

            if (!child->children.empty())
                printTree(ctx, *child, totalPeakBytes, depth + 1);
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

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    if (ctx.cmdLine().stats)
    {
        Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
        Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));
        Logger::printHeaderDot(ctx, colorHeader, "osMaxAllocated", colorMsg, Utf8Helper::toNiceSize(Os::peakProcessMemoryUsage()));
    }

#if SWC_HAS_STATS
    if (ctx.cmdLine().stats)
    {
        // Frontend counts
        Logger::print(ctx, "\n");
        Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numFiles", colorMsg, Utf8Helper::toNiceBigNumber(numFiles.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numTokens", colorMsg, Utf8Helper::toNiceBigNumber(numTokens.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numAstNodes.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numVisitedAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));

        // Semantic model counts
        Logger::print(ctx, "\n");
        Logger::printHeaderDot(ctx, colorHeader, "count.sema.numConstants", colorMsg, Utf8Helper::toNiceBigNumber(numConstants.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.sema.numTypes", colorMsg, Utf8Helper::toNiceBigNumber(numTypes.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.sema.numIdentifiers", colorMsg, Utf8Helper::toNiceBigNumber(numIdentifiers.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.sema.numSymbols", colorMsg, Utf8Helper::toNiceBigNumber(numSymbols.load()));
        Logger::printHeaderDot(ctx, colorHeader, "count.sema.numCodeGenFunctions", colorMsg, Utf8Helper::toNiceBigNumber(numCodeGenFunctions.load()));

        // Backend micro counts
        Logger::print(ctx, "\n");
        const size_t numMicroInitial          = numMicroInstrInitial.load();
        const size_t numMicroAfterStart       = numMicroInstrAfterStart.load();
        const size_t numMicroAfterPreRAOptim  = numMicroInstrAfterPreRAOptim.load();
        const size_t numMicroAfterRA          = numMicroInstrAfterRA.load();
        const size_t numMicroAfterPostRASetup = numMicroInstrAfterPostRASetup.load();
        const size_t numMicroAfterPostRAOptim = numMicroInstrAfterPostRAOptim.load();
        const size_t numMicroFinal            = numMicroInstrFinal.load();

        Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrInitialLowered", colorMsg, Utf8Helper::toNiceBigNumber(numMicroInitial));

        const std::array<MicroStageTransition, 6> transitions = {
            MicroStageTransition{"count.micro.instrAfterStackAdjustNormalize", numMicroInitial, numMicroAfterStart},
            MicroStageTransition{"count.micro.instrAfterPreRAOptimLoop", numMicroAfterStart, numMicroAfterPreRAOptim},
            MicroStageTransition{"count.micro.instrAfterLegalizeRegAllocLoop", numMicroAfterPreRAOptim, numMicroAfterRA},
            MicroStageTransition{"count.micro.instrAfterPrologEpilogSetup", numMicroAfterRA, numMicroAfterPostRASetup},
            MicroStageTransition{"count.micro.instrAfterPostRAOptimPasses", numMicroAfterPostRASetup, numMicroAfterPostRAOptim},
            MicroStageTransition{"count.micro.instrFinalAfterSanitizeEmit", numMicroAfterPostRAOptim, numMicroFinal},
        };

        for (const MicroStageTransition& transition : transitions)
            Logger::printHeaderDot(ctx, colorHeader, transition.countLabel, colorMsg, formatMicroInstrTotalWithDelta(transition.currentCount, transition.previousCount));

        const int64_t pipelineDelta = static_cast<int64_t>(numMicroFinal) - static_cast<int64_t>(numMicroInitial);
        Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrDeltaInitialToFinal", colorMsg, formatMicroInstrDelta(pipelineDelta, numMicroInitial));

        // Time
        Logger::print(ctx, "\n");
        Logger::printHeaderDot(ctx, colorHeader, "time.frontend.loadFile", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
        Logger::printHeaderDot(ctx, colorHeader, "time.frontend.lexer", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
        Logger::printHeaderDot(ctx, colorHeader, "time.frontend.parser", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));
        Logger::printHeaderDot(ctx, colorHeader, "time.sema.analysis", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeSema.load())));
        Logger::printHeaderDot(ctx, colorHeader, "time.backend.codegen", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeCodeGen.load())));
        Logger::printHeaderDot(ctx, colorHeader, "time.backend.microLower", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroLower.load())));
    }

    // Memory profile
    if (ctx.cmdLine().statsMem)
    {
        MemoryProfile::Summary summary;
        MemoryProfile::buildSummary(summary);

        Logger::print(ctx, "\n");
        Logger::printHeaderDot(ctx, colorHeader, "mem.trackedPeak", colorMsg, Utf8Helper::toNiceSize(summary.totalPeakBytes));
        Logger::printHeaderDot(ctx, colorHeader, "mem.trackedCurrent", colorMsg, Utf8Helper::toNiceSize(summary.totalCurrentBytes));

        if (!summary.categories.empty())
        {
            Logger::print(ctx, "\n");

            TreeNode root;
            for (const auto& cat : summary.categories)
                insertIntoTree(root, cat);
            propagateStats(root);

            // Untagged
            const size_t taggedPeak = root.peakBytes;
            if (taggedPeak < summary.totalPeakBytes)
            {
                const size_t untaggedPeak = summary.totalPeakBytes - taggedPeak;
                printMemLine(ctx, Utf8("(untagged)"), 0, summary.totalPeakBytes, untaggedPeak, 0, 0, nullptr);
            }

            printTree(ctx, root, summary.totalPeakBytes, 0);
        }
    }
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

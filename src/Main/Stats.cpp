#include "pch.h"
#include "Main/Stats.h"
#include "Main/Global.h"
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
    struct TreeNode
    {
        Utf8                                segment;
        size_t                              peakBytes    = 0;
        size_t                              currentBytes = 0;
        size_t                              totalBytes   = 0;
        size_t                              allocCount   = 0;
        size_t                              freeCount    = 0;
        const MemoryProfile::CategorySnapshot* leaf     = nullptr;
        std::map<Utf8, std::unique_ptr<TreeNode>> children;
    };

    void insertIntoTree(TreeNode& root, const MemoryProfile::CategorySnapshot& snap)
    {
        TreeNode*   node     = &root;
        std::string_view name = snap.name;

        while (!name.empty())
        {
            size_t      sep = name.find('/');
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

        // Accumulate leaf stats
        node->peakBytes    += snap.peakBytes;
        node->currentBytes += snap.currentBytes;
        node->totalBytes   += snap.totalBytes;
        node->allocCount   += snap.allocCount;
        node->freeCount    += snap.freeCount;
        node->leaf          = &snap;
    }

    void propagateStats(TreeNode& node)
    {
        for (auto& [_, child] : node.children)
        {
            propagateStats(*child);
            node.peakBytes    += child->peakBytes;
            node.currentBytes += child->currentBytes;
            node.totalBytes   += child->totalBytes;
            node.allocCount   += child->allocCount;
            node.freeCount    += child->freeCount;
        }
    }

    void printTree(Utf8& out, const TreeNode& node, const size_t totalPeakBytes, const uint32_t depth)
    {
        // Collect and sort children by peak bytes descending
        std::vector<const TreeNode*> sorted;
        sorted.reserve(node.children.size());
        for (const auto& [_, child] : node.children)
            sorted.push_back(child.get());
        std::ranges::sort(sorted, [](const TreeNode* a, const TreeNode* b) {
            return a->peakBytes > b->peakBytes;
        });

        for (const auto* child : sorted)
        {
            if (!child->peakBytes && !child->totalBytes)
                continue;

            // Indent
            for (uint32_t i = 0; i < depth; ++i)
                out += "  ";

            const double peakPct = totalPeakBytes ? 100.0 * static_cast<double>(child->peakBytes) / static_cast<double>(totalPeakBytes) : 0.0;

            out += std::format("{}", child->segment);

            // Pad name to alignment
            const size_t nameLen = child->segment.length() + depth * 2;
            if (nameLen < 30)
                out.append(30 - nameLen, '.');
            else
                out += "..";

            out += std::format(" peak {:>9s} ({:5.1f}%)", Utf8Helper::toNiceSize(child->peakBytes), peakPct);

            if (child->totalBytes != child->peakBytes)
                out += std::format("  churn {:>9s}", Utf8Helper::toNiceSize(child->totalBytes));

            if (child->allocCount)
                out += std::format("  allocs {:>8s}", Utf8Helper::toNiceBigNumber(child->allocCount));

            // Show file:line for leaf nodes
            if (child->leaf && child->leaf->file)
            {
                // Extract just the filename from the path
                std::string_view filePath = child->leaf->file;
                auto             lastSep  = filePath.find_last_of("\\/");
                if (lastSep != std::string_view::npos)
                    filePath = filePath.substr(lastSep + 1);
                out += std::format("  [{}:{}]", filePath, child->leaf->line);
            }

            out += "\n";

            // Recurse into children
            if (!child->children.empty())
                printTree(out, *child, totalPeakBytes, depth + 1);
        }
    }
}
#endif

void Stats::print(const TaskContext& ctx) const
{
    const Logger::ScopedLock loggerLock(ctx.global().logger());

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));
    Logger::printHeaderDot(ctx, colorHeader, "osMaxAllocated", colorMsg, Utf8Helper::toNiceSize(Os::peakProcessMemoryUsage()));

#if SWC_HAS_STATS
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
    const size_t numMicroNoOptim = numMicroInstrNoOptim.load();
    const size_t numMicroFinal   = numMicroInstrFinal.load();
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrNoOptim", colorMsg, Utf8Helper::toNiceBigNumber(numMicroNoOptim));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrFinal", colorMsg, Utf8Helper::toNiceBigNumber(numMicroFinal));

    const int64_t numMicroPipelineDelta     = static_cast<int64_t>(numMicroFinal) - static_cast<int64_t>(numMicroNoOptim);
    const char    numMicroPipelineDeltaSign = numMicroPipelineDelta >= 0 ? '+' : '-';
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrDelta", colorMsg, std::format("{}{}", numMicroPipelineDeltaSign, Utf8Helper::toNiceBigNumber(static_cast<size_t>(std::abs(numMicroPipelineDelta)))));

    double pipelineRemovedPct = 0.0;
    if (numMicroNoOptim != 0)
        pipelineRemovedPct = 100.0 * static_cast<double>(numMicroPipelineDelta) / static_cast<double>(numMicroNoOptim);
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrReducedPct", colorMsg, std::format("{:.2f}%", pipelineRemovedPct));

    // Time
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.loadFile", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.lexer", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.parser", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.sema.analysis", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeSema.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.backend.codegen", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeCodeGen.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.backend.microLower", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroLower.load())));

    // Memory profile
    MemoryProfile::Summary summary;
    MemoryProfile::buildSummary(summary);

    Utf8 memorySection;
    memorySection += "\nMemory Profile\n";
    memorySection += std::format("  tracked peak....... {}\n", Utf8Helper::toNiceSize(summary.totalPeakBytes));
    memorySection += std::format("  tracked current.... {}\n", Utf8Helper::toNiceSize(summary.totalCurrentBytes));

    if (summary.categories.empty())
    {
        memorySection += "  (no category data — add SWC_MEM_SCOPE to track allocations)\n";
    }
    else
    {
        memorySection += "\n";

        // Build hierarchical tree
        TreeNode root;
        for (const auto& cat : summary.categories)
            insertIntoTree(root, cat);
        propagateStats(root);

        // Also collect untagged bytes
        size_t taggedPeak = root.peakBytes;
        if (taggedPeak < summary.totalPeakBytes)
        {
            const size_t untaggedPeak = summary.totalPeakBytes - taggedPeak;
            const double untaggedPct  = 100.0 * static_cast<double>(untaggedPeak) / static_cast<double>(summary.totalPeakBytes);
            memorySection += std::format("  (untagged)...................... peak {:>9s} ({:5.1f}%)\n", Utf8Helper::toNiceSize(untaggedPeak), untaggedPct);
        }

        printTree(memorySection, root, summary.totalPeakBytes, 1);
    }

    Logger::print(ctx, memorySection);
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

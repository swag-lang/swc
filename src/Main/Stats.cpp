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

    constexpr size_t kMemoryHotspotTopN         = 4;
    constexpr size_t kMemoryHotspotMinPeakBytes = 1024 * 1024;
    constexpr size_t kMemoryHotspotMinTotalBytes = 16 * 1024 * 1024;

    MemoryProfile::Summary memoryProfileSummary;
    MemoryProfile::buildSummary(memoryProfileSummary, kMemoryHotspotTopN, kMemoryHotspotMinPeakBytes, kMemoryHotspotMinTotalBytes);

    const auto appendFieldLine = [](Utf8& out, const std::string_view label, const Utf8& value) {
        out += "  ";
        out += label;
        if (label.size() < 14)
            out.append(14 - label.size(), ' ');
        out += ": ";
        out += value;
        out += "\n";
    };

    const auto appendLocationLine = [](Utf8& out, const std::string_view label, const Utf8& value) {
        if (value.empty())
            return;

        out += "      ";
        out += label;
        if (label.size() < 12)
            out.append(12 - label.size(), ' ');
        out += ": ";
        out += value;
        out += "\n";
    };

    const auto appendLiveHotspots = [&](Utf8& out, const std::vector<MemoryProfile::Hotspot>& hotspots) {
        if (hotspots.empty())
            return;

        out += "\nTop Live Allocation Hotspots\n";
        for (size_t i = 0; i < hotspots.size(); ++i)
        {
            const auto& hotspot = hotspots[i];
            const double peakPct = memoryProfileSummary.totalPeakBytes ? 100.0 * static_cast<double>(hotspot.peakBytes) / static_cast<double>(memoryProfileSummary.totalPeakBytes) : 0.0;
            const auto   location = MemoryProfile::formatHotspotLocation(&ctx, hotspot);

            out += std::format("  [{}] peak {} ({:.1f}%), current {}, live blocks {}\n",
                               i + 1,
                               Utf8Helper::toNiceSize(hotspot.peakBytes),
                               peakPct,
                               Utf8Helper::toNiceSize(hotspot.currentBytes),
                               Utf8Helper::toNiceBigNumber(hotspot.liveCount));
            out += std::format("      churn {}, allocs {}, avg {}, frees {}\n",
                               Utf8Helper::toNiceSize(hotspot.totalBytes),
                               Utf8Helper::toNiceBigNumber(hotspot.allocCount),
                               Utf8Helper::toNiceSize(hotspot.allocCount ? hotspot.totalBytes / hotspot.allocCount : 0),
                               Utf8Helper::toNiceBigNumber(hotspot.freeCount));
            appendLocationLine(out, "allocator", location.allocationSite);
            appendLocationLine(out, "triggered by", location.callerSite);

            if (i + 1 != hotspots.size())
                out += "\n";
        }
    };

    const auto appendChurnHotspots = [&](Utf8& out, const std::vector<MemoryProfile::Hotspot>& hotspots) {
        if (hotspots.empty())
            return;

        out += "\nTop Allocation Churn\n";
        for (size_t i = 0; i < hotspots.size(); ++i)
        {
            const auto& hotspot  = hotspots[i];
            const auto  location = MemoryProfile::formatHotspotLocation(&ctx, hotspot);

            out += std::format("  [{}] churn {}, allocs {}, avg {}\n",
                               i + 1,
                               Utf8Helper::toNiceSize(hotspot.totalBytes),
                               Utf8Helper::toNiceBigNumber(hotspot.allocCount),
                               Utf8Helper::toNiceSize(hotspot.allocCount ? hotspot.totalBytes / hotspot.allocCount : 0));
            out += std::format("      peak {}, current {}, live blocks {}, frees {}\n",
                               Utf8Helper::toNiceSize(hotspot.peakBytes),
                               Utf8Helper::toNiceSize(hotspot.currentBytes),
                               Utf8Helper::toNiceBigNumber(hotspot.liveCount),
                               Utf8Helper::toNiceBigNumber(hotspot.freeCount));
            appendLocationLine(out, "allocator", location.allocationSite);
            appendLocationLine(out, "triggered by", location.callerSite);

            if (i + 1 != hotspots.size())
                out += "\n";
        }
    };

    Utf8 memorySection;
    memorySection += "\nMemory\n";
    appendFieldLine(memorySection, "tracked peak", Utf8Helper::toNiceSize(memoryProfileSummary.totalPeakBytes));
    appendFieldLine(memorySection, "tracked current", Utf8Helper::toNiceSize(memoryProfileSummary.totalCurrentBytes));
    appendFieldLine(memorySection, "report filter", std::format(">= {} peak or >= {} churn",
                                                                 Utf8Helper::toNiceSize(kMemoryHotspotMinPeakBytes),
                                                                 Utf8Helper::toNiceSize(kMemoryHotspotMinTotalBytes)));

    if (memoryProfileSummary.peakHotspots.empty() && memoryProfileSummary.totalHotspots.empty())
    {
        appendFieldLine(memorySection, "hotspots", "none above reporting threshold");
    }
    else
    {
        appendLiveHotspots(memorySection, memoryProfileSummary.peakHotspots);
        appendChurnHotspots(memorySection, memoryProfileSummary.totalHotspots);
    }

    Logger::print(ctx, memorySection);
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

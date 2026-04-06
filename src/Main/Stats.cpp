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

    MemoryProfile::Summary memoryProfileSummary;
    MemoryProfile::buildSummary(memoryProfileSummary, 6, 1024 * 1024, 16 * 1024 * 1024);

    const auto formatHotspotSummary = [&](const MemoryProfile::Hotspot& hotspot) {
        const double peakPct = memoryProfileSummary.totalPeakBytes ? 100.0 * static_cast<double>(hotspot.peakBytes) / static_cast<double>(memoryProfileSummary.totalPeakBytes) : 0.0;

        Utf8 result;
        result += "peak=";
        result += Utf8Helper::toNiceSize(hotspot.peakBytes);
        result += std::format(" ({:.1f}%)", peakPct);
        result += " current=";
        result += Utf8Helper::toNiceSize(hotspot.currentBytes);
        result += " total=";
        result += Utf8Helper::toNiceSize(hotspot.totalBytes);
        result += " allocs=";
        result += Utf8Helper::toNiceBigNumber(hotspot.allocCount);
        result += " avg=";
        result += Utf8Helper::toNiceSize(hotspot.allocCount ? hotspot.totalBytes / hotspot.allocCount : 0);
        return result;
    };

    const auto printHotspotSection = [&](const std::string_view headerPrefix, const std::vector<MemoryProfile::Hotspot>& hotspots) {
        for (size_t i = 0; i < hotspots.size(); ++i)
        {
            const Utf8 header = std::format("{}[{}]", headerPrefix, i + 1);
            Logger::printHeaderDot(ctx, colorHeader, header, colorMsg, formatHotspotSummary(hotspots[i]));

            const auto location = MemoryProfile::formatHotspotLocation(&ctx, hotspots[i]);
            Logger::printHeaderDot(ctx, colorHeader, "  alloc", colorMsg, location.allocationSite, ".", 44);
            if (!location.callerSite.empty())
                Logger::printHeaderDot(ctx, colorHeader, "  from", colorMsg, location.callerSite, ".", 44);

            if (i + 1 != hotspots.size())
                Logger::print(ctx, "\n");
        }
    };

    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "mem.total.peak", colorMsg, Utf8Helper::toNiceSize(memoryProfileSummary.totalPeakBytes));
    Logger::printHeaderDot(ctx, colorHeader, "mem.total.current", colorMsg, Utf8Helper::toNiceSize(memoryProfileSummary.totalCurrentBytes));

    if (!memoryProfileSummary.peakHotspots.empty())
    {
        Logger::print(ctx, "\n");
        printHotspotSection("mem.hotspot.live", memoryProfileSummary.peakHotspots);
    }

    if (!memoryProfileSummary.totalHotspots.empty())
    {
        Logger::print(ctx, "\n");
        printHotspotSection("mem.hotspot.churn", memoryProfileSummary.totalHotspots);
    }
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

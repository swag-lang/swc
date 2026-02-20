#include "pch.h"
#include "Main/Stats.h"
#include "Main/Global.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void Stats::print(const TaskContext& ctx) const
{
    Logger::ScopedLock loggerLock(ctx.global().logger());

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));

#if SWC_HAS_STATS
    // Counts
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "numFiles", colorMsg, Utf8Helper::toNiceBigNumber(numFiles.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numTokens", colorMsg, Utf8Helper::toNiceBigNumber(numTokens.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numAstNodes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numVisitedAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numConstants", colorMsg, Utf8Helper::toNiceBigNumber(numConstants.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numTypes", colorMsg, Utf8Helper::toNiceBigNumber(numTypes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numIdentifiers", colorMsg, Utf8Helper::toNiceBigNumber(numIdentifiers.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numSymbols", colorMsg, Utf8Helper::toNiceBigNumber(numSymbols.load()));

    Logger::print(ctx, "\n");
    const size_t numMicroNoOptim      = numMicroInstrNoOptim.load();
    const size_t numMicroFinal        = numMicroInstrFinal.load();
    const size_t numMicroOptimRemoved = numMicroInstrOptimRemoved.load();
    const size_t numMicroOptimAdded   = numMicroInstrOptimAdded.load();
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrNoOptim", colorMsg, Utf8Helper::toNiceBigNumber(numMicroNoOptim));
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrFinal", colorMsg, Utf8Helper::toNiceBigNumber(numMicroFinal));

    const int64_t numMicroPipelineDelta     = static_cast<int64_t>(numMicroNoOptim) - static_cast<int64_t>(numMicroFinal);
    const char    numMicroPipelineDeltaSign = numMicroPipelineDelta >= 0 ? '+' : '-';
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrPipelineDelta", colorMsg, std::format("{}{}", numMicroPipelineDeltaSign, Utf8Helper::toNiceBigNumber(static_cast<size_t>(std::abs(numMicroPipelineDelta)))));

    double pipelineRemovedPct = 0.0;
    if (numMicroNoOptim != 0)
        pipelineRemovedPct = 100.0 * static_cast<double>(numMicroPipelineDelta) / static_cast<double>(numMicroNoOptim);
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrPipelineRemovedPct", colorMsg, std::format("{:.2f}%", pipelineRemovedPct));

    const int64_t numMicroOptimNet     = static_cast<int64_t>(numMicroOptimRemoved) - static_cast<int64_t>(numMicroOptimAdded);
    const char    numMicroOptimNetSign = numMicroOptimNet >= 0 ? '+' : '-';
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrOptimRemoved", colorMsg, Utf8Helper::toNiceBigNumber(numMicroOptimRemoved));
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrOptimAdded", colorMsg, Utf8Helper::toNiceBigNumber(numMicroOptimAdded));
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrOptimNet", colorMsg, std::format("{}{}", numMicroOptimNetSign, Utf8Helper::toNiceBigNumber(static_cast<size_t>(std::abs(numMicroOptimNet)))));

    double optimRemovedPct = 0.0;
    if (numMicroNoOptim != 0)
        optimRemovedPct = 100.0 * static_cast<double>(numMicroOptimNet) / static_cast<double>(numMicroNoOptim);
    Logger::printHeaderDot(ctx, colorHeader, "numMicroInstrOptimRemovedPct", colorMsg, std::format("{:.2f}%", optimRemovedPct));

    // Time
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "timeLoadFile", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
    Logger::printHeaderDot(ctx, colorHeader, "timeLexer", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "timeParser", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));

    // Memory
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "memMaxAllocated", colorMsg, Utf8Helper::toNiceSize(memMaxAllocated.load()));
    Logger::printHeaderDot(ctx, colorHeader, "memConstants", colorMsg, Utf8Helper::toNiceSize(memConstants.load()));
    Logger::printHeaderDot(ctx, colorHeader, "memTypes", colorMsg, Utf8Helper::toNiceSize(memTypes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "memSymbols", colorMsg, Utf8Helper::toNiceSize(memSymbols.load()));
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Core/Timer.h"
#include "Core/Utf8Helper.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

void Stats::print(const TaskContext& ctx) const
{
    auto& log = ctx.global().logger();
    log.lock();

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    // Counts
    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
#if SWC_HAS_STATS
    Logger::printHeaderDot(ctx, colorHeader, "numFiles", colorMsg, Utf8Helper::toNiceBigNumber(numFiles.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numTokens", colorMsg, Utf8Helper::toNiceBigNumber(numTokens.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numAstNodes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numVisitedAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));
#endif
    Logger::print(ctx, "\n");

    // Times
#if SWC_HAS_STATS
    Logger::printHeaderDot(ctx, colorHeader, "timeLoadFile", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
    Logger::printHeaderDot(ctx, colorHeader, "timeLexer", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "timeParser", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));
#endif
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));
    Logger::print(ctx, "\n");

    // Memory
#if SWC_HAS_STATS
    Logger::printHeaderDot(ctx, colorHeader, "memMaxAllocated", colorMsg, Utf8Helper::toNiceSize(memMaxAllocated.load()));
#endif
    Logger::print(ctx, "\n");

    log.unlock();
}

SWC_END_NAMESPACE()

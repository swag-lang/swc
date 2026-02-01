#include "pch.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Main/Global.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void Stats::print(const TaskContext& ctx) const
{
    auto& log = ctx.global().logger();
    log.lock();

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
    log.unlock();
}

SWC_END_NAMESPACE();

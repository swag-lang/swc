#include "pch.h"
#include "Report/Stats.h"
#include "Core/Utf8Helper.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void Stats::print(const Context& ctx) const
{
    auto& log = ctx.global().logger();
    log.lock();

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Os::timerToSeconds(timeTotal.load())));

#if SWC_HAS_STATS
    Logger::printHeaderDot(ctx, colorHeader, "timeLexer", colorMsg, Utf8Helper::toNiceTime(Os::timerToSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "timeParser", colorMsg, Utf8Helper::toNiceTime(Os::timerToSeconds(timeParser.load())));
    Logger::printHeaderDot(ctx, colorHeader, "memMaxAllocated", colorMsg, Utf8Helper::toNiceSize(memMaxAllocated.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numFiles", colorMsg, Utf8Helper::toNiceBigNumber(numFiles.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numTokens", colorMsg, Utf8Helper::toNiceBigNumber(numTokens.load()));
#endif

    log.unlock();
}

SWC_END_NAMESPACE();

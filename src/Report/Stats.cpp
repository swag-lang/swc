#include "pch.h"
#include "Report/Stats.h"
#include "Core/Utf8Helpers.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void Stats::print(const EvalContext& ctx) const
{
    auto& log = ctx.global().logger();
    log.lock();

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helpers::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helpers::toNiceTime(Os::timerToSeconds(timeTotal.load())));

#if SWC_HAS_STATS
    Logger::printHeaderDot(ctx, colorHeader, "timeLexer", colorMsg, Utf8Helpers::toNiceTime(Os::timerToSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "timeParser", colorMsg, Utf8Helpers::toNiceTime(Os::timerToSeconds(timeParser.load())));
    Logger::printHeaderDot(ctx, colorHeader, "memMaxAllocated", colorMsg, Utf8Helpers::toNiceSize(memMaxAllocated.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numFiles", colorMsg, Utf8Helpers::toNiceBigNumber(numFiles.load()));
    Logger::printHeaderDot(ctx, colorHeader, "numTokens", colorMsg, Utf8Helpers::toNiceBigNumber(numTokens.load()));
#endif

    log.unlock();
}

SWC_END_NAMESPACE();

#include "pch.h"

#include "Core/Utf8Helpers.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

void Stats::print(const CompilerContext& ctx) const
{
    auto& log = ctx.global()->logger();
    log.lock();

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    log.printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helpers::toNiceBigNumber(ctx.global()->jobMgr().numWorkers()));
    Logger::printEol(ctx);

    log.printHeaderDot(ctx, colorHeader, "memMaxAllocated", colorMsg, Utf8Helpers::toNiceSize(memMaxAllocated.load()));
    Logger::printEol(ctx);

    log.printHeaderDot(ctx, colorHeader, "numFiles", colorMsg, Utf8Helpers::toNiceBigNumber(numFiles.load()));
    log.printHeaderDot(ctx, colorHeader, "numTokens", colorMsg, Utf8Helpers::toNiceBigNumber(numTokens.load()));
    Logger::printEol(ctx);

    log.printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helpers::toNiceTime(Os::timerToSeconds(timeTotal.load())));
    Logger::printEol(ctx);

    log.unlock();
}

SWC_END_NAMESPACE()

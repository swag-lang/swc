#include "pch.h"

#include "Core/Utf8Helpers.h"
#include "Main/Global.h"
#include "Report/Color.h"
#include "Report/Logger.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

void Stats::print() const
{
    auto& log = Global::get().logger();

    constexpr auto colorHeader = Color::Yellow;
    constexpr auto colorMsg    = Color::White;

    log.printHeaderDot(colorHeader, "numWorkers", colorMsg, Utf8Helpers::toNiceBigNumber(Global::get().jobMgr().numWorkers()));
    log.printEol();

    log.printHeaderDot(colorHeader, "memMaxAllocated", colorMsg, Utf8Helpers::toNiceSize(memMaxAllocated.load()));
    log.printEol();

    log.printHeaderDot(colorHeader, "numFiles", colorMsg, Utf8Helpers::toNiceBigNumber(numFiles.load()));
    log.printHeaderDot(colorHeader, "numTokens", colorMsg, Utf8Helpers::toNiceBigNumber(numTokens.load()));
    log.printEol();
}

#include "pch.h"

#include "Color.h"
#include "Core/Utf8Helpers.h"
#include "Logger.h"
#include "Main/Global.h"
#include "Report/Stats.h"

void Stats::print() const
{
    auto& log = Global::get().logger();
    log.printHeaderDot(Color::Yellow, "memMaxAllocated", Color::White, Utf8Helpers::toNiceSize(memMaxAllocated.load()));
    log.printHeaderDot(Color::Yellow, "numFiles", Color::White, Utf8Helpers::toNiceBigNumber(numFiles.load()));
    log.printHeaderDot(Color::Yellow, "numTokens", Color::White, Utf8Helpers::toNiceBigNumber(numTokens.load()));
}

#include "pch.h"

#include "Color.h"
#include "Core/Utf8Helpers.h"
#include "Logger.h"
#include "Main/Global.h"
#include "Report/Stats.h"

void Stats::print() const
{
    auto& log = Global::get().logger();
    log.printHeaderDot("memMaxAllocated", Utf8Helpers::toNiceSize(memMaxAllocated.load()), Color::Yellow, Color::White, ".");   
}
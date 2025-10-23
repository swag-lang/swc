#include "pch.h"

#include "Core/Utf8Helpers.h"
#include "Logger.h"
#include "Main/Global.h"
#include "Report/Stats.h"

void Stats::print()
{
    auto msg = std::format("memMaxAllocated: {}\n", Utf8Helpers::toNiceSize(memMaxAllocated.load()).c_str());
    Global::get().logger().log(msg);   
}
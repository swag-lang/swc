#include "pch.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

void Stats::resetCommandMetrics()
{
    Stats& stats = get();
    stats.numErrors.store(0, std::memory_order_relaxed);
    stats.numWarnings.store(0, std::memory_order_relaxed);
    stats.numFiles.store(0, std::memory_order_relaxed);
    stats.numTests.store(0, std::memory_order_relaxed);
    stats.numTestsFailed.store(0, std::memory_order_relaxed);
    stats.numTokens.store(0, std::memory_order_relaxed);
    stats.numFormatRewrittenFiles.store(0, std::memory_order_relaxed);
}

SWC_END_NAMESPACE();

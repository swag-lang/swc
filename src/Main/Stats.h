#pragma once

SWC_BEGIN_NAMESPACE();

struct Stats
{
    std::atomic<size_t> numErrors               = 0;
    std::atomic<size_t> numWarnings             = 0;
    std::atomic<size_t> numFiles                = 0;
    std::atomic<size_t> numTests                = 0;
    std::atomic<size_t> numTestsFailed          = 0;
    std::atomic<size_t> numTokens               = 0;
    std::atomic<size_t> numFormatRewrittenFiles = 0;

    static Stats& get()
    {
        static Stats stats;
        return stats;
    }

    static void addError()
    {
        get().numErrors.fetch_add(1, std::memory_order_relaxed);
    }

    static bool hasError()
    {
        return get().numErrors.load(std::memory_order_relaxed) != 0;
    }

    static uint64_t getNumErrors()
    {
        return get().numErrors.load(std::memory_order_relaxed);
    }

    static void resetCommandMetrics();
};

SWC_END_NAMESPACE();

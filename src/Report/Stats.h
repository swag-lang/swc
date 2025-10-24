#pragma once
SWC_BEGIN_NAMESPACE();

class Context;

struct Stats
{
    std::atomic<uint64_t> timeTotal = 0;

#if SWC_HAS_STATS
    std::atomic<uint64_t> timeLexer       = 0;
    std::atomic<uint64_t> timeParser      = 0;
    std::atomic<size_t>   memAllocated    = 0;
    std::atomic<size_t>   memMaxAllocated = 0;
    std::atomic<size_t>   numFiles        = 0;
    std::atomic<size_t>   numTokens       = 0;
#endif // SWC_HAS_STATS

    static Stats& get()
    {
        static Stats stats;
        return stats;
    }

    static void setMax(const std::atomic<size_t>& cur, std::atomic<size_t>& max)
    {
        const size_t current = cur.load(std::memory_order_relaxed);
        size_t       prevMax = max.load(std::memory_order_relaxed);
        while (current > prevMax && !max.compare_exchange_weak(prevMax, current, std::memory_order_relaxed))
        {
        }
    }

    void print(const Context& ctx) const;
};

SWC_END_NAMESPACE();

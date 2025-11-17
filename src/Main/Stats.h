#pragma once
SWC_BEGIN_NAMESPACE()

class TaskContext;

struct Stats
{
    std::atomic<uint64_t> timeTotal   = 0;
    std::atomic<size_t>   numErrors   = 0;
    std::atomic<size_t>   numWarnings = 0;

#if SWC_HAS_STATS
    std::atomic<uint64_t> timeLoadFile       = 0;
    std::atomic<uint64_t> timeLexer          = 0;
    std::atomic<uint64_t> timeParser         = 0;
    std::atomic<size_t>   memAllocated       = 0;
    std::atomic<size_t>   memMaxAllocated    = 0;
    std::atomic<size_t>   numFiles           = 0;
    std::atomic<size_t>   numTokens          = 0;
    std::atomic<size_t>   numAstNodes        = 0;
    std::atomic<size_t>   numVisitedAstNodes = 0;
#endif // SWC_HAS_STATS

    static Stats& get()
    {
        static Stats stats;
        return stats;
    }

    static void setMax(const std::atomic<size_t>& valCur, std::atomic<size_t>& valMax)
    {
        const size_t current = valCur.load(std::memory_order_relaxed);
        size_t       prevMax = valMax.load(std::memory_order_relaxed);
        while (current > prevMax && !valMax.compare_exchange_weak(prevMax, current, std::memory_order_relaxed))
        {
        }
    }

    void print(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE()

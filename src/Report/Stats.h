#pragma once

struct Stats
{
    std::atomic<uint32_t> memAllocated    = 0;
    std::atomic<uint32_t> memMaxAllocated = 0;

    static void setMax(const std::atomic<uint32_t>& cur, std::atomic<uint32_t>& max)
    {
        const uint32_t current = cur.load(std::memory_order_relaxed);
        uint32_t       prevMax = max.load(std::memory_order_relaxed);
        while (current > prevMax && !max.compare_exchange_weak(prevMax, current, std::memory_order_relaxed))
        {
        }
    }
};

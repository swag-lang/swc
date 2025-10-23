#include "pch.h"

#include "Memory/mimalloc/include/mimalloc.h"
#include "Report/Stats.h"

void* operator new(size_t size)
{
#if SWC_HAS_STATS
    auto& stats = Stats::get();
    stats.memAllocated.fetch_add(static_cast<uint32_t>(size));
    Stats::setMax(stats.memAllocated, stats.memMaxAllocated);
#endif

    return mi_malloc_aligned(size, sizeof(void*));
}

// ReSharper disable once CppParameterNamesMismatch
void operator delete(void* block) noexcept
{
    if (!block)
        return;

#if SWC_HAS_STATS
    const auto size = static_cast<uint32_t>(mi_usable_size(block));
    Stats::get().memAllocated.fetch_sub(size, std::memory_order_relaxed);
#endif

    mi_free_aligned(block, sizeof(void*));
}

void operator delete(void* block, std::size_t size) noexcept
{
    if (!block)
        return;

#if SWC_HAS_STATS
    Stats::get().memAllocated.fetch_sub(static_cast<uint32_t>(size), std::memory_order_relaxed);
#endif    
}

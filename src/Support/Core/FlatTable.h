#pragma once

SWC_BEGIN_NAMESPACE();

// What the compiler's open-addressing tables share: Fibonacci hashing spreads keys over a
// power-of-two table, and a table grows once it is three quarters full.
namespace FlatTable
{
    inline size_t slotIndex(uint64_t key, size_t mask) noexcept
    {
        return static_cast<size_t>(key * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    // Pointers from one allocator share their low bits; the multiply spreads them over the table.
    inline size_t slotIndex(const void* key, size_t mask) noexcept
    {
        return slotIndex(static_cast<uint64_t>(reinterpret_cast<uintptr_t>(key) >> 4), mask);
    }

    inline size_t capacityFor(size_t count, size_t initialCapacity) noexcept
    {
        size_t capacity = initialCapacity;
        while (count * 4 > capacity * 3)
            capacity *= 2;
        return capacity;
    }
}

SWC_END_NAMESPACE();

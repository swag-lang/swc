#pragma once
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class DenseBits
{
public:
    static std::span<uint64_t> row(std::vector<uint64_t>& bits, uint32_t rowIndex, uint32_t rowWordCount)
    {
        if (!rowWordCount)
            return {};

        const size_t offset = static_cast<size_t>(rowIndex) * rowWordCount;
        return {bits.data() + offset, rowWordCount};
    }

    static std::span<const uint64_t> row(const std::vector<uint64_t>& bits, uint32_t rowIndex, uint32_t rowWordCount)
    {
        if (!rowWordCount)
            return {};

        const size_t offset = static_cast<size_t>(rowIndex) * rowWordCount;
        return {bits.data() + offset, rowWordCount};
    }

    static void set(std::span<uint64_t> bits, uint32_t bitIndex)
    {
        if (bits.empty())
            return;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        bits[wordIndex] |= (1ull << (bitIndex & 63u));
    }

    static void clear(std::span<uint64_t> bits, uint32_t bitIndex)
    {
        if (bits.empty())
            return;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        bits[wordIndex] &= ~(1ull << (bitIndex & 63u));
    }

    static bool contains(std::span<const uint64_t> bits, uint32_t bitIndex)
    {
        if (bits.empty())
            return false;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        return (bits[wordIndex] & (1ull << (bitIndex & 63u))) != 0;
    }
    static bool                      copyIfChanged(std::span<uint64_t> outDst, std::span<const uint64_t> src);
    static uint32_t                  count(std::span<const uint64_t> bits);
};

SWC_END_NAMESPACE();

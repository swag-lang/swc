#include "pch.h"
#include "Support/Core/DenseBits.h"

SWC_BEGIN_NAMESPACE();

std::span<uint64_t> DenseBits::row(std::vector<uint64_t>& bits, const uint32_t rowIndex, const uint32_t rowWordCount)
{
    if (!rowWordCount)
        return {};

    const size_t offset = static_cast<size_t>(rowIndex) * rowWordCount;
    return {bits.data() + offset, rowWordCount};
}

std::span<const uint64_t> DenseBits::row(const std::vector<uint64_t>& bits, const uint32_t rowIndex, const uint32_t rowWordCount)
{
    if (!rowWordCount)
        return {};

    const size_t offset = static_cast<size_t>(rowIndex) * rowWordCount;
    return {bits.data() + offset, rowWordCount};
}

void DenseBits::set(const std::span<uint64_t> bits, const uint32_t bitIndex)
{
    if (bits.empty())
        return;

    const uint32_t wordIndex = bitIndex >> 6u;
    SWC_ASSERT(wordIndex < bits.size());
    bits[wordIndex] |= (1ull << (bitIndex & 63u));
}

void DenseBits::clear(const std::span<uint64_t> bits, const uint32_t bitIndex)
{
    if (bits.empty())
        return;

    const uint32_t wordIndex = bitIndex >> 6u;
    SWC_ASSERT(wordIndex < bits.size());
    bits[wordIndex] &= ~(1ull << (bitIndex & 63u));
}

bool DenseBits::contains(const std::span<const uint64_t> bits, const uint32_t bitIndex)
{
    if (bits.empty())
        return false;

    const uint32_t wordIndex = bitIndex >> 6u;
    SWC_ASSERT(wordIndex < bits.size());
    return (bits[wordIndex] & (1ull << (bitIndex & 63u))) != 0;
}

bool DenseBits::copyIfChanged(const std::span<uint64_t> outDst, const std::span<const uint64_t> src)
{
    SWC_ASSERT(outDst.size() == src.size());
    bool changed = false;
    for (size_t i = 0; i < outDst.size(); ++i)
    {
        if (outDst[i] == src[i])
            continue;

        changed = true;
        break;
    }

    if (!changed)
        return false;

    for (size_t i = 0; i < outDst.size(); ++i)
        outDst[i] = src[i];
    return true;
}

uint32_t DenseBits::count(const std::span<const uint64_t> bits)
{
    uint32_t result = 0;
    for (const uint64_t value : bits)
        result += std::popcount(value);
    return result;
}

SWC_END_NAMESPACE();

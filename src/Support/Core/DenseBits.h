#pragma once

SWC_BEGIN_NAMESPACE();

class DenseBits
{
public:
    static std::span<uint64_t>       row(std::vector<uint64_t>& bits, uint32_t rowIndex, uint32_t rowWordCount);
    static std::span<const uint64_t> row(const std::vector<uint64_t>& bits, uint32_t rowIndex, uint32_t rowWordCount);
    static void                      set(std::span<uint64_t> bits, uint32_t bitIndex);
    static void                      clear(std::span<uint64_t> bits, uint32_t bitIndex);
    static bool                      contains(std::span<const uint64_t> bits, uint32_t bitIndex);
    static bool                      copyIfChanged(std::span<uint64_t> outDst, std::span<const uint64_t> src);
    static uint32_t                  count(std::span<const uint64_t> bits);
};

SWC_END_NAMESPACE();

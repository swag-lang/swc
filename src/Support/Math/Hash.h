#pragma once
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

SWC_BEGIN_NAMESPACE();

namespace Math
{
    uint32_t hash(std::string_view v, uint64_t seed = 0xa0761d6478bd642full);
    uint32_t hash(std::span<const std::byte> v, uint64_t seed = 0xa0761d6478bd642full);
    uint32_t hash(uint32_t v);
    uint32_t hashCombine(uint32_t h, bool v);
    uint32_t hashCombine(uint32_t h, uint32_t v);
    uint32_t hashCombine(uint32_t h, uint64_t v);
}

SWC_END_NAMESPACE();

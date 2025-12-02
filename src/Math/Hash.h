#pragma once

SWC_BEGIN_NAMESPACE()

namespace Math
{
    uint32_t hash(std::string_view v, uint64_t seed = 0xa0761d6478bd642full);
    size_t   hash_combine(size_t h, size_t v);
}

SWC_END_NAMESPACE()

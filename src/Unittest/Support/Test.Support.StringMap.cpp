#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/StringMap.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CountedValue
    {
        uint32_t value = 0;

        CountedValue() = default;
        CountedValue(uint32_t requested, uint32_t& constructions) :
            value(requested)
        {
            ++constructions;
        }
    };
}

SWC_TEST_BEGIN(StringMap_EmplaceConstructsOnceWhenDisplacingEntry)
{
    StringMap<CountedValue> map;
    uint32_t                constructions = 0;
    map.try_emplace("left", 0, 11u, constructions);
    map.try_emplace("right", 1, 22u, constructions);

    // The new key starts in slot zero and displaces the key in slot one.
    constructions                = 0;
    const auto [value, inserted] = map.try_emplace("middle", 16, 33u, constructions);
    if (!inserted || constructions != 1 || value->value != 33 || map.size() != 3)
        return Result::Error;

    const auto* left  = map.find("left", 0);
    const auto* right = map.find("right", 1);
    if (!left || left->value != 11 || !right || right->value != 22)
        return Result::Error;

    constructions                        = 0;
    const auto [existing, insertedAgain] = map.try_emplace("middle", 16, 44u, constructions);
    if (insertedAgain || constructions != 0 || existing->value != 33)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(StringMap_ReserveKeepsRoundedCapacities)
{
    struct TestCase
    {
        size_t requested;
        size_t capacity;
    };
    constexpr std::array cases = {
        TestCase{0, 2},
        TestCase{1, 2},
        TestCase{2, 4},
        TestCase{3, 4},
        TestCase{7, 16},
        TestCase{14, 32},
        TestCase{28, 64},
        TestCase{56, 128},
    };
    for (const TestCase test : cases)
    {
        StringMap<uint32_t> constructed(test.requested);
        if (constructed.capacity() != test.capacity || !constructed.empty())
            return Result::Error;
        constructed.reserve(test.requested);
        constructed.reserve(0);
        if (constructed.capacity() != test.capacity)
            return Result::Error;

        StringMap<uint32_t> reserved;
        reserved.reserve(test.requested);
        if (reserved.capacity() != std::max(size_t{16}, test.capacity))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(StringMap_CollisionsSurviveGrowthReserveAndClear)
{
    constexpr uint32_t          count    = 96;
    constexpr std::array        prefixes = {0x80000000u, 0xFE000000u, 0xFF000000u};
    std::array<Utf8, count>     keys;
    std::array<uint32_t, count> hashes;
    for (uint32_t index = 0; index < count; ++index)
    {
        keys[index]   = std::format("collision_{}", index);
        hashes[index] = prefixes[index % prefixes.size()] | (index % 7 == 0 ? 127u : index % 2);
    }

    StringMap<uint32_t> map(0);
    for (uint32_t index = 0; index < count; ++index)
    {
        const auto [value, inserted] = map.try_emplace(keys[index], hashes[index], index + 10);
        if (!inserted || *value != index + 10 || map.size() != index + 1)
            return Result::Error;
        for (uint32_t previous = 0; previous <= index; ++previous)
        {
            const auto* found = std::as_const(map).find(keys[previous], hashes[previous]);
            if (!found || *found != previous + 10)
                return Result::Error;
        }
    }
    if (map.capacity() != 128 || map.find("missing", 0xFF000001u))
        return Result::Error;

    map.reserve(200);
    map.reserve(80);
    if (map.capacity() != 256 || map.size() != count)
        return Result::Error;
    for (uint32_t index = 0; index < count; ++index)
    {
        const auto* found = map.find(keys[index], hashes[index]);
        if (!found || *found != index + 10)
            return Result::Error;
    }

    map.clear();
    if (!map.empty() || map.capacity() != 256)
        return Result::Error;
    for (uint32_t index = count; index-- > 0;)
    {
        if (map.find(keys[index], hashes[index]))
            return Result::Error;
        map.insert_or_assign(keys[index], hashes[index], index + 100);
    }
    for (uint32_t index = 0; index < count; ++index)
    {
        const auto* found = map.find(keys[index], hashes[index]);
        if (!found || *found != index + 100)
            return Result::Error;
    }
    const auto [updated, inserted] = map.insert_or_assign(keys[5], hashes[5], 0xCAFEu);
    if (inserted || *updated != 0xCAFEu || map.size() != count)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

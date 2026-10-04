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

SWC_END_NAMESPACE();

#endif

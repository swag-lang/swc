#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/PointerSet.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

// A worker keeps these tables across functions. A large table that its last fill used only a
// little of is given back on clear: what it held must be gone, and the next fill must work.
SWC_TEST_BEGIN(FlatTables_PointerSetClearAfterLargeAndSmallFills)
{
    std::vector<int> storage(4096);
    PointerSet<int>  set;
    for (int& value : storage)
        set.insert(&value);
    if (set.size() != storage.size())
        return Result::Error;

    set.clear();
    if (!set.empty() || set.contains(&storage[17]))
        return Result::Error;

    // A small fill of the large table, then the clear that gives the table back.
    set.insert(&storage[3]);
    set.insert(&storage[5]);
    set.clear();
    set.clear();
    if (!set.empty() || set.contains(&storage[3]) || set.contains(&storage[5]))
        return Result::Error;

    for (size_t i = 0; i < storage.size(); i += 2)
    {
        if (!set.insert(&storage[i]))
            return Result::Error;
    }

    for (size_t i = 0; i < storage.size(); ++i)
    {
        if (set.contains(&storage[i]) != (i % 2 == 0))
            return Result::Error;
    }

    if (set.insert(&storage[0]))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FlatTables_FlatKeyMapClearAfterLargeAndSmallFills)
{
    constexpr uint32_t   K_ALL_ONES = std::numeric_limits<uint32_t>::max();
    FlatKeyMap<uint32_t> map;
    for (uint32_t key = 0; key < 4096; ++key)
        map.getOrInsert(key) = key + 1;
    map.getOrInsert(K_ALL_ONES) = 7;
    if (map.size() != 4097)
        return Result::Error;

    map.clear();
    if (!map.empty() || map.find(12) || map.find(K_ALL_ONES))
        return Result::Error;

    // A small fill of the large table, then the clear that gives the table back.
    map.emplace(10, 11);
    map.emplace(10, 99);
    if (!map.find(10) || *map.find(10) != 11)
        return Result::Error;
    map.clear();
    if (!map.empty() || map.find(10))
        return Result::Error;

    for (uint32_t key = 0; key < 3000; key += 3)
        map.getOrInsert(key) = key * 2;
    for (uint32_t key = 0; key < 3000; ++key)
    {
        const uint32_t* value = map.find(key);
        if ((value != nullptr) != (key % 3 == 0))
            return Result::Error;
        if (value && *value != key * 2)
            return Result::Error;
    }

    FlatKeySet set;
    set.reserve(2000);
    for (uint32_t key = 100; key < 2100; ++key)
        set.insert(key);
    set.reserve(5000);
    for (uint32_t key = 0; key < 2200; ++key)
    {
        if (set.contains(key) != (key >= 100 && key < 2100))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

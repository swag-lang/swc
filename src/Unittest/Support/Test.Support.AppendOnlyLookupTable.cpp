#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/AppendOnlyLookupTable.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(AppendOnlyLookupTable_GrowsAcrossChunks)
{
    AppendOnlyLookupTable<int, 2>     table;
    std::vector<std::unique_ptr<int>> values;
    values.reserve(10);
    for (int i = 0; i < 10; ++i)
    {
        values.push_back(std::make_unique<int>(100 + i));
        table.pushBack(values.back().get());
    }

    if (table.size() != values.size())
        return Result::Error;

    for (size_t i = 0; i < values.size(); ++i)
    {
        if (table.at(static_cast<uint32_t>(i)) != values[i].get())
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(AppendOnlyLookupTable_ConcurrentReaderSeesPublishedEntries)
{
    static constexpr uint32_t VALUE_COUNT = 64;

    AppendOnlyLookupTable<int, 3> table;
    std::array<int, VALUE_COUNT>  values{};
    for (uint32_t i = 0; i < VALUE_COUNT; ++i)
        values[i] = static_cast<int>(i * 3 + 1);

    std::atomic readerOk = true;
    std::thread       reader([&] {
        uint32_t observed = 0;
        while (observed < VALUE_COUNT)
        {
            const uint32_t published = table.size();
            for (; observed < published; ++observed)
            {
                int* value = table.at(observed);
                if (value != &values[observed] || *value != values[observed])
                {
                    readerOk.store(false, std::memory_order_release);
                    return;
                }
            }

            std::this_thread::yield();
        }
    });

    for (uint32_t i = 0; i < VALUE_COUNT; ++i)
        table.pushBack(&values[i]);

    reader.join();
    if (!readerOk.load(std::memory_order_acquire))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

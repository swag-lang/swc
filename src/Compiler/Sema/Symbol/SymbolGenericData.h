#pragma once
#include "Support/Memory/Heap.h"
#include <atomic>

SWC_BEGIN_NAMESPACE();

namespace SymbolGenericData
{
    template<typename T>
    inline T& ensure(std::atomic<T*>& slot) noexcept
    {
        if (auto* data = slot.load(std::memory_order_acquire))
            return *data;

        auto* newData  = heapNew<T>();
        auto* expected = static_cast<T*>(nullptr);
        if (!slot.compare_exchange_strong(expected, newData, std::memory_order_acq_rel, std::memory_order_acquire))
        {
            heapDelete(newData);
            return *expected;
        }

        return *newData;
    }
}

SWC_END_NAMESPACE();

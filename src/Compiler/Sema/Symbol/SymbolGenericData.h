#pragma once
#include "Support/Memory/Heap.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
struct GenericInstanceOrigin;

namespace SymbolGenericData
{
    template<typename T>
    inline void setCompletionOwner(T& data, const TaskContext& ctx) noexcept
    {
        const TaskContext* expected = nullptr;
        const bool         done     = data.completionOwner.compare_exchange_strong(expected, &ctx, std::memory_order_acq_rel);
        SWC_ASSERT(done || expected == &ctx);
    }

    template<typename T>
    inline bool isCompletionOwner(const T* data, const TaskContext& ctx) noexcept
    {
        return data && data->completionOwner.load(std::memory_order_acquire) == &ctx;
    }

    template<typename T>
    inline const GenericInstanceOrigin* instanceOrigin(const T* data) noexcept
    {
        return data && data->rootSym ? &data->origin : nullptr;
    }

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

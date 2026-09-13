#pragma once
#include "Support/Memory/mimalloc/include/mimalloc.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace Unittest
{
    // Track this thread's allocations independently of other compiler instances and jobs.
    class ScopedHeap
    {
    public:
        ScopedHeap() :
            heap_(mi_heap_new())
        {
            if (heap_)
                previous_ = mi_theap_set_default(mi_heap_theap(heap_));
        }

        ScopedHeap(const ScopedHeap&)            = delete;
        ScopedHeap& operator=(const ScopedHeap&) = delete;

        ~ScopedHeap()
        {
            if (heap_)
            {
                mi_theap_set_default(previous_);
                mi_heap_destroy(heap_);
            }
        }

        bool empty() const
        {
            if (!heap_)
                return false;
            mi_heap_collect(heap_, true);
            size_t count = 0;
            return mi_heap_visit_blocks(heap_, true, countLiveBlocks, &count) && count == 0;
        }

    private:
        static bool countLiveBlocks(const mi_heap_t*, const mi_heap_area_t*, void* block, size_t, void* data)
        {
            if (block)
                ++*static_cast<size_t*>(data);
            return true;
        }

        mi_heap_t*  heap_     = nullptr;
        mi_theap_t* previous_ = nullptr;
    };
}

#endif

SWC_END_NAMESPACE();

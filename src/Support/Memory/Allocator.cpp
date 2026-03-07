// ReSharper disable CppParameterNamesMismatch
#include "pch.h"
#include "Main/Stats.h"
#include "Support/Memory/mimalloc/include/mimalloc.h"

namespace
{
#if SWC_HAS_STATS
    void trackAlloc(const void* ptr)
    {
        if (!ptr)
            return;

        swc::Stats&  stats = swc::Stats::get();
        const size_t size  = mi_usable_size(ptr);
        stats.memAllocated.fetch_add(size, std::memory_order_relaxed);
        swc::Stats::setMax(stats.memAllocated, stats.memMaxAllocated);
    }

    void trackFree(const void* ptr)
    {
        if (!ptr)
            return;

        const size_t size = mi_usable_size(ptr);
        swc::Stats::get().memAllocated.fetch_sub(size, std::memory_order_relaxed);
    }
#else
    void trackAlloc(void*)
    {
    }
    void trackFree(void*)
    {
    }
#endif

    [[nodiscard]] void* allocThrow(size_t size, size_t align)
    {
        void* ptr = mi_malloc_aligned(size, align);
        if (!ptr)
            throw std::bad_alloc();

        trackAlloc(ptr);
        return ptr;
    }

    [[nodiscard]] void* allocNoThrow(size_t size, size_t align) noexcept
    {
        void* ptr = mi_malloc_aligned(size, align);
        trackAlloc(ptr);
        return ptr;
    }

    void freeBlock(void* block, size_t align) noexcept
    {
        if (!block)
            return;

        trackFree(block);
        mi_free_aligned(block, align);
    }
}

void* operator new(size_t size)
{
    return allocThrow(size, sizeof(void*));
}

void* operator new[](size_t size)
{
    return allocThrow(size, sizeof(void*));
}

void* operator new(size_t size, const std::nothrow_t&) noexcept
{
    return allocNoThrow(size, sizeof(void*));
}

void* operator new[](size_t size, const std::nothrow_t&) noexcept
{
    return allocNoThrow(size, sizeof(void*));
}

void* operator new(size_t size, std::align_val_t align)
{
    return allocThrow(size, static_cast<size_t>(align));
}

void* operator new[](size_t size, std::align_val_t align)
{
    return allocThrow(size, static_cast<size_t>(align));
}

void* operator new(size_t size, std::align_val_t align, const std::nothrow_t&) noexcept
{
    return allocNoThrow(size, static_cast<size_t>(align));
}

void* operator new[](size_t size, std::align_val_t align, const std::nothrow_t&) noexcept
{
    return allocNoThrow(size, static_cast<size_t>(align));
}

void operator delete(void* block) noexcept
{
    freeBlock(block, sizeof(void*));
}

void operator delete[](void* block) noexcept
{
    freeBlock(block, sizeof(void*));
}

void operator delete(void* block, std::size_t) noexcept
{
    freeBlock(block, sizeof(void*));
}

void operator delete[](void* block, std::size_t) noexcept
{
    freeBlock(block, sizeof(void*));
}

void operator delete(void* block, const std::nothrow_t&) noexcept
{
    freeBlock(block, sizeof(void*));
}

void operator delete[](void* block, const std::nothrow_t&) noexcept
{
    freeBlock(block, sizeof(void*));
}

void operator delete(void* block, std::align_val_t align) noexcept
{
    freeBlock(block, static_cast<size_t>(align));
}

void operator delete[](void* block, std::align_val_t align) noexcept
{
    freeBlock(block, static_cast<size_t>(align));
}

void operator delete(void* block, std::size_t, std::align_val_t align) noexcept
{
    freeBlock(block, static_cast<size_t>(align));
}

void operator delete[](void* block, std::size_t, std::align_val_t align) noexcept
{
    freeBlock(block, static_cast<size_t>(align));
}

void operator delete(void* block, std::align_val_t align, const std::nothrow_t&) noexcept
{
    freeBlock(block, static_cast<size_t>(align));
}

void operator delete[](void* block, std::align_val_t align, const std::nothrow_t&) noexcept
{
    freeBlock(block, static_cast<size_t>(align));
}

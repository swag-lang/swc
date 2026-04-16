// ReSharper disable CppParameterNamesMismatch
#include "pch.h"
#include "Support/Memory/MemoryProfile.h"

namespace
{
    constexpr size_t K_DEFAULT_NEW_ALIGNMENT = sizeof(void*);

    [[nodiscard]] void* allocThrow(const size_t size, const size_t align)
    {
        return swc::MemoryProfile::allocateHeap(size, align, true);
    }

    [[nodiscard]] void* allocNoThrow(const size_t size, const size_t align) noexcept
    {
        return swc::MemoryProfile::allocateHeap(size, align, false);
    }

    void freeBlock(void* block) noexcept
    {
        swc::MemoryProfile::freeHeap(block);
    }

    [[nodiscard]] void* allocDefaultThrow(const size_t size)
    {
        return allocThrow(size, K_DEFAULT_NEW_ALIGNMENT);
    }

    [[nodiscard]] void* allocDefaultNoThrow(const size_t size) noexcept
    {
        return allocNoThrow(size, K_DEFAULT_NEW_ALIGNMENT);
    }

    [[nodiscard]] void* allocAlignedThrow(const size_t size, const std::align_val_t align)
    {
        return allocThrow(size, static_cast<size_t>(align));
    }

    [[nodiscard]] void* allocAlignedNoThrow(const size_t size, const std::align_val_t align) noexcept
    {
        return allocNoThrow(size, static_cast<size_t>(align));
    }

    void freeAllocatedBlock(void* block) noexcept
    {
        freeBlock(block);
    }
}

void* operator new(size_t size)
{
    return allocDefaultThrow(size);
}

void* operator new[](size_t size)
{
    return allocDefaultThrow(size);
}

void* operator new(size_t size, const std::nothrow_t&) noexcept
{
    return allocDefaultNoThrow(size);
}

void* operator new[](size_t size, const std::nothrow_t&) noexcept
{
    return allocDefaultNoThrow(size);
}

void* operator new(size_t size, std::align_val_t align)
{
    return allocAlignedThrow(size, align);
}

void* operator new[](size_t size, std::align_val_t align)
{
    return allocAlignedThrow(size, align);
}

void* operator new(size_t size, std::align_val_t align, const std::nothrow_t&) noexcept
{
    return allocAlignedNoThrow(size, align);
}

void* operator new[](size_t size, std::align_val_t align, const std::nothrow_t&) noexcept
{
    return allocAlignedNoThrow(size, align);
}

void operator delete(void* block) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete[](void* block) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete(void* block, std::size_t) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete[](void* block, std::size_t) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete(void* block, const std::nothrow_t&) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete[](void* block, const std::nothrow_t&) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete(void* block, std::align_val_t) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete[](void* block, std::align_val_t) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete(void* block, std::size_t, std::align_val_t) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete[](void* block, std::size_t, std::align_val_t) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete(void* block, std::align_val_t, const std::nothrow_t&) noexcept
{
    freeAllocatedBlock(block);
}

void operator delete[](void* block, std::align_val_t, const std::nothrow_t&) noexcept
{
    freeAllocatedBlock(block);
}

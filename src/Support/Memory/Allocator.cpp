// ReSharper disable CppParameterNamesMismatch
#include "pch.h"
#include "Support/Memory/MemoryProfile.h"

namespace
{
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
    freeBlock(block);
}

void operator delete[](void* block) noexcept
{
    freeBlock(block);
}

void operator delete(void* block, std::size_t) noexcept
{
    freeBlock(block);
}

void operator delete[](void* block, std::size_t) noexcept
{
    freeBlock(block);
}

void operator delete(void* block, const std::nothrow_t&) noexcept
{
    freeBlock(block);
}

void operator delete[](void* block, const std::nothrow_t&) noexcept
{
    freeBlock(block);
}

void operator delete(void* block, std::align_val_t) noexcept
{
    freeBlock(block);
}

void operator delete[](void* block, std::align_val_t) noexcept
{
    freeBlock(block);
}

void operator delete(void* block, std::size_t, std::align_val_t) noexcept
{
    freeBlock(block);
}

void operator delete[](void* block, std::size_t, std::align_val_t) noexcept
{
    freeBlock(block);
}

void operator delete(void* block, std::align_val_t, const std::nothrow_t&) noexcept
{
    freeBlock(block);
}

void operator delete[](void* block, std::align_val_t, const std::nothrow_t&) noexcept
{
    freeBlock(block);
}

// ReSharper disable CppParameterNamesMismatch
#include "pch.h"
#include "Support/Memory/Allocator.h"
#include "Support/Memory/mimalloc/include/mimalloc.h"
#include "Support/Os/Os.h"

namespace
{
    void mimallocOutputWithStack(const char* msg, void*)
    {
        if (msg)
            (void) fputs(msg, stderr);

        static thread_local bool inStackDump = false;
        if (inStackDump || !msg)
            return;
        if (!strstr(msg, "assertion failed") && !strstr(msg, "mimalloc: error"))
            return;

        inStackDump = true;
        std::array<uintptr_t, 32> frames{};
        const uint32_t            numFrames = swc::Os::captureCallStack(frames, 1);
        (void) fputs("mimalloc report stack trace:\n", stderr);
        for (uint32_t i = 0; i < numFrames; ++i)
        {
            swc::Os::ResolvedAddress resolved;
            if (swc::Os::resolveAddress(resolved, frames[i], nullptr))
                (void) fprintf(stderr, "  [%02u] 0x%016llX %s | %s | %s\n", i, static_cast<unsigned long long>(frames[i]), resolved.moduleName.c_str(), resolved.symbolName.c_str(), resolved.sourceLocation.c_str());
            else
                (void) fprintf(stderr, "  [%02u] 0x%016llX\n", i, static_cast<unsigned long long>(frames[i]));
        }

        (void) fflush(stderr);
        inStackDump = false;
    }

    [[nodiscard]] void* allocThrow(size_t size, const size_t align)
    {
        if (!size)
            size = 1;
        void* ptr = mi_malloc_aligned(size, align);
        if (!ptr)
            throw std::bad_alloc();
        return ptr;
    }

    [[nodiscard]] void* allocNoThrow(size_t size, const size_t align) noexcept
    {
        if (!size)
            size = 1;
        return mi_malloc_aligned(size, align);
    }

    void freeBlock(void* block) noexcept
    {
        mi_free(block);
    }
}

SWC_BEGIN_NAMESPACE();

void Allocator::configure()
{
    // A compilation run spreads its allocations over one heap per worker thread. On-demand
    // commit keeps the process charge tied to pages the compiler actually touches. The value 2
    // retains full commit on overcommitting systems, where that charge is free.
    mi_option_set(mi_option_page_commit_on_demand, 2);
    mi_register_output(&mimallocOutputWithStack, nullptr);
}

SWC_END_NAMESPACE();

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

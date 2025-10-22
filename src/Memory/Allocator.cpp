#include "pch.h"

#include "Memory/mimalloc/include/mimalloc.h"

void* operator new(size_t size)
{
    return mi_malloc_aligned(size, sizeof(void*));
}

// ReSharper disable once CppParameterNamesMismatch
void operator delete(void* block) noexcept
{
    if (!block)
        return;
    mi_free_aligned(block, sizeof(void*));
}

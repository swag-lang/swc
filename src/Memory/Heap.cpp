#include "pch.h"
#include "Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

void* heapAlloc(std::size_t size) noexcept
{
    return operator new(size);
}

void heapFree(void* ptr) noexcept
{
    operator delete(ptr);
}

SWC_END_NAMESPACE();

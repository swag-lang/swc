#pragma once

SWC_BEGIN_NAMESPACE();

void* heapAlloc(std::size_t size) noexcept;
void  heapFree(void* ptr) noexcept;

// Typed wrappers
template<typename T, typename... ARGS>
T* heapNew(ARGS&&... args)
{
    void* mem = heapAlloc(sizeof(T));
    try
    {
        return new (mem) T(std::forward<ARGS>(args)...);
    }
    catch (...)
    {
        heapFree(mem);
        throw;
    }
}

template<typename T>
void heapDelete(T*& ptr) noexcept
{
    if (!ptr)
        return;

    ptr->~T();
    heapFree(static_cast<void*>(ptr));
    ptr = nullptr;
}

SWC_END_NAMESPACE();

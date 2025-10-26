// ReSharper disable CppInconsistentNaming
#pragma once
#include "Core/Types.h"
#include "Memory/Arena.h"
#include "Report/Check.h"

SWC_BEGIN_NAMESPACE();

// PagedStore: grow-only container backed by an Arena, IDs are dense [0..size)
template<class T, uint32_t N = 1024> // items per page by default
class PagedStore
{
    static_assert(N > 0 && (N & (N - 1)) == 0, "N must be a power of two");
    static_assert(std::is_trivially_destructible_v<T>, "T must be trivially destructible");

    static constexpr uint32_t PAGE_SHIFT = []() {
        uint32_t shift = 0, size = N;
        while (size >>= 1)
            ++shift;
        return shift;
    }();

    static constexpr uint32_t PAGE_MASK = N - 1u;

    std::vector<T*> pages_;
    uint32_t        count_ = 0;

    static uint32_t pageIndex(uint32_t id) noexcept { return id >> PAGE_SHIFT; }
    static uint32_t pageOffset(uint32_t id) noexcept { return id & PAGE_MASK; }

    T* newPage()
    {
        T* base = new T[N];
        pages_.push_back(base);
        return base;
    }

public:
    Ref push_back(const T& v)
    {
        const uint32_t id = count_++;
        const uint32_t p  = pageIndex(id);
        const uint32_t o  = pageOffset(id);
        if (p >= pages_.size())
            newPage();
        ::new (static_cast<void*>(&pages_[p][o])) T(v);
        return id;
    }

    template<class... Args>
    Ref emplace_back(Args&&... args)
    {
        const uint32_t id = count_++;
        const uint32_t p  = pageIndex(id);
        const uint32_t o  = pageOffset(id);
        if (p >= pages_.size())
            newPage();
        ::new (static_cast<void*>(&pages_[p][o])) T(std::forward<Args>(args)...);
        return id;
    }

    T& at(Ref id)
    {
        SWC_ASSERT(id < count_);
        return pages_[pageIndex(id)][pageOffset(id)];
    }

    const T& at(Ref id) const
    {
        SWC_ASSERT(id < count_);
        return pages_[pageIndex(id)][pageOffset(id)];
    }

    T* ptr(Ref id)
    {
        SWC_ASSERT(id < count_);
        return &pages_[pageIndex(id)][pageOffset(id)];
    }

    const T* ptr(Ref id) const
    {
        SWC_ASSERT(id < count_);
        return &pages_[pageIndex(id)][pageOffset(id)];
    }

    void reserve(uint32_t expected)
    {
        const uint32_t pagesNeeded = (expected + N - 1u) / N;
        pages_.reserve(pagesNeeded);
    }

    uint32_t size() const noexcept { return count_; }
    void     clear() noexcept { count_ = 0; }
};

SWC_END_NAMESPACE();

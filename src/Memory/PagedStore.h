// ReSharper disable CppInconsistentNaming
#pragma once
#include "Core/Types.h"
#include "Memory/Arena.h"

template<class T, uint32_t PAGE_SHIFT = 12> // 4096 items/page by default
class PagedStore
{
    static constexpr uint32_t PAGE_SIZE = 1u << PAGE_SHIFT;
    static constexpr uint32_t PAGE_MASK = PAGE_SIZE - 1;

    Arena*          arena_ = nullptr;
    std::vector<T*> pages_; // small side array of page bases
    uint32_t        count_ = 0;

    T* newPage()
    {
        T* base = arena_->allocArray<T>(PAGE_SIZE);
        pages_.push_back(base);
        return base;
    }

public:
    explicit PagedStore(Arena& arena) :
        arena_(&arena)
    {
    }

    Ref push_back(const T& v)
    {
        const uint32_t id   = count_++;
        uint32_t       page = id >> PAGE_SHIFT;
        uint32_t       off  = id & PAGE_MASK;
        if (page >= pages_.size())
            newPage();
        pages_[page][off] = v;
        return id;
    }

    template<class... Args>
    Ref emplace_back(Args&&... args)
    {
        const uint32_t id   = count_++;
        uint32_t       page = id >> PAGE_SHIFT;
        uint32_t       off  = id & PAGE_MASK;
        if (page >= pages_.size())
            newPage();
        ::new (&pages_[page][off]) T(std::forward<Args>(args)...);
        return id;
    }

    T& at(Ref id)
    {
        uint32_t page = id >> PAGE_SHIFT, off = id & PAGE_MASK;
        return pages_[page][off];
    }

    const T& at(Ref id) const
    {
        uint32_t page = id >> PAGE_SHIFT, off = id & PAGE_MASK;
        return pages_[page][off];
    }

    T* ptr(Ref id)
    {
        uint32_t page = id >> PAGE_SHIFT, off = id & PAGE_MASK;
        return &pages_[page][off];
    }

    const T* ptr(Ref id) const
    {
        uint32_t page = id >> PAGE_SHIFT, off = id & PAGE_MASK;
        return &pages_[page][off];
    }

    uint32_t size() const
    {
        return count_;
    }
};

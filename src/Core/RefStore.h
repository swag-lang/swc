// ReSharper disable CppInconsistentNaming
#pragma once
#include "Core/Types.h"
#include "Report/Check.h"
#include <memory>
#include <typeindex>
#include <typeinfo>
#include <vector>

SWC_BEGIN_NAMESPACE();

// Grow-only heterogeneous container with Ref-based lookup.
// Stores any type, keeping items densely indexed [0..size).
template<uint32_t N = 1024> // items per page by default
class RefStore
{
    static_assert(N > 0 && (N & (N - 1)) == 0, "N must be a power of two");

    // Base entry for type-erased storage
    struct EntryBase
    {
        virtual ~EntryBase()                                = default;
        virtual void*                 ptr() noexcept        = 0;
        virtual const std::type_info& type() const noexcept = 0;
    };

    // Concrete typed entry
    template<class T>
    struct Entry final : EntryBase
    {
        T value;
        explicit Entry(const T& v) :
            value(v)
        {
        }
        explicit Entry(T&& v) :
            value(std::move(v))
        {
        }
        void*                 ptr() noexcept override { return &value; }
        const std::type_info& type() const noexcept override { return typeid(T); }
    };

    // Compute log2(N) at compile time for fast page math
    static constexpr uint32_t PAGE_SHIFT = []() {
        uint32_t shift = 0, size = N;
        while (size >>= 1)
            ++shift;
        return shift;
    }();

    static constexpr uint32_t PAGE_MASK = N - 1u;

    std::vector<std::unique_ptr<EntryBase>*> pages_;     // array of page pointers
    uint32_t                                 count_ = 0; // total elements stored

    // Compute page index and offset from an ID
    static uint32_t pageIndex(uint32_t id) noexcept { return id >> PAGE_SHIFT; }
    static uint32_t pageOffset(uint32_t id) noexcept { return id & PAGE_MASK; }

    // Allocate and register a new page
    std::unique_ptr<EntryBase>* newPage()
    {
        auto* base = new std::unique_ptr<EntryBase>[N];
        pages_.push_back(base);
        return base;
    }

public:
    RefStore() = default;

    // Destroy all allocated pages
    ~RefStore()
    {
        for (auto* page : pages_)
            delete[] page;
    }

    // Add a copy of an existing object
    template<class T>
    Ref push_back(const T& v)
    {
        const uint32_t id = count_++;
        const uint32_t p  = pageIndex(id);
        const uint32_t o  = pageOffset(id);
        if (p >= pages_.size())
            newPage();
        pages_[p][o] = std::make_unique<Entry<T>>(v);
        return id;
    }

    // Construct an object in-place with forwarded arguments
    template<class T, class... Args>
    Ref emplace_back(Args&&... args)
    {
        const uint32_t id = count_++;
        const uint32_t p  = pageIndex(id);
        const uint32_t o  = pageOffset(id);
        if (p >= pages_.size())
            newPage();
        pages_[p][o] = std::make_unique<Entry<T>>(T(std::forward<Args>(args)...));
        return id;
    }

    // Get mutable reference by ID and expected type
    template<class T>
    T& at(Ref id)
    {
        SWC_ASSERT(id < count_);
        auto* e = pages_[pageIndex(id)][pageOffset(id)].get();
        SWC_ASSERT(e && e->type() == typeid(T));
        return *static_cast<T*>(e->ptr());
    }

    // Get const reference by ID and expected type
    template<class T>
    const T& at(Ref id) const
    {
        SWC_ASSERT(id < count_);
        auto* e = pages_[pageIndex(id)][pageOffset(id)].get();
        SWC_ASSERT(e && e->type() == typeid(T));
        return *static_cast<const T*>(e->ptr());
    }

    // Get mutable pointer by ID and expected type
    template<class T>
    T* ptr(Ref id)
    {
        SWC_ASSERT(id < count_);
        auto* e = pages_[pageIndex(id)][pageOffset(id)].get();
        SWC_ASSERT(e && e->type() == typeid(T));
        return static_cast<T*>(e->ptr());
    }

    // Get const reference by ID and expected type
    template<class T>
    const T* ptr(Ref id) const
    {
        SWC_ASSERT(id < count_);
        auto* e = pages_[pageIndex(id)][pageOffset(id)].get();
        SWC_ASSERT(e && e->type() == typeid(T));
        return static_cast<const T*>(e->ptr());
    }

    // Preallocate enough pages for 'expected' bytes
    void reserve(uint32_t expected)
    {
        const uint32_t pagesNeeded = (expected + N - 1u) / N;
        pages_.reserve(pagesNeeded);
    }

    // Free any unused pages and shrink vector capacity
    void shrink_to_fit() noexcept
    {
        const uint32_t needed = (count_ + N - 1u) / N;
        for (uint32_t i = static_cast<uint32_t>(pages_.size()); i > needed; --i)
        {
            delete[] pages_[i - 1];
            pages_.pop_back();
        }
        pages_.shrink_to_fit();
    }

    // Current number of stored elements
    uint32_t size() const noexcept { return count_; }

    // Reset logical size (does not free memory)
    void clear() noexcept { count_ = 0; }
};

SWC_END_NAMESPACE();

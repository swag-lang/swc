#pragma once
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

template<class T>
class TypedStore
{
public:
    TypedStore() = default;
    explicit TypedStore(uint32_t pageSize) :
        store_(pageSize)
    {
    }

    TypedStore(const TypedStore&)                = delete;
    TypedStore& operator=(const TypedStore&)     = delete;
    TypedStore(TypedStore&&) noexcept            = default;
    TypedStore& operator=(TypedStore&&) noexcept = default;

    uint32_t     pageSize() const noexcept { return store_.pageSize(); }
    uint32_t     size() const noexcept { return store_.size(); }
    uint8_t*     seekPtr() const noexcept { return store_.seekPtr(); }
    uint32_t     count() const noexcept { return count_; }
    T*           ptr(Ref ref) noexcept { return store_.ptr<T>(ref); }
    const T*     ptr(Ref ref) const noexcept { return store_.ptr<T>(ref); }
    T&           at(Ref ref) noexcept { return store_.at<T>(ref); }
    const T&     at(Ref ref) const noexcept { return store_.at<T>(ref); }
    T*           ptrAtIndex(uint32_t index) noexcept { return ptrAtIndexImpl(index); }
    const T*     ptrAtIndex(uint32_t index) const noexcept { return ptrAtIndexImpl(index); }
    Store&       store() noexcept { return store_; }
    const Store& store() const noexcept { return store_; }

    void clear() noexcept
    {
        store_.clear();
        count_ = 0;
    }

    Ref pushBack(const T& v)
    {
        ++count_;
        return store_.pushBack<T>(v);
    }

    std::pair<Ref, T*> emplaceUninit()
    {
        ++count_;
        return store_.emplaceUninit<T>();
    }

    std::pair<Ref, T*> emplaceUninitArray(uint32_t count)
    {
        if (count)
            count_ += count;
        return store_.emplaceUninitArray<T>(count);
    }

    class View
    {
    public:
        struct Iterator
        {
            TypedStore* store       = nullptr;
            uint32_t    pageIndex   = 0;
            uint32_t    indexInPage = 0;

            void advanceToValid()
            {
                while (pageIndex < store->pageCount())
                {
                    const uint32_t countInPage = store->pageUsed(pageIndex) / static_cast<uint32_t>(sizeof(T));
                    if (indexInPage < countInPage)
                        return;
                    ++pageIndex;
                    indexInPage = 0;
                }
            }

            T& operator*() const
            {
                return *(reinterpret_cast<T*>(store->pageBytesMutable(pageIndex)) + indexInPage);
            }

            Iterator& operator++()
            {
                ++indexInPage;
                advanceToValid();
                return *this;
            }

            bool operator!=(const Iterator& other) const
            {
                return store != other.store || pageIndex != other.pageIndex || indexInPage != other.indexInPage;
            }
        };

        struct ReverseIterator
        {
            TypedStore* store       = nullptr;
            uint32_t    pageIndex   = std::numeric_limits<uint32_t>::max();
            uint32_t    indexInPage = 0;

            void initToLast()
            {
                if (!store || store->pageCount() == 0)
                    return;

                pageIndex = store->pageCount() - 1;
                while (true)
                {
                    const uint32_t countInPage = store->pageUsed(pageIndex) / static_cast<uint32_t>(sizeof(T));
                    if (countInPage)
                    {
                        indexInPage = countInPage - 1;
                        return;
                    }
                    if (pageIndex == 0)
                    {
                        pageIndex = std::numeric_limits<uint32_t>::max();
                        return;
                    }
                    --pageIndex;
                }
            }

            T& operator*() const
            {
                return *(reinterpret_cast<T*>(store->pageBytesMutable(pageIndex)) + indexInPage);
            }

            ReverseIterator& operator++()
            {
                if (pageIndex == std::numeric_limits<uint32_t>::max())
                    return *this;

                if (indexInPage > 0)
                {
                    --indexInPage;
                    return *this;
                }

                while (pageIndex > 0)
                {
                    --pageIndex;
                    const uint32_t countInPage = store->pageUsed(pageIndex) / static_cast<uint32_t>(sizeof(T));
                    if (countInPage)
                    {
                        indexInPage = countInPage - 1;
                        return *this;
                    }
                }

                pageIndex = std::numeric_limits<uint32_t>::max();
                return *this;
            }

            bool operator!=(const ReverseIterator& other) const
            {
                return store != other.store || pageIndex != other.pageIndex || indexInPage != other.indexInPage;
            }
        };

        explicit View(TypedStore* s) :
            store_(s)
        {
        }

        Iterator begin() const
        {
            Iterator it{store_, 0, 0};
            it.advanceToValid();
            return it;
        }

        Iterator end() const
        {
            return {store_, store_->pageCount(), 0};
        }

        ReverseIterator rbegin() const
        {
            ReverseIterator it{store_};
            it.initToLast();
            return it;
        }

        ReverseIterator rend() const
        {
            return {store_, std::numeric_limits<uint32_t>::max(), 0};
        }

    private:
        TypedStore* store_ = nullptr;
    };

    View view() noexcept { return View(this); }

private:
    T* ptrAtIndexImpl(uint32_t index) noexcept
    {
        uint32_t remaining = index;
        for (uint32_t pageIndex = 0; pageIndex < pageCount(); ++pageIndex)
        {
            const uint32_t countInPage = pageUsed(pageIndex) / static_cast<uint32_t>(sizeof(T));
            if (remaining < countInPage)
            {
                auto* bytes = const_cast<uint8_t*>(pageBytes(pageIndex));
                return reinterpret_cast<T*>(bytes) + remaining;
            }
            remaining -= countInPage;
        }
        return nullptr;
    }

    const T* ptrAtIndexImpl(uint32_t index) const noexcept
    {
        uint32_t remaining = index;
        for (uint32_t pageIndex = 0; pageIndex < pageCount(); ++pageIndex)
        {
            const uint32_t countInPage = pageUsed(pageIndex) / static_cast<uint32_t>(sizeof(T));
            if (remaining < countInPage)
            {
                const auto* bytes = pageBytes(pageIndex);
                return reinterpret_cast<const T*>(bytes) + remaining;
            }
            remaining -= countInPage;
        }
        return nullptr;
    }

    uint32_t       pageCount() const noexcept { return static_cast<uint32_t>(store_.pagesStorage_.size()); }
    uint32_t       pageUsed(uint32_t index) const noexcept { return store_.pagesStorage_[index]->used; }
    const uint8_t* pageBytes(uint32_t index) const noexcept { return store_.pagesStorage_[index]->bytes(); }
    uint8_t*       pageBytesMutable(uint32_t index) const noexcept { return store_.pagesStorage_[index]->bytes(); }
    Store          store_;
    uint32_t       count_ = 0;
};

SWC_END_NAMESPACE();

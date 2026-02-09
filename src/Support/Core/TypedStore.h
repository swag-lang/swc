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

    uint32_t pageSize() const noexcept { return store_.pageSize(); }
    void     clear() noexcept { store_.clear(); }
    uint32_t size() const noexcept { return store_.size(); }
    uint8_t* seekPtr() const noexcept { return store_.seekPtr(); }

    Ref                pushBack(const T& v) { return store_.pushBack<T>(v); }
    std::pair<Ref, T*> emplaceUninit() { return store_.emplaceUninit<T>(); }
    std::pair<Ref, T*> emplaceUninitArray(uint32_t count) { return store_.emplaceUninitArray<T>(count); }

    T*       ptr(Ref ref) noexcept { return store_.ptr<T>(ref); }
    const T* ptr(Ref ref) const noexcept { return store_.ptr<T>(ref); }
    T&       at(Ref ref) noexcept { return store_.at<T>(ref); }
    const T& at(Ref ref) const noexcept { return store_.at<T>(ref); }

    uint32_t count() const noexcept
    {
        uint32_t total = 0;
        for (uint32_t idx = 0; idx < pageCount(); ++idx)
            total += pageUsed(idx) / static_cast<uint32_t>(sizeof(T));
        return total;
    }

    Store&       store() noexcept { return store_; }
    const Store& store() const noexcept { return store_; }

    class View
    {
    public:
        struct Iterator
        {
            const TypedStore* store       = nullptr;
            uint32_t          pageIndex   = 0;
            uint32_t          indexInPage = 0;

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

            const T& operator*() const
            {
                return *(reinterpret_cast<const T*>(store->pageBytes(pageIndex)) + indexInPage);
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

        explicit View(const TypedStore* s) :
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

    private:
        const TypedStore* store_ = nullptr;
    };

    View view() const noexcept { return View(this); }

private:
    uint32_t       pageCount() const noexcept { return static_cast<uint32_t>(store_.pagesStorage_.size()); }
    uint32_t       pageUsed(uint32_t index) const noexcept { return store_.pagesStorage_[index]->used; }
    const uint8_t* pageBytes(uint32_t index) const noexcept { return store_.pagesStorage_[index]->bytes(); }
    Store          store_;
};

SWC_END_NAMESPACE();

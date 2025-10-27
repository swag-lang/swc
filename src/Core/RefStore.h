// ReSharper disable CppInconsistentNaming
#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

using Ref = uint32_t;

// Simple page-based POD store.
// Each page holds up to N bytes of raw data (N must be a power of two).
// Items are packed sequentially; alignment is preserved relative to a max-aligned base.
// Ref is a 32-bit index in BYTES from the start of the store.
template<uint32_t N = 16 * 1024>
class RefStore
{
    static_assert(N > 0 && (N & (N - 1)) == 0, "N must be a power of two");

    struct Page
    {
        using Storage = std::aligned_storage_t<N, alignof(std::max_align_t)>;
        Storage  storage{};
        uint32_t used = 0;

        uint8_t*       bytes() noexcept { return reinterpret_cast<uint8_t*>(&storage); }
        const uint8_t* bytes() const noexcept { return reinterpret_cast<const uint8_t*>(&storage); }
    };

    std::vector<std::unique_ptr<Page>> pages_;
    uint64_t                           totalBytes_ = 0;

    Page*    cur_      = nullptr;
    uint32_t curIndex_ = 0;

    Page* newPage()
    {
        pages_.emplace_back(std::make_unique<Page>());
        cur_      = pages_.back().get();
        curIndex_ = static_cast<uint32_t>(pages_.size() - 1);
        return cur_;
    }

    static constexpr Ref makeRef(uint32_t pageIndex, uint32_t offset) noexcept
    {
        const uint64_t r = static_cast<uint64_t>(pageIndex) * static_cast<uint64_t>(N) + offset;
        SWC_ASSERT(r < std::numeric_limits<Ref>::max());
        return static_cast<Ref>(r);
    }

    static constexpr void decodeRef(Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept
    {
        pageIndex = ref / N;
        offset    = ref % N;
    }

    std::pair<Ref, void*> allocate(uint32_t size, uint32_t align)
    {
        SWC_ASSERT(size <= N && (align & (align - 1)) == 0 && align <= alignof(std::max_align_t));

        Page* page = cur_ ? cur_ : newPage();

        uint32_t offset = (page->used + (align - 1)) & ~(align - 1);

        if (offset + size > N)
        {
            page   = newPage();
            offset = 0;
        }

        page->used = offset + size;
        totalBytes_ += size;

        const Ref r = makeRef(curIndex_, offset);
        return {r, static_cast<void*>(page->bytes() + offset)};
    }

public:
    RefStore()                           = default;
    RefStore(const RefStore&)            = delete;
    RefStore& operator=(const RefStore&) = delete;

    RefStore(RefStore&& other) noexcept :
        pages_(std::move(other.pages_)),
        totalBytes_(other.totalBytes_),
        cur_(other.cur_),
        curIndex_(other.curIndex_)
    {
        other.totalBytes_ = 0;
        other.cur_        = nullptr;
        other.curIndex_   = 0;
    }

    RefStore& operator=(RefStore&& other) noexcept
    {
        if (this != &other)
        {
            using std::swap;
            swap(pages_, other.pages_);
            swap(totalBytes_, other.totalBytes_);
            swap(cur_, other.cur_);
            swap(curIndex_, other.curIndex_);
        }
        return *this;
    }

    void clear() noexcept
    {
        for (auto& up : pages_)
            up->used = 0;
        totalBytes_ = 0;
        if (!pages_.empty())
        {
            cur_      = pages_.back().get();
            curIndex_ = static_cast<uint32_t>(pages_.size() - 1);
        }
        else
        {
            cur_      = nullptr;
            curIndex_ = 0;
        }
    }

    uint32_t size() const noexcept
    {
        return static_cast<uint32_t>(std::min<uint64_t>(totalBytes_, std::numeric_limits<uint32_t>::max()));
    }

    template<class T>
    Ref push_back(const T& v)
    {
        static_assert(std::is_trivially_copyable_v<T>);
        auto [r, p]         = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        *static_cast<T*>(p) = v;
        return r;
    }

    template<class T>
    std::pair<Ref, T*> emplace_uninit()
    {
        static_assert(std::is_trivially_copyable_v<T>);
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    std::pair<Ref, void*> push_back_raw(uint32_t size, uint32_t align = alignof(std::max_align_t))
    {
        return allocate(size, align);
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        return ptr_impl<T>(pages_, ref);
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        return ptr_impl<T>(pages_, ref);
    }

    template<class T>
    T& at(Ref ref) noexcept
    {
        return *ptr<T>(ref);
    }

    template<class T>
    const T& at(Ref ref) const noexcept
    {
        return *ptr<T>(ref);
    }

private:
    template<class T>
    static T* ptr_impl(const std::vector<std::unique_ptr<Page>>& pages, Ref ref)
    {
        static_assert(std::is_trivially_copyable_v<T>);
        uint32_t pageIndex, offset;
        decodeRef(ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages.size());
        SWC_ASSERT(offset + sizeof(T) <= N);
        return reinterpret_cast<T*>(pages[pageIndex]->bytes() + offset);
    }

    struct SpanHdrRaw
    {
        uint32_t count; // elements of T in this chunk
        uint32_t total; // total elements in the full span (same in every chunk)
    };

    static constexpr uint32_t align_up_u32(uint32_t v, uint32_t a) noexcept
    {
        return (v + (a - 1)) & ~(a - 1);
    }

    template<class T>
    std::pair<Ref, uint32_t> write_chunk(const T* src, uint32_t remaining, uint32_t totalElems)
    {
        Page* page = cur_ ? cur_ : newPage();

        uint32_t off        = page->used;
        uint32_t bytesAvail = N - off;

        const uint32_t dataAlign  = static_cast<uint32_t>(alignof(T));
        const uint32_t hdrSize    = static_cast<uint32_t>(sizeof(SpanHdrRaw));
        const uint32_t dataOffset = align_up_u32(off + hdrSize, dataAlign);
        const uint32_t padBytes   = dataOffset - (off + hdrSize);

        if (hdrSize + padBytes + sizeof(T) > bytesAvail)
        {
            page       = newPage();
            off        = 0;
            bytesAvail = N;
        }

        const uint32_t dataOffsetF = align_up_u32(off + hdrSize, dataAlign);
        const uint32_t padBytesF   = dataOffsetF - (off + hdrSize);
        const uint32_t maxData     = N - (off + hdrSize + padBytesF);
        const uint32_t fit         = std::min<uint32_t>(remaining, maxData / static_cast<uint32_t>(sizeof(T)));
        SWC_ASSERT(fit > 0);

        const Ref      hdrRef  = makeRef(curIndex_, off);
        const uint32_t newUsed = dataOffsetF + fit * static_cast<uint32_t>(sizeof(T));
        SWC_ASSERT(newUsed <= N);
        page->used = newUsed;
        totalBytes_ += hdrSize + padBytesF + fit * sizeof(T);

        auto* hdr  = reinterpret_cast<SpanHdrRaw*>(page->bytes() + off);
        hdr->count = fit;
        hdr->total = totalElems;

        std::memcpy(page->bytes() + dataOffsetF, src, static_cast<size_t>(fit) * sizeof(T));

        return {hdrRef, fit};
    }

public:
    template<class T>
    Ref push_span(std::span<T> s)
    {
        static_assert(std::is_trivially_copyable_v<T>);

        const T* src       = s.data();
        auto     remaining = static_cast<uint32_t>(s.size());

        if (remaining == 0)
        {
            Page* page = cur_ ? cur_ : newPage();
            if (page->used + sizeof(SpanHdrRaw) > N)
                page = newPage();
            const Ref hdrRef = makeRef(curIndex_, page->used);
            auto*     hdr    = reinterpret_cast<SpanHdrRaw*>(page->bytes() + page->used);
            hdr->count       = 0;
            hdr->total       = 0;
            page->used += sizeof(SpanHdrRaw);
            totalBytes_ += sizeof(SpanHdrRaw);
            return hdrRef;
        }

        const uint32_t totalElems = remaining;
        Ref            firstRef   = INVALID_REF;

        while (remaining)
        {
            auto [hdrRef, wrote] = write_chunk<T>(src, remaining, totalElems);
            if (firstRef == INVALID_REF)
                firstRef = hdrRef;
            src += wrote;
            remaining -= wrote;
        }

        return firstRef;
    }

    template<class T>
    class SpanView
    {
        const RefStore* store_;
        Ref             head_;

        static const T* data_ptr(const RefStore* st, Ref hdrRef, uint32_t& count)
        {
            auto* hdr = st->ptr<SpanHdrRaw>(hdrRef);
            count     = hdr->count;
            uint32_t pageIndex, off;
            decodeRef(hdrRef, pageIndex, off);
            const uint32_t dataAlign  = static_cast<uint32_t>(alignof(T));
            const uint32_t hdrSize    = static_cast<uint32_t>(sizeof(SpanHdrRaw));
            const uint32_t dataOffset = align_up_u32(off + hdrSize, dataAlign);
            return reinterpret_cast<const T*>(st->pages_[pageIndex]->bytes() + dataOffset);
        }

        static uint32_t total_elems(const RefStore* st, Ref hdrRef)
        {
            return st->ptr<SpanHdrRaw>(hdrRef)->total;
        }

    public:
        explicit SpanView(const RefStore* s, Ref r) :
            store_(s),
            head_(r)
        {
        }

        uint32_t size() const { return total_elems(store_, head_); }
        bool     empty() const { return size() == 0; }
        Ref      ref() const { return head_; }

        struct chunk
        {
            const T* ptr;
            uint32_t count;
        };

        struct chunk_iterator
        {
            const RefStore* store  = nullptr;
            Ref             hdrRef = INVALID_REF;
            uint32_t        total  = 0;
            uint32_t        done   = 0;
            chunk           current{nullptr, 0};

            bool         operator!=(const chunk_iterator& o) const { return hdrRef != o.hdrRef; }
            const chunk& operator*() const { return current; }

            chunk_iterator& operator++()
            {
                done += current.count;
                if (done >= total)
                {
                    hdrRef = INVALID_REF;
                    return *this;
                }

                uint32_t pageIndex, off;
                decodeRef(hdrRef, pageIndex, off);
                hdrRef = makeRef(pageIndex + 1, 0);

                uint32_t cnt = 0;
                const T* p   = SpanView::data_ptr(store, hdrRef, cnt);
                current      = {p, cnt};
                return *this;
            }
        };

        chunk_iterator chunks_begin() const
        {
            uint32_t       cnt = 0;
            const T*       p   = data_ptr(store_, head_, cnt);
            chunk_iterator it{store_, head_, total_elems(store_, head_), 0, {p, cnt}};
            return it;
        }

        chunk_iterator chunks_end() const { return {store_, INVALID_REF, 0, 0, {nullptr, 0}}; }

        struct const_iterator
        {
            const RefStore* store       = nullptr;
            Ref             hdrRef      = INVALID_REF;
            const T*        curPtr      = nullptr;
            uint32_t        leftInChunk = 0;
            uint32_t        done        = 0;
            uint32_t        total       = 0;

            using value_type        = T;
            using reference         = const T&;
            using pointer           = const T*;
            using iterator_category = std::forward_iterator_tag;

            reference operator*() const { return *curPtr; }
            pointer   operator->() const { return curPtr; }

            const_iterator& operator++()
            {
                if (leftInChunk > 1)
                {
                    --leftInChunk;
                    ++curPtr;
                    ++done;
                    return *this;
                }

                ++done;
                if (done >= total)
                {
                    hdrRef      = INVALID_REF;
                    curPtr      = nullptr;
                    leftInChunk = 0;
                    return *this;
                }

                uint32_t pageIndex, off;
                decodeRef(hdrRef, pageIndex, off);
                hdrRef = makeRef(pageIndex + 1, 0);

                uint32_t cnt = 0;
                const T* p   = SpanView::data_ptr(store, hdrRef, cnt);
                curPtr       = p;
                leftInChunk  = cnt;
                return *this;
            }

            friend bool operator==(const const_iterator& a, const const_iterator& b)
            {
                return a.curPtr == b.curPtr && a.hdrRef == b.hdrRef;
            }

            friend bool operator!=(const const_iterator& a, const const_iterator& b)
            {
                return !(a == b);
            }
        };

        const_iterator begin() const
        {
            uint32_t cnt = 0;
            const T* p   = data_ptr(store_, head_, cnt);
            return {store_, head_, p, cnt, 0, total_elems(store_, head_)};
        }

        const_iterator end() const
        {
            return {store_, INVALID_REF, nullptr, 0, 0, total_elems(store_, head_)};
        }
    };

    template<class T>
    SpanView<T> span(Ref ref) const
    {
        return SpanView<T>(this, ref);
    }
};

SWC_END_NAMESPACE();

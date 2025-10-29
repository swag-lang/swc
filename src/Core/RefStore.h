// ReSharper disable CppInconsistentNaming
#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE()

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
        alignas(alignof(std::max_align_t)) std::byte storage[N]{};
        uint32_t used = 0;

        uint8_t*       bytes() noexcept { return reinterpret_cast<uint8_t*>(&storage); }
        const uint8_t* bytes() const noexcept { return reinterpret_cast<const uint8_t*>(&storage); }
    };

    std::vector<std::unique_ptr<Page>> pages_;
    uint64_t                           totalBytes_ = 0; // payload bytes (wider to avoid overflow)

    // Fast-path cache for the current page
    Page*    cur_      = nullptr;
    uint32_t curIndex_ = 0;

    Page* newPage()
    {
        pages_.emplace_back(std::make_unique<Page>());
        cur_      = pages_.back().get();
        curIndex_ = static_cast<uint32_t>(pages_.size() - 1);
        return cur_;
    }

    // Convert (page, offset) -> global byte index Ref
    static constexpr Ref makeRef(uint32_t pageIndex, uint32_t offset) noexcept
    {
        const uint64_t r = static_cast<uint64_t>(pageIndex) * static_cast<uint64_t>(N) + offset;
        SWC_ASSERT(r < std::numeric_limits<Ref>::max());
        return static_cast<Ref>(r);
    }

    // Convert Ref -> (page, offset)
    static constexpr void decodeRef(Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept
    {
        pageIndex = ref / N;
        offset    = ref % N;
    }

    // Allocate raw bytes with alignment; returns (ref, ptr) pair
    std::pair<Ref, void*> allocate(uint32_t size, uint32_t align)
    {
        SWC_ASSERT(size <= N && (align & (align - 1)) == 0 && align <= alignof(std::max_align_t));

        Page* page = cur_ ? cur_ : newPage();

        // Align current position (page start is already max-aligned)
        uint32_t offset = (page->used + (align - 1)) & ~(align - 1);

        // New page if not enough space
        if (offset + size > N)
        {
            page   = newPage();
            offset = 0; // page start is max-aligned -> OK for all T
        }

        page->used = offset + size;
        totalBytes_ += size;

        const Ref r = makeRef(curIndex_, offset);
        return {r, static_cast<void*>(page->bytes() + offset)};
    }

public:
    RefStore() = default;

    // Non-copyable (owning raw buffers)
    RefStore(const RefStore&)            = delete;
    RefStore& operator=(const RefStore&) = delete;

    // Movable
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
            std::swap(pages_, other.pages_);
            std::swap(totalBytes_, other.totalBytes_);
            std::swap(cur_, other.cur_);
            std::swap(curIndex_, other.curIndex_);
        }
        return *this;
    }

    void clear() noexcept
    {
        for (auto& up : pages_)
            up->used = 0;
        totalBytes_ = 0;

        // keep capacity and current page for reuse
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

    // payload bytes (clamped to 32 bits to match the previous signature)
    uint32_t size() const noexcept
    {
        return static_cast<uint32_t>(std::min<uint64_t>(totalBytes_, std::numeric_limits<uint32_t>::max()));
    }

    // Allocate and copy a POD value (bitwise)
    template<class T>
    Ref push_back(const T& v)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        auto [r, p]         = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        *static_cast<T*>(p) = v;
        return r;
    }

    // Allocate uninitialized storage for T; returns a pointer to fill in-place.
    template<class T>
    std::pair<Ref, T*> emplace_uninit()
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    // Allocate raw bytes with chosen alignment
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
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        uint32_t pageIndex, offset;
        decodeRef(ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages.size());
        SWC_ASSERT(offset + sizeof(T) <= N);
        return reinterpret_cast<T*>(pages[pageIndex]->bytes() + offset);
    }

    struct SpanHdrRaw
    {
        // Minimal header: store only the total number of elements in the span.
        // This is read from the *first* header; subsequent chunks recompute their count from layout.
        uint32_t total;
    };

    static constexpr uint32_t align_up_u32(uint32_t v, uint32_t a) noexcept
    {
        return (v + (a - 1)) & ~(a - 1);
    }

    // Compute where the data begins (after header, aligned to T) for a given header ref.
    template<class T>
    static uint32_t data_offset_from_hdr(uint32_t hdrOffset) noexcept
    {
        const uint32_t hdrSize = static_cast<uint32_t>(sizeof(SpanHdrRaw));
        const uint32_t align   = static_cast<uint32_t>(alignof(T));
        return align_up_u32(hdrOffset + hdrSize, align);
    }

    // Write one chunk (header + padding + data) on current/new page(s) as needed.
    // Precondition: at least one T will fit when this is called.
    template<class T>
    std::pair<Ref, uint32_t> write_chunk(const T* src, uint32_t remaining, uint32_t totalElems)
    {
        Page* page = cur_ ? cur_ : newPage();

        // Attempt on the current page
        uint32_t       off        = page->used; // header has no special alignment
        const uint32_t bytesAvail = N - off;

        const uint32_t dataOffset = data_offset_from_hdr<T>(off);
        const uint32_t padBytes   = dataOffset - (off + static_cast<uint32_t>(sizeof(SpanHdrRaw)));

        // If we can't fit header+pad+one T, start a fresh page (header at 0)
        if (sizeof(SpanHdrRaw) + padBytes + sizeof(T) > bytesAvail)
        {
            page = newPage();
            off  = 0;
        }

        // Recompute for (potentially) new page
        const uint32_t dataOffsetF = data_offset_from_hdr<T>(off);
        const uint32_t maxData     = N - dataOffsetF;
        const uint32_t cap         = maxData / static_cast<uint32_t>(sizeof(T));
        const uint32_t fit         = std::min<uint32_t>(remaining, cap);
        SWC_ASSERT(fit > 0);

        // Reserve space (advance used)
        const Ref      hdrRef  = makeRef(curIndex_, off);
        const uint32_t newUsed = dataOffsetF + fit * static_cast<uint32_t>(sizeof(T));
        SWC_ASSERT(newUsed <= N);
        page->used = newUsed;
        totalBytes_ += static_cast<uint32_t>(sizeof(SpanHdrRaw)) + (dataOffsetF - (off + static_cast<uint32_t>(sizeof(SpanHdrRaw)))) + fit * static_cast<uint32_t>(sizeof(T));

        // Write header (only 'total' is needed; duplicate in all chunks for convenience)
        auto* hdr  = reinterpret_cast<SpanHdrRaw*>(page->bytes() + off);
        hdr->total = totalElems;

        // Copy payload
        std::memcpy(page->bytes() + dataOffsetF, src, static_cast<size_t>(fit) * sizeof(T));

        return {hdrRef, fit};
    }

public:
    // Store a span of T split across pages. Returns Ref to the FIRST CHUNK HEADER.
    template<class T>
    Ref push_span(const std::span<T>& s)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");

        const T* src       = s.data();
        auto     remaining = static_cast<uint32_t>(s.size());

        // Always emit a header so span<>() works even for empty spans.
        if (remaining == 0)
        {
            Page*          page = cur_ ? cur_ : newPage();
            const uint32_t need = static_cast<uint32_t>(sizeof(SpanHdrRaw));
            if (page->used + need > N)
                page = newPage();
            const Ref hdrRef = makeRef(curIndex_, page->used);
            auto*     hdr    = reinterpret_cast<SpanHdrRaw*>(page->bytes() + page->used);
            hdr->total       = 0;
            page->used += need;
            totalBytes_ += need;
            return hdrRef;
        }

        const uint32_t totalElems = remaining;

        Ref firstRef = INVALID_REF;

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

        // Compute data pointer for given header; caller decides how many elements fit.
        static const T* data_ptr(const RefStore* st, Ref hdrRef)
        {
            uint32_t pageIndex, off;
            decodeRef(hdrRef, pageIndex, off);
            const uint32_t dataOffset = data_offset_from_hdr<T>(off);
            return reinterpret_cast<const T*>(st->pages_[pageIndex]->bytes() + dataOffset);
        }

        // Number of elements in the full span (read from the first header)
        static uint32_t total_elems(const RefStore* st, Ref hdrRef)
        {
            return st->ptr<SpanHdrRaw>(hdrRef)->total;
        }

        // Given a header on some page and remaining elements, compute this chunk's count.
        static uint32_t chunk_count_from_layout(Ref hdrRef, uint32_t remaining)
        {
            uint32_t pageIndex, off;
            decodeRef(hdrRef, pageIndex, off);
            const uint32_t dataOffset = data_offset_from_hdr<T>(off);
            const uint32_t capBytes   = N - dataOffset;
            const uint32_t cap        = capBytes / static_cast<uint32_t>(sizeof(T));
            return std::min<uint32_t>(cap, remaining);
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

        // Chunk-wise iteration
        struct chunk
        {
            const T* ptr;
            uint32_t count;
        };

        struct chunk_iterator
        {
            const RefStore* store  = nullptr;
            Ref             hdrRef = INVALID_REF; // current chunk header
            uint32_t        total  = 0;
            uint32_t        done   = 0;
            chunk           current{nullptr, 0};

            bool         operator!=(const chunk_iterator& o) const { return hdrRef != o.hdrRef; }
            const chunk& operator*() const { return current; }
            const chunk* operator->() const { return &current; }

            chunk_iterator& operator++()
            {
                done += current.count;
                if (done >= total)
                {
                    hdrRef  = INVALID_REF;
                    current = {nullptr, 0};
                    return *this;
                }

                // Next chunk starts at the beginning of the next page
                uint32_t  pageIndex, off;
                const Ref cur = hdrRef;
                decodeRef(cur, pageIndex, off);
                const Ref nextHdr = makeRef(pageIndex + 1, 0);

                hdrRef                   = nextHdr;
                const uint32_t remaining = total - done;
                const uint32_t cnt       = chunk_count_from_layout(hdrRef, remaining);
                const T*       p         = SpanView::data_ptr(store, hdrRef);
                current                  = {p, cnt};
                return *this;
            }
        };

        chunk_iterator chunks_begin() const
        {
            chunk_iterator it;
            it.store  = store_;
            it.hdrRef = head_;
            it.total  = total_elems(store_, head_);
            it.done   = 0;

            if (it.total == 0)
            {
                it.hdrRef  = INVALID_REF;
                it.current = {nullptr, 0};
                return it;
            }

            const uint32_t cnt = chunk_count_from_layout(head_, it.total);
            const T*       p   = data_ptr(store_, head_);
            it.current         = {p, cnt};
            return it;
        }

        chunk_iterator chunks_end() const
        {
            return {store_, INVALID_REF, 0, 0, {nullptr, 0}};
        }

        // Element-wise const iterator spanning chunks
        struct const_iterator
        {
            const RefStore* store       = nullptr;
            Ref             curHdr      = INVALID_REF; // header of current chunk
            const T*        curPtr      = nullptr;     // pointer to current element
            uint32_t        leftInChunk = 0;           // elements left in current chunk (including curPtr)
            uint32_t        done        = 0;           // total elements produced so far
            uint32_t        total       = 0;           // total elements in the span

            using value_type        = T;
            using difference_type   = std::ptrdiff_t;
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

                // consumed last element in this chunk
                ++done;
                if (done >= total)
                {
                    // end()
                    curHdr      = INVALID_REF;
                    curPtr      = nullptr;
                    leftInChunk = 0;
                    return *this;
                }

                // Move to next page's chunk
                uint32_t pageIndex, off;
                decodeRef(curHdr, pageIndex, off);
                curHdr = makeRef(pageIndex + 1, 0);

                const uint32_t remaining = total - done;
                leftInChunk              = chunk_count_from_layout(curHdr, remaining);
                curPtr                   = SpanView::data_ptr(store, curHdr);
                return *this;
            }

            const_iterator operator++(int)
            {
                auto t = *this;
                ++(*this);
                return t;
            }

            friend bool operator==(const const_iterator& a, const const_iterator& b)
            {
                return a.store == b.store && a.curHdr == b.curHdr && a.curPtr == b.curPtr && a.leftInChunk == b.leftInChunk && a.done == b.done && a.total == b.total;
            }

            friend bool operator!=(const const_iterator& a, const const_iterator& b)
            {
                return !(a == b);
            }
        };

        const_iterator begin() const
        {
            const uint32_t tot = total_elems(store_, head_);
            if (tot == 0)
                return {store_, INVALID_REF, nullptr, 0, 0, 0};

            const uint32_t cnt = chunk_count_from_layout(head_, tot);
            const T*       p   = data_ptr(store_, head_);
            return {store_, head_, p, cnt, 0, tot};
        }

        const_iterator end() const
        {
            const uint32_t tot = total_elems(store_, head_);
            return {store_, INVALID_REF, nullptr, 0, tot, tot};
        }
    };

    // Build a SpanView<T> for a Ref produced by push_span<T>()
    template<class T>
    SpanView<T> span(Ref ref) const
    {
        return SpanView<T>(this, ref);
    }
};

SWC_END_NAMESPACE()

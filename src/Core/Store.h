// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE()

using Ref = uint32_t;

// Simple page-based POD store.
// Each page holds up to pageSize bytes of raw data (pageSize must be a power of two).
// Items are packed sequentially; alignment is preserved relative to a max-aligned base.
// Ref is a 32-bit index in BYTES from the start of the store.
class Store
{
    static constexpr uint32_t kDefaultPageSize = 16u * 1024u;

    struct Page
    {
        std::byte* storage_ = nullptr;
        uint32_t   used     = 0;

        static std::byte* allocate_aligned(uint32_t size);
        static void       deallocate_aligned(std::byte* p) noexcept;

        explicit Page(uint32_t pageSize);
        ~Page();

        uint8_t*       bytes() noexcept { return reinterpret_cast<uint8_t*>(storage_); }
        const uint8_t* bytes() const noexcept { return reinterpret_cast<const uint8_t*>(storage_); }
    };

    std::vector<std::unique_ptr<Page>> pages_;
    uint64_t                           totalBytes_ = 0; // payload bytes (wider to avoid overflow)
    uint32_t                           pageSize_   = kDefaultPageSize;

    // Fast-path cache for the current page
    Page*    cur_      = nullptr;
    uint32_t curIndex_ = 0;

    Page* newPage();

    // Convert (page, offset) -> global byte index Ref
    static Ref makeRef(uint32_t pageSize, uint32_t pageIndex, uint32_t offset) noexcept;

    // Convert Ref -> (page, offset)
    static void decodeRef(uint32_t pageSize, Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept;

    // Allocate raw bytes with alignment; returns a (ref, ptr)
    std::pair<Ref, void*> allocate(uint32_t size, uint32_t align);

public:
    explicit Store(uint32_t pageSize = kDefaultPageSize);

    Store(const Store&)            = delete;
    Store& operator=(const Store&) = delete;

    Store(Store&& other) noexcept;
    Store& operator=(Store&& other) noexcept;

    uint32_t pageSize() const noexcept { return pageSize_; }

    void clear() noexcept;

    // payload bytes (clamped to 32 bits to match the previous signature)
    uint32_t size() const noexcept;

    // Allocate and copy a POD value (bitwise)
    template<class T>
    Ref push_back(const T& v)
    {
        auto [r, p]         = allocate(static_cast<uint32_t>(sizeof(T)),
                                       static_cast<uint32_t>(alignof(T)));
        *static_cast<T*>(p) = v;
        return r;
    }

    // Allocate uninitialized storage for T; returns a pointer to fill in-place.
    template<class T>
    std::pair<Ref, T*> emplace_uninit()
    {
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T)),
                               static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    // Allocate raw bytes with chosen alignment
    std::pair<Ref, void*> push_back_raw(uint32_t size,
                                        uint32_t align = alignof(std::max_align_t))
    {
        return allocate(size, align);
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        return ptr_impl<T>(pages_, pageSize_, ref);
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        return ptr_impl<T>(pages_, pageSize_, ref);
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
    static T* ptr_impl(const std::vector<std::unique_ptr<Page>>& pages,
                       uint32_t                                  pageSize,
                       Ref                                       ref)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        uint32_t pageIndex, offset;
        decodeRef(pageSize, ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages.size());
        SWC_ASSERT(offset + sizeof(T) <= pageSize);
        return reinterpret_cast<T*>(pages[pageIndex]->bytes() + offset);
    }

    struct SpanHdrRaw
    {
        // Minimal header: store only the total number of elements in the span.
        // This is read from the *first* header; later chunks recompute their count from layout.
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
    std::pair<SpanRef, uint32_t> write_chunk(const T* src,
                                             uint32_t remaining,
                                             uint32_t totalElems)
    {
        Page* page = cur_ ? cur_ : newPage();

        // Attempt on the current page
        uint32_t       off        = page->used; // the header has no special alignment
        const uint32_t bytesAvail = pageSize_ - off;

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
        const uint32_t maxData     = pageSize_ - dataOffsetF;
        const uint32_t cap         = maxData / static_cast<uint32_t>(sizeof(T));
        const uint32_t fit         = std::min<uint32_t>(remaining, cap);
        SWC_ASSERT(fit > 0);

        // Reserve space (advance used)
        const SpanRef  hdrRef{makeRef(pageSize_, curIndex_, off)};
        const uint32_t newUsed = dataOffsetF + fit * static_cast<uint32_t>(sizeof(T));
        SWC_ASSERT(newUsed <= pageSize_);
        page->used = newUsed;
        totalBytes_ += static_cast<uint32_t>(sizeof(SpanHdrRaw)) +
                       (dataOffsetF - (off + static_cast<uint32_t>(sizeof(SpanHdrRaw)))) +
                       fit * static_cast<uint32_t>(sizeof(T));

        // Write header (only 'total' is needed; duplicate in all chunks for convenience)
        auto* hdr  = reinterpret_cast<SpanHdrRaw*>(page->bytes() + off);
        hdr->total = totalElems;

        // Copy payload
        std::memcpy(page->bytes() + dataOffsetF, src, static_cast<size_t>(fit) * sizeof(T));

        return {hdrRef, fit};
    }

public:
    // Store a span of T split across pages. Returns Ref to the first chunk header
    template<class T>
    SpanRef push_span(const std::span<T>& s)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");

        if (s.empty())
            return SpanRef::invalid();

        const T* src       = s.data();
        auto     remaining = static_cast<uint32_t>(s.size());

        // Always emit a header so span<>() works even for empty spans.
        if (remaining == 0)
        {
            Page*          page = cur_ ? cur_ : newPage();
            const uint32_t need = static_cast<uint32_t>(sizeof(SpanHdrRaw));
            if (page->used + need > pageSize_)
                page = newPage();
            const SpanRef hdrRef{makeRef(pageSize_, curIndex_, page->used)};
            auto*         hdr = reinterpret_cast<SpanHdrRaw*>(page->bytes() + page->used);
            hdr->total        = 0;
            page->used += need;
            totalBytes_ += need;
            return hdrRef;
        }

        const uint32_t totalElems = remaining;
        SpanRef        firstRef   = SpanRef::invalid();

        while (remaining)
        {
            auto [hdrRef, wrote] = write_chunk<T>(src, remaining, totalElems);

            if (firstRef.isInvalid())
                firstRef = hdrRef;

            src += wrote;
            remaining -= wrote;
        }

        return firstRef;
    }

    template<class T>
    class SpanView
    {
        const Store* store_;
        Ref          head_;

        static void decode_ref(const Store* st, Ref ref, uint32_t& pageIndex, uint32_t& off)
        {
            Store::decodeRef(st->pageSize(), ref, pageIndex, off);
        }

        // Compute a data pointer for given header; caller decides how many elements fit.
        static const T* data_ptr(const Store* st, Ref hdrRef)
        {
            uint32_t pageIndex, off;
            decode_ref(st, hdrRef, pageIndex, off);
            const uint32_t dataOffset = data_offset_from_hdr<T>(off);
            return reinterpret_cast<const T*>(st->pages_[pageIndex]->bytes() + dataOffset);
        }

        // Number of elements in the full span (read from the first header)
        static uint32_t total_elems(const Store* st, Ref hdrRef)
        {
            return st->template ptr<SpanHdrRaw>(hdrRef)->total;
        }

        // Given a header on some page and remaining elements, compute this chunk's count.
        static uint32_t chunk_count_from_layout(const Store* st,
                                                Ref          hdrRef,
                                                uint32_t     remaining)
        {
            uint32_t pageIndex, off;
            decode_ref(st, hdrRef, pageIndex, off);
            const uint32_t dataOffset = data_offset_from_hdr<T>(off);
            const uint32_t capBytes   = st->pageSize() - dataOffset;
            const uint32_t cap        = capBytes / static_cast<uint32_t>(sizeof(T));
            return std::min<uint32_t>(cap, remaining);
        }

    public:
        explicit SpanView(const Store* s, Ref r) :
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
            const Store* store  = nullptr;
            Ref          hdrRef = UINT32_MAX;
            uint32_t     total  = 0;
            uint32_t     done   = 0;
            chunk        current{nullptr, 0};

            bool         operator!=(const chunk_iterator& o) const { return hdrRef != o.hdrRef; }
            const chunk& operator*() const { return current; }
            const chunk* operator->() const { return &current; }

            chunk_iterator& operator++()
            {
                done += current.count;
                if (done >= total)
                {
                    hdrRef  = UINT32_MAX;
                    current = {nullptr, 0};
                    return *this;
                }

                // The next chunk starts at the beginning of the next page
                uint32_t  pageIndex, off;
                const Ref cur = hdrRef;
                decode_ref(store, cur, pageIndex, off);
                const Ref nextHdr = Store::makeRef(store->pageSize(), pageIndex + 1, 0);

                hdrRef                   = nextHdr;
                const uint32_t remaining = total - done;
                const uint32_t cnt       = chunk_count_from_layout(store, hdrRef, remaining);
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
                it.hdrRef  = UINT32_MAX;
                it.current = {nullptr, 0};
                return it;
            }

            const uint32_t cnt = chunk_count_from_layout(store_, head_, it.total);
            const T*       p   = data_ptr(store_, head_);
            it.current         = {p, cnt};
            return it;
        }

        chunk_iterator chunks_end() const
        {
            return {store_, UINT32_MAX, 0, 0, {nullptr, 0}};
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

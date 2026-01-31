// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE();

using Ref = uint32_t;

struct SpanTag
{
};
using SpanRef = StrongRef<SpanTag>;

// Simple page-based POD store.
// Each page holds up to pageSize bytes of raw data (pageSize must be a power of two).
// Items are packed sequentially; alignment is preserved relative to a max-aligned base.
// Ref is a 32-bit index in BYTES from the start of the store.
class Store
{
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
        auto [r, p]         = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        *static_cast<T*>(p) = v;
        return r;
    }

    // Allocate uninitialized storage for T; returns a pointer to fill in-place.
    template<class T>
    std::pair<Ref, T*> emplace_uninit()
    {
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    // Allocate and copy raw bytes; returns a stable view + its Ref.
    std::pair<ByteSpan, Ref> push_copy_span(ByteSpan payload, uint32_t align = alignof(std::byte))
    {
        auto [ref, dst] = allocate(static_cast<uint32_t>(payload.size()), align);
        std::memcpy(dst, payload.data(), payload.size());
        return {{static_cast<const std::byte*>(dst), payload.size()}, ref};
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

    // Non-templated raw span push: data = contiguous array of elements (elemSize/elemAlign),
    // count = number of elements. Returns Ref to first chunk header.
    SpanRef push_span_raw(const void* data, uint32_t elemSize, uint32_t elemAlign, uint32_t count);

    // Templated convenience wrapper for typed spans.
    template<class T>
    SpanRef push_span(const std::span<T>& s)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        return push_span_raw(s.data(), static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)), static_cast<uint32_t>(s.size()));
    }

    // Span view over stored data (type-erased; elements described by size+alignment).
    class SpanView
    {
        const Store* store_     = nullptr;
        Ref          head_      = std::numeric_limits<Ref>::max();
        uint32_t     elemSize_  = 0;
        uint32_t     elemAlign_ = 0;

        static void        decode_ref(const Store* st, Ref ref, uint32_t& pageIndex, uint32_t& off);
        static uint32_t    data_offset_from_hdr(uint32_t hdrOffset, uint32_t elemAlign);
        static const void* data_ptr(const Store* st, Ref hdrRef, uint32_t elemAlign);
        static uint32_t    total_elems(const Store* st, Ref hdrRef);
        static uint32_t    chunk_count_from_layout(const Store* st, Ref hdrRef, uint32_t remaining, uint32_t elemSize, uint32_t elemAlign);

    public:
        SpanView() = default;
        SpanView(const Store* s, Ref r, uint32_t elemSize, uint32_t elemAlign);

        uint32_t size() const;
        bool     empty() const { return size() == 0; }
        Ref      ref() const { return head_; }
        uint32_t elemSize() const { return elemSize_; }
        uint32_t elemAlign() const { return elemAlign_; }

        struct chunk
        {
            const void* ptr;
            uint32_t    count; // number of elements, not bytes
        };

        struct chunk_iterator
        {
            const Store* store     = nullptr;
            Ref          hdrRef    = std::numeric_limits<Ref>::max();
            uint32_t     total     = 0;
            uint32_t     done      = 0;
            uint32_t     elemSize  = 0;
            uint32_t     elemAlign = 0;
            chunk        current{nullptr, 0};

            bool         operator!=(const chunk_iterator& o) const;
            const chunk& operator*() const { return current; }
            const chunk* operator->() const { return &current; }

            chunk_iterator& operator++();
        };

        chunk_iterator chunks_begin() const;
        chunk_iterator chunks_end() const;
    };

    // Build a type-erased SpanView given the element size and alignment.
    SpanView span_view(Ref ref, uint32_t elemSize, uint32_t elemAlign) const;

    // Templated "last mile" helper: same layout, but you reinterpret chunks as T.
    template<class T>
    SpanView span(Ref ref) const
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        return span_view(ref, static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
    }

    Ref findRef(const void* ptr) const noexcept;

private:
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

    struct SpanHdrRaw
    {
        uint32_t total;
    };

    std::vector<std::unique_ptr<Page>> pages_;

    uint64_t totalBytes_ = 0;
    uint32_t pageSize_   = kDefaultPageSize;
    Page*    cur_        = nullptr;
    uint32_t curIndex_   = 0;

    Page*                                     newPage();
    const std::vector<std::unique_ptr<Page>>& pages() const { return pages_; }
    static Ref                                makeRef(uint32_t pageSize, uint32_t pageIndex, uint32_t offset) noexcept;
    static void                               decodeRef(uint32_t pageSize, Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept;
    std::pair<Ref, void*>                     allocate(uint32_t size, uint32_t align);
    static constexpr uint32_t                 align_up_u32(uint32_t v, uint32_t a) noexcept { return (v + (a - 1)) & ~(a - 1); }
    std::pair<SpanRef, uint32_t>              write_chunk_raw(const uint8_t* src, uint32_t elemSize, uint32_t elemAlign, uint32_t remaining, uint32_t totalElems);

    template<class T>
    static T* ptr_impl(const std::vector<std::unique_ptr<Page>>& pages, uint32_t pageSize, Ref ref)
    {
        uint32_t pageIndex, offset;
        decodeRef(pageSize, ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages.size());
        SWC_ASSERT(offset + sizeof(T) <= pageSize);
        return reinterpret_cast<T*>(pages[pageIndex]->bytes() + offset);
    }
};

SWC_END_NAMESPACE();

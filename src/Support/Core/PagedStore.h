#pragma once

SWC_BEGIN_NAMESPACE();

using Ref                 = uint32_t;
constexpr Ref INVALID_REF = std::numeric_limits<Ref>::max();

template<class T>
class TypedPagedStore;

struct SpanTag
{
};
using SpanRef = StrongRef<SpanTag>;

// Simple page-based store.
// Each page holds up to pageSize bytes of raw data (pageSize must be a power of two).
// Items are packed sequentially; alignment is preserved relative to a max-aligned base.
// Ref is a 32-bit index in BYTES from the start of the store.
class PagedStore
{
public:
    explicit PagedStore(uint32_t pageSize = K_DEFAULT_PAGE_SIZE);

    PagedStore(const PagedStore&)            = delete;
    PagedStore& operator=(const PagedStore&) = delete;

    PagedStore(PagedStore&& other) noexcept;
    PagedStore& operator=(PagedStore&& other) noexcept;

    uint32_t pageSize() const noexcept { return pageSizeValue_; }

    void clear() noexcept;

    // payload bytes (clamped to 32 bits to match the previous signature)
    uint32_t size() const noexcept;

    uint8_t* seekPtr() const noexcept { return lastPtr_; }

    template<class T>
    Ref pushBack(const T& v)
    {
        auto [r, p]         = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        *static_cast<T*>(p) = v;
        return r;
    }

    template<class T>
    uint8_t* pushPod(const T& v)
    {
        auto [ref, p] = emplaceUninit<T>();
        (void) ref;
        *p       = v;
        lastPtr_ = reinterpret_cast<uint8_t*>(p) + sizeof(T);
        return lastPtr_;
    }

    uint8_t* pushU8(uint8_t v) { return pushPod(v); }
    uint8_t* pushU16(uint16_t v) { return pushPod(v); }
    uint8_t* pushU32(uint32_t v) { return pushPod(v); }
    uint8_t* pushU64(uint64_t v) { return pushPod(v); }
    uint8_t* pushS32(int32_t v) { return pushPod(v); }

    // Allocate uninitialized storage for T; returns a pointer to fill in-place.
    template<class T>
    std::pair<Ref, T*> emplaceUninit()
    {
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    template<class T>
    std::pair<Ref, T*> emplaceUninitArray(uint32_t count)
    {
        if (count == 0)
            return {std::numeric_limits<Ref>::max(), nullptr};
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T) * count), static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    // Allocate and copy raw bytes; returns a stable view + its Ref.
    std::pair<ByteSpan, Ref> pushCopySpan(ByteSpan payload, uint32_t align = alignof(std::byte))
    {
        auto [ref, dst] = allocate(static_cast<uint32_t>(payload.size()), align);
        if (payload.data()) // TODO
            std::memcpy(dst, payload.data(), payload.size());
        return {{static_cast<const std::byte*>(dst), payload.size()}, ref};
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        return ptrImpl<T>(pagesStorage_, pageSizeValue_, ref);
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        return ptrImpl<T>(pagesStorage_, pageSizeValue_, ref);
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
    SpanRef pushSpanRaw(const void* data, uint32_t elemSize, uint32_t elemAlign, uint32_t count);

    // Templated convenience wrapper for typed spans.
    template<class T>
    SpanRef pushSpan(const std::span<T>& s)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        return pushSpanRaw(s.data(), static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)), static_cast<uint32_t>(s.size()));
    }

    // Span view over stored data (type-erased; elements described by size+alignment).
    class SpanView
    {
        const PagedStore* store_        = nullptr;
        Ref               head_         = std::numeric_limits<Ref>::max();
        uint32_t          elementSize_  = 0;
        uint32_t          elementAlign_ = 0;

        static void        decodeRef(const PagedStore* st, Ref ref, uint32_t& pageIndex, uint32_t& off);
        static uint32_t    dataOffsetFromHdr(uint32_t hdrOffset, uint32_t elemAlign);
        static const void* dataPtr(const PagedStore* st, Ref hdrRef, uint32_t elemAlign);
        static uint32_t    totalElems(const PagedStore* st, Ref hdrRef);
        static uint32_t    chunkCountFromLayout(const PagedStore* st, Ref hdrRef, uint32_t remaining, uint32_t elemSize, uint32_t elemAlign);

    public:
        SpanView() = default;
        SpanView(const PagedStore* s, Ref r, uint32_t elemSize, uint32_t elemAlign);

        uint32_t size() const;
        bool     empty() const { return size() == 0; }
        Ref      ref() const { return head_; }
        uint32_t elemSize() const { return elementSize_; }
        uint32_t elemAlign() const { return elementAlign_; }

        struct Chunk
        {
            const void* ptr;
            uint32_t    count;
        };

        struct ChunkIterator
        {
            const PagedStore* store     = nullptr;
            Ref               hdrRef    = std::numeric_limits<Ref>::max();
            uint32_t          total     = 0;
            uint32_t          done      = 0;
            uint32_t          elemSize  = 0;
            uint32_t          elemAlign = 0;
            Chunk             current{nullptr, 0};

            bool         operator!=(const ChunkIterator& o) const;
            const Chunk& operator*() const { return current; }
            const Chunk* operator->() const { return &current; }

            ChunkIterator& operator++();
        };

        ChunkIterator chunksBegin() const;
        ChunkIterator chunksEnd() const;
    };

    // Build a type-erased SpanView given the element size and alignment.
    SpanView spanView(Ref ref, uint32_t elemSize, uint32_t elemAlign) const;

    // Templated "last mile" helper: same layout, but you reinterpret chunks as T.
    template<class T>
    SpanView span(Ref ref) const
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        return spanView(ref, static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
    }

    Ref findRef(const void* ptr) const noexcept;

private:
    template<class T>
    friend class TypedPagedStore;

    static constexpr uint32_t K_DEFAULT_PAGE_SIZE = 16u * 1024u;

    struct Page
    {
        std::byte* storage = nullptr;
        uint32_t   used    = 0;

        static std::byte* allocateAligned(uint32_t size);
        static void       deallocateAligned(std::byte* p) noexcept;

        explicit Page(uint32_t pageSize);
        ~Page();

        uint8_t*       bytes() noexcept { return reinterpret_cast<uint8_t*>(storage); }
        const uint8_t* bytes() const noexcept { return reinterpret_cast<const uint8_t*>(storage); }
    };

    struct SpanHdrRaw
    {
        uint32_t total;
    };

    Page*                                     newPage();
    const std::vector<std::unique_ptr<Page>>& pages() const { return pagesStorage_; }
    static Ref                                makeRef(uint32_t pageSize, uint32_t pageIndex, uint32_t offset) noexcept;
    static void                               decodeRef(uint32_t pageSize, Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept;
    std::pair<Ref, void*>                     allocate(uint32_t size, uint32_t align);
    static constexpr uint32_t                 alignUpU32(uint32_t v, uint32_t a) noexcept { return (v + (a - 1)) & ~(a - 1); }
    std::pair<SpanRef, uint32_t>              writeChunkRaw(const uint8_t* src, uint32_t elemSize, uint32_t elemAlign, uint32_t remaining, uint32_t totalElems);

    template<class T>
    static T* ptrImpl(const std::vector<std::unique_ptr<Page>>& pages, uint32_t pageSize, Ref ref)
    {
        uint32_t pageIndex, offset;
        decodeRef(pageSize, ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages.size());
        SWC_ASSERT(offset + sizeof(T) <= pageSize);
        return reinterpret_cast<T*>(pages[pageIndex]->bytes() + offset);
    }

    std::vector<std::unique_ptr<Page>> pagesStorage_;
    uint64_t                           totalBytes_    = 0;
    uint32_t                           pageSizeValue_ = K_DEFAULT_PAGE_SIZE;
    Page*                              curPage_       = nullptr;
    uint32_t                           curPageIndex_  = 0;
    uint8_t*                           lastPtr_       = nullptr;
};

SWC_END_NAMESPACE();

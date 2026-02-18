#pragma once

SWC_BEGIN_NAMESPACE();

using Ref                 = uint32_t;
constexpr Ref INVALID_REF = std::numeric_limits<Ref>::max();

template<class T>
class PagedStoreTyped;

struct SpanTag
{
};
using SpanRef = StrongRef<SpanTag>;

class PagedStore
{
public:
    class SpanView;
    static constexpr uint32_t K_DEFAULT_PAGE_SIZE = 16u * 1024u;

    explicit PagedStore(uint32_t pageSize = K_DEFAULT_PAGE_SIZE);

    PagedStore(const PagedStore&)            = delete;
    PagedStore& operator=(const PagedStore&) = delete;
    PagedStore(PagedStore&& other) noexcept;
    PagedStore& operator=(PagedStore&& other) noexcept;

    uint32_t pageSize() const noexcept { return pageSizeValue_; }
    uint32_t size() const noexcept;
    uint8_t* seekPtr() const noexcept { return lastPtr_; }
    void     clear() noexcept;
    void     copyTo(ByteSpanRW dst) const;

    uint8_t* pushU8(uint8_t v) { return pushPod(v); }
    uint8_t* pushU16(uint16_t v) { return pushPod(v); }
    uint8_t* pushU32(uint32_t v) { return pushPod(v); }
    uint8_t* pushU64(uint64_t v) { return pushPod(v); }
    uint8_t* pushS8(int8_t v) { return pushPod(v); }
    uint8_t* pushS16(int16_t v) { return pushPod(v); }
    uint8_t* pushS32(int32_t v) { return pushPod(v); }
    uint8_t* pushS64(int64_t v) { return pushPod(v); }

    std::pair<ByteSpan, Ref> pushCopySpan(ByteSpan payload, uint32_t align = alignof(std::byte));
    SpanRef                  pushSpanRaw(const void* data, uint32_t elemSize, uint32_t elemAlign, uint32_t count);
    SpanView                 spanView(Ref ref, uint32_t elemSize, uint32_t elemAlign) const;
    Ref                      findRef(const void* ptr) const noexcept;

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
        auto [_, p] = allocate(static_cast<uint32_t>(sizeof(T)), 1);
        std::memcpy(p, &v, sizeof(T));
        lastPtr_ = static_cast<uint8_t*>(p) + sizeof(T);
        return lastPtr_;
    }

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
            return {INVALID_REF, nullptr};

        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T) * count), static_cast<uint32_t>(alignof(T)));
        return {r, static_cast<T*>(p)};
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        SWC_ASSERT(ref != INVALID_REF);
        return ptrImpl<T>(snapshotPages(), pageSizeValue_, ref);
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        SWC_ASSERT(ref != INVALID_REF);
        return ptrImpl<T>(snapshotPages(), pageSizeValue_, ref);
    }

    template<class T>
    T& at(Ref ref) noexcept
    {
        SWC_ASSERT(ref != INVALID_REF);
        return *SWC_CHECK_NOT_NULL(ptr<T>(ref));
    }

    template<class T>
    const T& at(Ref ref) const noexcept
    {
        SWC_ASSERT(ref != INVALID_REF);
        return *SWC_CHECK_NOT_NULL(ptr<T>(ref));
    }

    template<class T>
    SpanRef pushSpan(const std::span<T>& s)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        return pushSpanRaw(s.data(), static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)), static_cast<uint32_t>(s.size()));
    }

    template<class T>
    SpanView span(Ref ref) const;

private:
    template<class T>
    friend class PagedStoreTyped;

    struct Page
    {
        std::byte* storage = nullptr;
        std::atomic<uint32_t> used = 0;

        static std::byte* allocateAligned(uint32_t size);
        static void       deallocateAligned(std::byte* p) noexcept;

        explicit Page(uint32_t pageSize);
        ~Page();

        uint8_t*       bytes() noexcept { return reinterpret_cast<uint8_t*>(storage); }
        const uint8_t* bytes() const noexcept { return reinterpret_cast<const uint8_t*>(storage); }
    };

    struct SpanHdrRaw
    {
        uint32_t total = 0;
    };

    static Ref                   makeRef(uint32_t pageSize, uint32_t pageIndex, uint32_t offset) noexcept;
    static void                  decodeRef(uint32_t pageSize, Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept;
    Page*                        newPage();
    std::pair<Ref, void*>        allocate(uint32_t size, uint32_t align);
    std::pair<SpanRef, uint32_t> writeChunkRaw(const uint8_t* src, uint32_t elemSize, uint32_t elemAlign, uint32_t remaining, uint32_t totalElems);

    template<class T>
    static T* ptrImpl(const std::shared_ptr<const std::vector<Page*>>& pages, uint32_t pageSize, Ref ref)
    {
        uint32_t pageIndex = 0, offset = 0;
        decodeRef(pageSize, ref, pageIndex, offset);

        SWC_ASSERT(pages);
        SWC_ASSERT(pageIndex < pages->size());
        SWC_ASSERT(offset + sizeof(T) <= pageSize);

        return reinterpret_cast<T*>((*pages)[pageIndex]->bytes() + offset);
    }

    std::shared_ptr<const std::vector<Page*>> snapshotPages() const noexcept;
    void                                       publishPages();

    uint32_t       publishedPageCount() const noexcept;
    uint32_t       publishedPageUsed(uint32_t index) const noexcept;
    const uint8_t* publishedPageBytes(uint32_t index) const noexcept;
    uint8_t*       publishedPageBytesMutable(uint32_t index) const noexcept;

    std::vector<std::unique_ptr<Page>>                     pagesStorage_;
    std::atomic<std::shared_ptr<const std::vector<Page*>>> publishedPages_;
    uint64_t                                               totalBytes_    = 0;
    uint32_t                                               pageSizeValue_ = K_DEFAULT_PAGE_SIZE;
    Page*                                                  curPage_       = nullptr;
    uint32_t                                               curPageIndex_  = 0;
    uint8_t*                                               lastPtr_       = nullptr;
};

class PagedStore::SpanView
{
public:
    struct Chunk
    {
        const void* ptr   = nullptr;
        uint32_t    count = 0;
    };

    struct ChunkIterator
    {
        const PagedStore* store     = nullptr;
        Ref               hdrRef    = INVALID_REF;
        uint32_t          total     = 0;
        uint32_t          done      = 0;
        uint32_t          elemSize  = 0;
        uint32_t          elemAlign = 0;
        Chunk             current{nullptr, 0};

        bool           operator!=(const ChunkIterator& o) const;
        const Chunk&   operator*() const { return current; }
        const Chunk*   operator->() const { return &current; }
        ChunkIterator& operator++();
    };

    SpanView() = default;
    SpanView(const PagedStore* s, Ref head, uint32_t elemSize, uint32_t elemAlign);

    uint32_t size() const;
    bool     empty() const { return size() == 0; }
    Ref      ref() const { return head_; }
    uint32_t elemSize() const { return elementSize_; }
    uint32_t elemAlign() const { return elementAlign_; }

    ChunkIterator chunksBegin() const;
    ChunkIterator chunksEnd() const;

private:
    static void        decodeRef(const PagedStore* st, Ref ref, uint32_t& pageIndex, uint32_t& off);
    static uint32_t    dataOffsetFromHdr(uint32_t hdrOffset, uint32_t elemAlign);
    static const void* dataPtr(const PagedStore* st, Ref hdrRef, uint32_t elemAlign);
    static uint32_t    totalElems(const PagedStore* st, Ref hdrRef);
    static uint32_t    chunkCountFromLayout(const PagedStore* st, Ref hdrRef, uint32_t remaining, uint32_t elemSize, uint32_t elemAlign);

    const PagedStore* store_        = nullptr;
    Ref               head_         = INVALID_REF;
    uint32_t          elementSize_  = 0;
    uint32_t          elementAlign_ = 0;
};

template<class T>
PagedStore::SpanView PagedStore::span(Ref ref) const
{
    SWC_ASSERT(ref != INVALID_REF);
    static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
    return spanView(ref, static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
}

SWC_END_NAMESPACE();

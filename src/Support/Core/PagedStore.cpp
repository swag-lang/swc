#include "pch.h"
#include "Support/Core/PagedStore.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

PagedStore::PagedStore(uint32_t pageSize) :
    publishedPages_(std::make_shared<const std::vector<Page*>>()),
    pageSizeValue_(pageSize)
{
    SWC_ASSERT(pageSizeValue_ > 0 && (pageSizeValue_ & (pageSizeValue_ - 1)) == 0);
}

PagedStore::PagedStore(PagedStore&& other) noexcept :
    pagesStorage_(std::move(other.pagesStorage_)),
    publishedPages_(other.publishedPages_.load(std::memory_order_acquire)),
    totalBytes_(other.totalBytes_),
    pageSizeValue_(other.pageSizeValue_),
    curPage_(other.curPage_),
    curPageIndex_(other.curPageIndex_),
    lastPtr_(other.lastPtr_)
{
    other.totalBytes_   = 0;
    other.curPage_      = nullptr;
    other.curPageIndex_ = 0;
    other.lastPtr_      = nullptr;
    other.publishedPages_.store(std::make_shared<const std::vector<Page*>>(), std::memory_order_release);
}

PagedStore& PagedStore::operator=(PagedStore&& other) noexcept
{
    if (this != &other)
    {
        std::swap(pagesStorage_, other.pagesStorage_);
        auto leftSnapshot  = publishedPages_.load(std::memory_order_acquire);
        auto rightSnapshot = other.publishedPages_.load(std::memory_order_acquire);
        publishedPages_.store(rightSnapshot, std::memory_order_release);
        other.publishedPages_.store(leftSnapshot, std::memory_order_release);
        std::swap(totalBytes_, other.totalBytes_);
        std::swap(pageSizeValue_, other.pageSizeValue_);
        std::swap(curPage_, other.curPage_);
        std::swap(curPageIndex_, other.curPageIndex_);
        std::swap(lastPtr_, other.lastPtr_);
    }
    return *this;
}

void PagedStore::clear() noexcept
{
    for (const std::unique_ptr<Page>& up : pagesStorage_)
        up->used.store(0, std::memory_order_relaxed);
    totalBytes_ = 0;

    if (!pagesStorage_.empty())
    {
        curPage_      = pagesStorage_.back().get();
        curPageIndex_ = static_cast<uint32_t>(pagesStorage_.size() - 1);
    }
    else
    {
        curPage_      = nullptr;
        curPageIndex_ = 0;
    }
    lastPtr_ = nullptr;
}

uint32_t PagedStore::size() const noexcept
{
    return static_cast<uint32_t>(std::min<uint64_t>(totalBytes_, std::numeric_limits<uint32_t>::max()));
}

void PagedStore::copyTo(ByteSpanRW dst) const
{
    SWC_ASSERT(dst.size() <= size());

    std::byte* out       = dst.data();
    uint32_t   remaining = static_cast<uint32_t>(dst.size());
    for (const std::unique_ptr<Page>& page : pagesStorage_)
    {
        if (!remaining)
            break;

        const uint32_t chunkSize = std::min(remaining, page->used.load(std::memory_order_relaxed));
        if (chunkSize)
        {
            std::memcpy(out, page->bytes(), chunkSize);
            out += chunkSize;
            remaining -= chunkSize;
        }
    }

    SWC_ASSERT(remaining == 0);
}

std::pair<SpanRef, uint32_t> PagedStore::writeChunkRaw(const uint8_t* src, uint32_t elemSize, uint32_t elemAlign, uint32_t remaining, uint32_t totalElems)
{
    SWC_ASSERT(elemSize > 0);
    SWC_ASSERT((elemAlign & (elemAlign - 1)) == 0 && elemAlign <= alignof(std::max_align_t));

    Page* page = curPage_ ? curPage_ : newPage();

    uint32_t       off        = page->used.load(std::memory_order_relaxed);
    const uint32_t bytesAvail = pageSizeValue_ - off;

    constexpr uint32_t hdrSize    = sizeof(SpanHdrRaw);
    const uint32_t     dataOffset = Math::alignUpU32(off + hdrSize, elemAlign);
    const uint32_t     padBytes   = dataOffset - (off + hdrSize);

    if (hdrSize + padBytes + elemSize > bytesAvail)
    {
        page = newPage();
        off  = 0;
    }

    const uint32_t dataOffsetF = Math::alignUpU32(off + hdrSize, elemAlign);
    const uint32_t maxData     = pageSizeValue_ - dataOffsetF;
    const uint32_t cap         = maxData / elemSize;
    const uint32_t fit         = std::min<uint32_t>(remaining, cap);
    SWC_ASSERT(fit > 0);

    const SpanRef  hdrRef{makeRef(pageSizeValue_, curPageIndex_, off)};
    const uint32_t newUsed = dataOffsetF + fit * elemSize;
    SWC_ASSERT(newUsed <= pageSizeValue_);
    page->used.store(newUsed, std::memory_order_relaxed);
    totalBytes_ += hdrSize + (dataOffsetF - (off + hdrSize)) + fit * elemSize;

    const auto hdr = reinterpret_cast<SpanHdrRaw*>(page->bytes() + off);
    hdr->total     = totalElems;

    std::memcpy(page->bytes() + dataOffsetF, src, static_cast<size_t>(fit) * elemSize);

    return {hdrRef, fit};
}

std::pair<ByteSpan, Ref> PagedStore::pushCopySpan(ByteSpan payload, uint32_t align)
{
    auto [ref, dst] = allocate(static_cast<uint32_t>(payload.size()), align);
    if (payload.data()) // TODO: define expectations for nullptr + nonzero size
        std::memcpy(dst, payload.data(), payload.size());
    return {{static_cast<const std::byte*>(dst), payload.size()}, ref};
}

SpanRef PagedStore::pushSpanRaw(const void* data, uint32_t elemSize, uint32_t elemAlign, uint32_t count)
{
    if (count == 0)
    {
        Page*              page     = curPage_ ? curPage_ : newPage();
        constexpr uint32_t need     = sizeof(SpanHdrRaw);
        uint32_t           pageUsed = page->used.load(std::memory_order_relaxed);
        if (pageUsed + need > pageSizeValue_)
        {
            page     = newPage();
            pageUsed = 0;
        }
        const SpanRef hdrRef{makeRef(pageSizeValue_, curPageIndex_, pageUsed)};
        const auto    hdr = reinterpret_cast<SpanHdrRaw*>(page->bytes() + pageUsed);
        hdr->total        = 0;
        page->used.store(pageUsed + need, std::memory_order_relaxed);
        totalBytes_ += need;
        return hdrRef;
    }

    SWC_ASSERT(data != nullptr);
    auto           src        = static_cast<const uint8_t*>(data);
    uint32_t       remaining  = count;
    const uint32_t totalElems = count;
    SpanRef        firstRef   = SpanRef::invalid();

    while (remaining)
    {
        auto [hdrRef, wrote] = writeChunkRaw(src, elemSize, elemAlign, remaining, totalElems);

        if (firstRef.isInvalid())
            firstRef = hdrRef;

        src += static_cast<size_t>(wrote) * elemSize;
        remaining -= wrote;
    }

    return firstRef;
}

void PagedStore::SpanView::decodeRef(const PagedStore* st, Ref ref, uint32_t& pageIndex, uint32_t& off)
{
    SWC_ASSERT(st != nullptr);
    SWC_ASSERT(ref != INVALID_REF);
    PagedStore::decodeRef(st->pageSize(), ref, pageIndex, off);
    SWC_ASSERT(pageIndex < st->publishedPageCount());
    SWC_ASSERT(off < st->pageSize());
}

uint32_t PagedStore::SpanView::dataOffsetFromHdr(uint32_t hdrOffset, uint32_t elemAlign)
{
    constexpr uint32_t hdrSize = sizeof(SpanHdrRaw);
    return Math::alignUpU32(hdrOffset + hdrSize, elemAlign);
}

const void* PagedStore::SpanView::dataPtr(const PagedStore* st, Ref hdrRef, uint32_t elemAlign)
{
    uint32_t pageIndex, off;
    decodeRef(st, hdrRef, pageIndex, off);
    const uint32_t dataOffset = dataOffsetFromHdr(off, elemAlign);
    SWC_ASSERT(dataOffset <= st->pageSize());
    SWC_ASSERT(dataOffset <= st->publishedPageUsed(pageIndex));
    return st->publishedPageBytes(pageIndex) + dataOffset;
}

uint32_t PagedStore::SpanView::totalElems(const PagedStore* st, Ref hdrRef)
{
    return st->ptr<SpanHdrRaw>(hdrRef)->total;
}

uint32_t PagedStore::SpanView::chunkCountFromLayout(const PagedStore* st, Ref hdrRef, uint32_t remaining, uint32_t elemSize, uint32_t elemAlign)
{
    SWC_ASSERT(st != nullptr);
    SWC_ASSERT(hdrRef != INVALID_REF);
    SWC_ASSERT(elemSize > 0);
    SWC_ASSERT((elemAlign & (elemAlign - 1)) == 0);
    SWC_ASSERT(elemAlign != 0);
    uint32_t pageIndex, off;
    decodeRef(st, hdrRef, pageIndex, off);
    const uint32_t dataOffset = dataOffsetFromHdr(off, elemAlign);
    SWC_ASSERT(dataOffset <= st->pageSize());
    const uint32_t capBytes = st->pageSize() - dataOffset;
    const uint32_t cap      = capBytes / elemSize;
    return std::min<uint32_t>(cap, remaining);
}

PagedStore::SpanView::SpanView(const PagedStore* s, Ref head, uint32_t elemSize, uint32_t elemAlign) :
    store_(s),
    head_(head),
    elementSize_(elemSize),
    elementAlign_(elemAlign)
{
}

uint32_t PagedStore::SpanView::size() const
{
    if (!store_ || head_ == std::numeric_limits<Ref>::max())
        return 0;
    return totalElems(store_, head_);
}

bool PagedStore::SpanView::ChunkIterator::operator!=(const ChunkIterator& o) const
{
    return hdrRef != o.hdrRef;
}

PagedStore::SpanView::ChunkIterator& PagedStore::SpanView::ChunkIterator::operator++()
{
    SWC_ASSERT(store != nullptr);
    SWC_ASSERT(hdrRef != INVALID_REF);
    done += current.count;
    if (done >= total)
    {
        hdrRef  = std::numeric_limits<Ref>::max();
        current = {.ptr = nullptr, .count = 0};
        return *this;
    }

    uint32_t  pageIndex, off;
    const Ref cur = hdrRef;
    decodeRef(store, cur, pageIndex, off);
    SWC_ASSERT(pageIndex + 1 < store->publishedPageCount());
    const Ref nextHdr = makeRef(store->pageSize(), pageIndex + 1, 0);

    hdrRef                   = nextHdr;
    const uint32_t remaining = total - done;
    const uint32_t cnt       = chunkCountFromLayout(store, hdrRef, remaining, elemSize, elemAlign);
    const void*    p         = dataPtr(store, hdrRef, elemAlign);
    current                  = {.ptr = p, .count = cnt};
    return *this;
}

PagedStore::SpanView::ChunkIterator PagedStore::SpanView::chunksBegin() const
{
    ChunkIterator it;
    it.store     = store_;
    it.hdrRef    = head_;
    it.total     = size();
    it.done      = 0;
    it.elemSize  = elementSize_;
    it.elemAlign = elementAlign_;

    if (it.total == 0)
    {
        it.hdrRef  = std::numeric_limits<Ref>::max();
        it.current = {.ptr = nullptr, .count = 0};
        return it;
    }

    const uint32_t cnt = chunkCountFromLayout(store_, head_, it.total, elementSize_, elementAlign_);
    const void*    p   = dataPtr(store_, head_, elementAlign_);
    it.current         = {.ptr = p, .count = cnt};
    return it;
}

PagedStore::SpanView::ChunkIterator PagedStore::SpanView::chunksEnd() const
{
    return {.store     = store_,
            .hdrRef    = std::numeric_limits<Ref>::max(),
            .total     = 0,
            .done      = 0,
            .elemSize  = elementSize_,
            .elemAlign = elementAlign_,
            .current   = {.ptr = nullptr, .count = 0}};
}

PagedStore::SpanView PagedStore::spanView(Ref ref, uint32_t elemSize, uint32_t elemAlign) const
{
    return {this, ref, elemSize, elemAlign};
}

std::byte* PagedStore::Page::allocateAligned(uint32_t size)
{
    return static_cast<std::byte*>(operator new(size, static_cast<std::align_val_t>(alignof(std::max_align_t))));
}

void PagedStore::Page::deallocateAligned(std::byte* p) noexcept
{
    operator delete(p, static_cast<std::align_val_t>(alignof(std::max_align_t)));
}

PagedStore::Page::Page(uint32_t pageSize) :
    storage(allocateAligned(pageSize))
{
}

PagedStore::Page::~Page()
{
    deallocateAligned(storage);
}

PagedStore::Page* PagedStore::newPage()
{
    pagesStorage_.emplace_back(std::make_unique<Page>(pageSizeValue_));
    curPage_      = pagesStorage_.back().get();
    curPageIndex_ = static_cast<uint32_t>(pagesStorage_.size() - 1);
    publishPages();
    return curPage_;
}

Ref PagedStore::findRef(const void* ptr) const noexcept
{
    const auto bPtr  = static_cast<const uint8_t*>(ptr);
    const auto pages = snapshotPages();
    for (uint32_t j = 0; j < pages->size(); j++)
    {
        const Page* page = (*pages)[j];
        if (bPtr >= page->bytes() && bPtr < page->bytes() + pageSizeValue_)
        {
            const uint32_t offset = static_cast<uint32_t>(bPtr - page->bytes());
            return makeRef(pageSizeValue_, j, offset);
        }
    }

    return std::numeric_limits<Ref>::max();
}

Ref PagedStore::makeRef(uint32_t pageSize, uint32_t pageIndex, uint32_t offset) noexcept
{
    const uint64_t r = static_cast<uint64_t>(pageIndex) * static_cast<uint64_t>(pageSize) + offset;
    SWC_ASSERT(r < std::numeric_limits<Ref>::max());
    return static_cast<Ref>(r);
}

void PagedStore::decodeRef(uint32_t pageSize, Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept
{
    pageIndex = ref / pageSize;
    offset    = ref % pageSize;
}

std::pair<Ref, void*> PagedStore::allocate(uint32_t size, uint32_t align)
{
    SWC_ASSERT(size <= pageSizeValue_ && (align & (align - 1)) == 0 && align <= alignof(std::max_align_t));

    Page*    page   = curPage_ ? curPage_ : newPage();
    uint32_t offset = (page->used.load(std::memory_order_relaxed) + (align - 1)) & ~(align - 1);
    if (offset + size > pageSizeValue_)
    {
        page   = newPage();
        offset = 0;
    }

    page->used.store(offset + size, std::memory_order_relaxed);
    totalBytes_ += size;

    const Ref r = makeRef(pageSizeValue_, curPageIndex_, offset);
    return {r, static_cast<void*>(page->bytes() + offset)};
}

std::shared_ptr<const std::vector<PagedStore::Page*>> PagedStore::snapshotPages() const noexcept
{
    return publishedPages_.load(std::memory_order_acquire);
}

void PagedStore::publishPages()
{
    std::vector<Page*> pages;
    pages.reserve(pagesStorage_.size());
    for (const std::unique_ptr<Page>& page : pagesStorage_)
        pages.push_back(page.get());
    publishedPages_.store(std::make_shared<const std::vector<Page*>>(std::move(pages)), std::memory_order_release);
}

uint32_t PagedStore::publishedPageCount() const noexcept
{
    return static_cast<uint32_t>(snapshotPages()->size());
}

uint32_t PagedStore::publishedPageUsed(uint32_t index) const noexcept
{
    const auto pages = snapshotPages();
    SWC_ASSERT(index < pages->size());
    return (*pages)[index]->used.load(std::memory_order_relaxed);
}

const uint8_t* PagedStore::publishedPageBytes(uint32_t index) const noexcept
{
    const auto pages = snapshotPages();
    SWC_ASSERT(index < pages->size());
    return (*pages)[index]->bytes();
}

uint8_t* PagedStore::publishedPageBytesMutable(uint32_t index) const noexcept
{
    const auto pages = snapshotPages();
    SWC_ASSERT(index < pages->size());
    return (*pages)[index]->bytes();
}

SWC_END_NAMESPACE();

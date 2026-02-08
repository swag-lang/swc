#include "pch.h"
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

Store::Store(uint32_t pageSize) :
    pageSizeValue_(pageSize)
{
    SWC_ASSERT(pageSizeValue_ > 0 && (pageSizeValue_ & (pageSizeValue_ - 1)) == 0);
}

Store::Store(Store&& other) noexcept :
    pagesStorage_(std::move(other.pagesStorage_)),
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
}

Store& Store::operator=(Store&& other) noexcept
{
    if (this != &other)
    {
        std::swap(pagesStorage_, other.pagesStorage_);
        std::swap(totalBytes_, other.totalBytes_);
        std::swap(pageSizeValue_, other.pageSizeValue_);
        std::swap(curPage_, other.curPage_);
        std::swap(curPageIndex_, other.curPageIndex_);
        std::swap(lastPtr_, other.lastPtr_);
    }
    return *this;
}

void Store::clear() noexcept
{
    for (const auto& up : pagesStorage_)
        up->used = 0;
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

uint32_t Store::size() const noexcept
{
    return static_cast<uint32_t>(std::min<uint64_t>(totalBytes_, std::numeric_limits<uint32_t>::max()));
}

std::pair<SpanRef, uint32_t> Store::writeChunkRaw(const uint8_t* src, uint32_t elemSize, uint32_t elemAlign, uint32_t remaining, uint32_t totalElems)
{
    SWC_ASSERT(elemSize > 0);
    SWC_ASSERT((elemAlign & (elemAlign - 1)) == 0 && elemAlign <= alignof(std::max_align_t));

    Page* page = curPage_ ? curPage_ : newPage();

    uint32_t       off        = page->used;
    const uint32_t bytesAvail = pageSizeValue_ - off;

    constexpr uint32_t hdrSize    = sizeof(SpanHdrRaw);
    const uint32_t     dataOffset = alignUpU32(off + hdrSize, elemAlign);
    const uint32_t     padBytes   = dataOffset - (off + hdrSize);

    if (hdrSize + padBytes + elemSize > bytesAvail)
    {
        page = newPage();
        off  = 0;
    }

    const uint32_t dataOffsetF = alignUpU32(off + hdrSize, elemAlign);
    const uint32_t maxData     = pageSizeValue_ - dataOffsetF;
    const uint32_t cap         = maxData / elemSize;
    const uint32_t fit         = std::min<uint32_t>(remaining, cap);
    SWC_ASSERT(fit > 0);

    const SpanRef  hdrRef{makeRef(pageSizeValue_, curPageIndex_, off)};
    const uint32_t newUsed = dataOffsetF + fit * elemSize;
    SWC_ASSERT(newUsed <= pageSizeValue_);
    page->used = newUsed;
    totalBytes_ += hdrSize + (dataOffsetF - (off + hdrSize)) + fit * elemSize;

    auto* hdr  = reinterpret_cast<SpanHdrRaw*>(page->bytes() + off);
    hdr->total = totalElems;

    std::memcpy(page->bytes() + dataOffsetF, src, static_cast<size_t>(fit) * elemSize);

    return {hdrRef, fit};
}

SpanRef Store::pushSpanRaw(const void* data, uint32_t elemSize, uint32_t elemAlign, uint32_t count)
{
    if (count == 0)
    {
        Page*              page = curPage_ ? curPage_ : newPage();
        constexpr uint32_t need = sizeof(SpanHdrRaw);
        if (page->used + need > pageSizeValue_)
            page = newPage();
        const SpanRef hdrRef{makeRef(pageSizeValue_, curPageIndex_, page->used)};
        auto*         hdr = reinterpret_cast<SpanHdrRaw*>(page->bytes() + page->used);
        hdr->total        = 0;
        page->used += need;
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

void Store::SpanView::decodeRef(const Store* st, Ref ref, uint32_t& pageIndex, uint32_t& off)
{
    Store::decodeRef(st->pageSize(), ref, pageIndex, off);
}

uint32_t Store::SpanView::dataOffsetFromHdr(uint32_t hdrOffset, uint32_t elemAlign)
{
    constexpr uint32_t hdrSize = sizeof(SpanHdrRaw);
    return alignUpU32(hdrOffset + hdrSize, elemAlign);
}

const void* Store::SpanView::dataPtr(const Store* st, Ref hdrRef, uint32_t elemAlign)
{
    uint32_t pageIndex, off;
    decodeRef(st, hdrRef, pageIndex, off);
    const uint32_t dataOffset = dataOffsetFromHdr(off, elemAlign);
    return st->pagesStorage_[pageIndex]->bytes() + dataOffset;
}

uint32_t Store::SpanView::totalElems(const Store* st, Ref hdrRef)
{
    return st->ptr<SpanHdrRaw>(hdrRef)->total;
}

uint32_t Store::SpanView::chunkCountFromLayout(const Store* st, Ref hdrRef, uint32_t remaining, uint32_t elemSize, uint32_t elemAlign)
{
    uint32_t pageIndex, off;
    decodeRef(st, hdrRef, pageIndex, off);
    const uint32_t dataOffset = dataOffsetFromHdr(off, elemAlign);
    const uint32_t capBytes   = st->pageSize() - dataOffset;
    const uint32_t cap        = capBytes / elemSize;
    return std::min<uint32_t>(cap, remaining);
}

Store::SpanView::SpanView(const Store* s, Ref r, uint32_t elemSize, uint32_t elemAlign) :
    store_(s),
    head_(r),
    elementSize_(elemSize),
    elementAlign_(elemAlign)
{
}

uint32_t Store::SpanView::size() const
{
    if (!store_ || head_ == std::numeric_limits<Ref>::max())
        return 0;
    return totalElems(store_, head_);
}

bool Store::SpanView::ChunkIterator::operator!=(const ChunkIterator& o) const
{
    return hdrRef != o.hdrRef;
}

Store::SpanView::ChunkIterator& Store::SpanView::ChunkIterator::operator++()
{
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
    const Ref nextHdr = makeRef(store->pageSize(), pageIndex + 1, 0);

    hdrRef                   = nextHdr;
    const uint32_t remaining = total - done;
    const uint32_t cnt       = chunkCountFromLayout(store, hdrRef, remaining, elemSize, elemAlign);
    const void*    p         = dataPtr(store, hdrRef, elemAlign);
    current                  = {.ptr = p, .count = cnt};
    return *this;
}

Store::SpanView::ChunkIterator Store::SpanView::chunksBegin() const
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

Store::SpanView::ChunkIterator Store::SpanView::chunksEnd() const
{
    return {.store     = store_,
            .hdrRef    = std::numeric_limits<Ref>::max(),
            .total     = 0,
            .done      = 0,
            .elemSize  = elementSize_,
            .elemAlign = elementAlign_,
            .current   = {.ptr = nullptr, .count = 0}};
}

Store::SpanView Store::spanView(Ref ref, uint32_t elemSize, uint32_t elemAlign) const
{
    return {this, ref, elemSize, elemAlign};
}

std::byte* Store::Page::allocateAligned(uint32_t size)
{
    return static_cast<std::byte*>(operator new(size, static_cast<std::align_val_t>(alignof(std::max_align_t))));
}

void Store::Page::deallocateAligned(std::byte* p) noexcept
{
    operator delete(p, static_cast<std::align_val_t>(alignof(std::max_align_t)));
}

Store::Page::Page(uint32_t pageSize) :
    storage(allocateAligned(pageSize))
{
}

Store::Page::~Page()
{
    deallocateAligned(storage);
}

Store::Page* Store::newPage()
{
    pagesStorage_.emplace_back(std::make_unique<Page>(pageSizeValue_));
    curPage_      = pagesStorage_.back().get();
    curPageIndex_ = static_cast<uint32_t>(pagesStorage_.size() - 1);
    return curPage_;
}

Ref Store::findRef(const void* ptr) const noexcept
{
    const auto bPtr = static_cast<const uint8_t*>(ptr);
    for (uint32_t j = 0; j < pagesStorage_.size(); j++)
    {
        const auto& page = pagesStorage_[j];
        if (bPtr >= page->bytes() && bPtr < page->bytes() + pageSizeValue_)
        {
            const auto offset = static_cast<uint32_t>(bPtr - page->bytes());
            return makeRef(pageSizeValue_, j, offset);
        }
    }

    return std::numeric_limits<Ref>::max();
}

Ref Store::makeRef(uint32_t pageSize, uint32_t pageIndex, uint32_t offset) noexcept
{
    const uint64_t r = static_cast<uint64_t>(pageIndex) * static_cast<uint64_t>(pageSize) + offset;
    SWC_ASSERT(r < std::numeric_limits<Ref>::max());
    return static_cast<Ref>(r);
}

void Store::decodeRef(uint32_t pageSize, Ref ref, uint32_t& pageIndex, uint32_t& offset) noexcept
{
    pageIndex = ref / pageSize;
    offset    = ref % pageSize;
}

std::pair<Ref, void*> Store::allocate(uint32_t size, uint32_t align)
{
    SWC_ASSERT(size <= pageSizeValue_ && (align & (align - 1)) == 0 && align <= alignof(std::max_align_t));

    Page*    page   = curPage_ ? curPage_ : newPage();
    uint32_t offset = (page->used + (align - 1)) & ~(align - 1);
    if (offset + size > pageSizeValue_)
    {
        page   = newPage();
        offset = 0;
    }

    page->used = offset + size;
    totalBytes_ += size;

    const Ref r = makeRef(pageSizeValue_, curPageIndex_, offset);
    return {r, static_cast<void*>(page->bytes() + offset)};
}

SWC_END_NAMESPACE();

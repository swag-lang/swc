// ReSharper disable CppInconsistentNaming
#include "pch.h"
#include "Core/Store.h"

SWC_BEGIN_NAMESPACE()

Store::Store(uint32_t pageSize) :
    pageSize_(pageSize)
{
    SWC_ASSERT(pageSize_ > 0 && (pageSize_ & (pageSize_ - 1)) == 0);
}

Store::Store(Store&& other) noexcept :
    pages_(std::move(other.pages_)),
    totalBytes_(other.totalBytes_),
    pageSize_(other.pageSize_),
    cur_(other.cur_),
    curIndex_(other.curIndex_)
{
    other.totalBytes_ = 0;
    other.cur_        = nullptr;
    other.curIndex_   = 0;
}

Store& Store::operator=(Store&& other) noexcept
{
    if (this != &other)
    {
        std::swap(pages_, other.pages_);
        std::swap(totalBytes_, other.totalBytes_);
        std::swap(pageSize_, other.pageSize_);
        std::swap(cur_, other.cur_);
        std::swap(curIndex_, other.curIndex_);
    }
    return *this;
}

Store::Page* Store::newPage()
{
    pages_.emplace_back(std::make_unique<Page>(pageSize_));
    cur_      = pages_.back().get();
    curIndex_ = static_cast<uint32_t>(pages_.size() - 1);
    return cur_;
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
    SWC_ASSERT(size <= pageSize_ && (align & (align - 1)) == 0 && align <= alignof(std::max_align_t));

    Page* page = cur_ ? cur_ : newPage();

    uint32_t offset = (page->used + (align - 1)) & ~(align - 1);

    if (offset + size > pageSize_)
    {
        page   = newPage();
        offset = 0;
    }

    page->used = offset + size;
    totalBytes_ += size;

    const Ref r = makeRef(pageSize_, curIndex_, offset);
    return {r, static_cast<void*>(page->bytes() + offset)};
}

void Store::clear() noexcept
{
    for (const auto& up : pages_)
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

uint32_t Store::size() const noexcept
{
    return static_cast<uint32_t>(std::min<uint64_t>(totalBytes_, std::numeric_limits<uint32_t>::max()));
}

std::pair<SpanRef, uint32_t> Store::write_chunk_raw(const uint8_t* src, uint32_t elemSize, uint32_t elemAlign, uint32_t remaining, uint32_t totalElems)
{
    SWC_ASSERT(elemSize > 0);
    SWC_ASSERT((elemAlign & (elemAlign - 1)) == 0 && elemAlign <= alignof(std::max_align_t));

    Page* page = cur_ ? cur_ : newPage();

    uint32_t       off        = page->used; // header has no special alignment
    const uint32_t bytesAvail = pageSize_ - off;

    constexpr uint32_t hdrSize    = sizeof(SpanHdrRaw);
    const uint32_t     dataOffset = align_up_u32(off + hdrSize, elemAlign);
    const uint32_t     padBytes   = dataOffset - (off + hdrSize);

    if (hdrSize + padBytes + elemSize > bytesAvail)
    {
        page = newPage();
        off  = 0;
    }

    const uint32_t dataOffsetF = align_up_u32(off + hdrSize, elemAlign);
    const uint32_t maxData     = pageSize_ - dataOffsetF;
    const uint32_t cap         = maxData / elemSize;
    const uint32_t fit         = std::min<uint32_t>(remaining, cap);
    SWC_ASSERT(fit > 0);

    const SpanRef  hdrRef{makeRef(pageSize_, curIndex_, off)};
    const uint32_t newUsed = dataOffsetF + fit * elemSize;
    SWC_ASSERT(newUsed <= pageSize_);
    page->used = newUsed;
    totalBytes_ += hdrSize + (dataOffsetF - (off + hdrSize)) + fit * elemSize;

    auto* hdr  = reinterpret_cast<SpanHdrRaw*>(page->bytes() + off);
    hdr->total = totalElems;

    std::memcpy(page->bytes() + dataOffsetF, src, static_cast<size_t>(fit) * elemSize);

    return {hdrRef, fit};
}

SpanRef Store::push_span_raw(const void* data, uint32_t elemSize, uint32_t elemAlign, uint32_t count)
{
    if (count == 0)
    {
        Page*              page = cur_ ? cur_ : newPage();
        constexpr uint32_t need = sizeof(SpanHdrRaw);
        if (page->used + need > pageSize_)
            page = newPage();
        const SpanRef hdrRef{makeRef(pageSize_, curIndex_, page->used)};
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
        auto [hdrRef, wrote] = write_chunk_raw(src, elemSize, elemAlign, remaining, totalElems);

        if (firstRef.isInvalid())
            firstRef = hdrRef;

        src += static_cast<size_t>(wrote) * elemSize;
        remaining -= wrote;
    }

    return firstRef;
}

std::byte* Store::Page::allocate_aligned(uint32_t size)
{
    return static_cast<std::byte*>(operator new(size, static_cast<std::align_val_t>(alignof(std::max_align_t))));
}

void Store::Page::deallocate_aligned(std::byte* p) noexcept
{
    operator delete(p, static_cast<std::align_val_t>(alignof(std::max_align_t)));
}

Store::Page::Page(uint32_t pageSize) :
    storage_(allocate_aligned(pageSize))
{
}

Store::Page::~Page()
{
    deallocate_aligned(storage_);
}

void Store::SpanView::decode_ref(const Store* st, Ref ref, uint32_t& pageIndex, uint32_t& off)
{
    decodeRef(st->pageSize(), ref, pageIndex, off);
}

uint32_t Store::SpanView::data_offset_from_hdr(uint32_t hdrOffset, uint32_t elemAlign)
{
    constexpr uint32_t hdrSize = sizeof(SpanHdrRaw);
    return align_up_u32(hdrOffset + hdrSize, elemAlign);
}

const void* Store::SpanView::data_ptr(const Store* st, Ref hdrRef, uint32_t elemAlign)
{
    uint32_t pageIndex, off;
    decode_ref(st, hdrRef, pageIndex, off);
    const uint32_t dataOffset = data_offset_from_hdr(off, elemAlign);
    return st->pages_[pageIndex]->bytes() + dataOffset;
}

uint32_t Store::SpanView::total_elems(const Store* st, Ref hdrRef)
{
    return st->ptr<SpanHdrRaw>(hdrRef)->total;
}

uint32_t Store::SpanView::chunk_count_from_layout(const Store* st, Ref hdrRef, uint32_t remaining, uint32_t elemSize, uint32_t elemAlign)
{
    uint32_t pageIndex, off;
    decode_ref(st, hdrRef, pageIndex, off);
    const uint32_t dataOffset = data_offset_from_hdr(off, elemAlign);
    const uint32_t capBytes   = st->pageSize() - dataOffset;
    const uint32_t cap        = capBytes / elemSize;
    return std::min<uint32_t>(cap, remaining);
}

Store::SpanView::SpanView(const Store* s, Ref r, uint32_t elemSize, uint32_t elemAlign) :
    store_(s),
    head_(r),
    elemSize_(elemSize),
    elemAlign_(elemAlign)
{
}

uint32_t Store::SpanView::size() const
{
    if (!store_ || head_ == std::numeric_limits<Ref>::max())
        return 0;
    return total_elems(store_, head_);
}

bool Store::SpanView::chunk_iterator::operator!=(const chunk_iterator& o) const
{
    return hdrRef != o.hdrRef;
}

Store::SpanView::chunk_iterator& Store::SpanView::chunk_iterator::operator++()
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
    decode_ref(store, cur, pageIndex, off);
    const Ref nextHdr = makeRef(store->pageSize(), pageIndex + 1, 0);

    hdrRef                   = nextHdr;
    const uint32_t remaining = total - done;
    const uint32_t cnt       = chunk_count_from_layout(store, hdrRef, remaining, elemSize, elemAlign);
    const void*    p         = data_ptr(store, hdrRef, elemAlign);
    current                  = {.ptr = p, .count = cnt};
    return *this;
}

Store::SpanView::chunk_iterator Store::SpanView::chunks_begin() const
{
    chunk_iterator it;
    it.store     = store_;
    it.hdrRef    = head_;
    it.total     = size();
    it.done      = 0;
    it.elemSize  = elemSize_;
    it.elemAlign = elemAlign_;

    if (it.total == 0)
    {
        it.hdrRef  = std::numeric_limits<Ref>::max();
        it.current = {.ptr = nullptr, .count = 0};
        return it;
    }

    const uint32_t cnt = chunk_count_from_layout(store_, head_, it.total, elemSize_, elemAlign_);
    const void*    p   = data_ptr(store_, head_, elemAlign_);
    it.current         = {.ptr = p, .count = cnt};
    return it;
}

Store::SpanView::chunk_iterator Store::SpanView::chunks_end() const
{
    return {.store     = store_,
            .hdrRef    = std::numeric_limits<Ref>::max(),
            .total     = 0,
            .done      = 0,
            .elemSize  = elemSize_,
            .elemAlign = elemAlign_,
            .current   = {.ptr = nullptr, .count = 0}};
}

Store::SpanView Store::span_view(Ref ref, uint32_t elemSize, uint32_t elemAlign) const
{
    return {this, ref, elemSize, elemAlign};
}

SWC_END_NAMESPACE()

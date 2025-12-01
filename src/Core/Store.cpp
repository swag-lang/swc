#include "pch.h"
#include "Core/Store.h"

SWC_BEGIN_NAMESPACE()

// === Store::Page ==========================================================

std::byte* Store::Page::allocate_aligned(uint32_t size)
{
#if defined(__cpp_aligned_new) && __cpp_aligned_new >= 201606
    return static_cast<std::byte*>(
        ::operator new(size, std::align_val_t(alignof(std::max_align_t))));
#else
    void* p = nullptr;
#if defined(_MSC_VER)
    p = _aligned_malloc(size, alignof(std::max_align_t));
    if (!p)
        throw std::bad_alloc();
    return static_cast<std::byte*>(p);
#else
    if (posix_memalign(&p, alignof(std::max_align_t), size) != 0)
        throw std::bad_alloc();
    return static_cast<std::byte*>(p);
#endif
#endif
}

void Store::Page::deallocate_aligned(std::byte* p) noexcept
{
    if (!p)
        return;

#if defined(__cpp_aligned_new) && __cpp_aligned_new >= 201606
    ::operator delete(p, std::align_val_t(alignof(std::max_align_t)));
#elif defined(_MSC_VER)
    _aligned_free(p);
#else
    std::free(p);
#endif
}

Store::Page::Page(uint32_t pageSize) :
    storage_(allocate_aligned(pageSize)),
    used(0)
{
}

Store::Page::~Page()
{
    deallocate_aligned(storage_);
}

// === Store non-template members ===========================================

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
    const uint64_t r =
        static_cast<uint64_t>(pageIndex) * static_cast<uint64_t>(pageSize) + offset;
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
    SWC_ASSERT(size <= pageSize_ &&
               (align & (align - 1)) == 0 &&
               align <= alignof(std::max_align_t));

    Page* page = cur_ ? cur_ : newPage();

    // Align the current position (page start is already max-aligned)
    uint32_t offset = (page->used + (align - 1)) & ~(align - 1);

    // New page if not enough space
    if (offset + size > pageSize_)
    {
        page   = newPage();
        offset = 0; // page start is max-aligned -> OK for all T
    }

    page->used = offset + size;
    totalBytes_ += size;

    const Ref r = makeRef(pageSize_, curIndex_, offset);
    return {r, static_cast<void*>(page->bytes() + offset)};
}

void Store::clear() noexcept
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

uint32_t Store::size() const noexcept
{
    return static_cast<uint32_t>(
        std::min<uint64_t>(totalBytes_, std::numeric_limits<uint32_t>::max()));
}

SWC_END_NAMESPACE()

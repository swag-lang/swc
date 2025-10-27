// ReSharper disable CppInconsistentNaming
#pragma once
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
        auto [r, p] = allocate(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
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

public:
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
};

SWC_END_NAMESPACE();

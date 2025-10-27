// ReSharper disable CppInconsistentNaming
#pragma once
SWC_BEGIN_NAMESPACE();

using Ref = uint32_t;

// Simple page-based POD store.
// Each page holds up to N bytes of raw data.
// Items are packed sequentially; alignment preserved relative to a max-aligned base.
// Ref is a 32-bit index in BYTES from the start of the store.
template<uint32_t N = 16 * 1024>
class RefStore
{
    static_assert(N > 0 && (N & (N - 1)) == 0, "N must be a power of two");

    struct Page
    {
        using Storage = std::aligned_storage_t<N, alignof(std::max_align_t)>;
        Storage  storage;
        uint32_t used = 0;

        uint8_t*       bytes() noexcept { return reinterpret_cast<uint8_t*>(&storage); }
        const uint8_t* bytes() const noexcept { return reinterpret_cast<const uint8_t*>(&storage); }
    };

    std::vector<Page*> pages_;
    uint32_t           totalBytes_ = 0; // total bytes of payload stored

    Page* newPage()
    {
        Page* p = new Page();
        p->used = 0;
        pages_.push_back(p);
        return p;
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

public:
    RefStore() = default;

    // Non-copyable (owning raw pointers)
    RefStore(const RefStore&)            = delete;
    RefStore& operator=(const RefStore&) = delete;

    // Movable
    RefStore(RefStore&& other) noexcept :
        pages_(std::move(other.pages_)),
        totalBytes_(other.totalBytes_)
    {
        other.pages_.clear();
        other.totalBytes_ = 0;
    }

    RefStore& operator=(RefStore&& other) noexcept
    {
        if (this != &other)
        {
            this->~RefStore();
            pages_      = std::move(other.pages_);
            totalBytes_ = other.totalBytes_;
            other.pages_.clear();
            other.totalBytes_ = 0;
        }
        
        return *this;
    }

    ~RefStore()
    {
        for (auto* p : pages_)
            delete p;
    }

    void clear() noexcept
    {
        for (auto* p : pages_)
            p->used = 0;
        totalBytes_ = 0;
    }

    uint32_t size() const noexcept { return totalBytes_; } // payload bytes

    // Emplace a POD (construct in-place)
    template<class T>
    Ref push_back(const T& v)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");

        const uint32_t align = alignof(T);
        const uint32_t size  = sizeof(T);

        Page* page = pages_.empty() ? newPage() : pages_.back();

        // align current position (base is max-aligned)
        uint32_t offset = (page->used + (align - 1)) & ~(align - 1);

        // new page if not enough space
        if (offset + size > N)
        {
            page   = newPage();
            offset = 0;
        }

        std::memcpy(page->bytes() + offset, &v, size);

        page->used = offset + size;
        totalBytes_ += size;

        const uint32_t pageIndex = static_cast<uint32_t>(pages_.size() - 1);
        return makeRef(pageIndex, offset); // True byte index
    }

    template<class T>
    T* ptr(Ref ref)
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        uint32_t pageIndex, offset;
        decodeRef(ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages_.size());
        SWC_ASSERT(offset + sizeof(T) <= N);
        return reinterpret_cast<T*>(pages_[pageIndex]->bytes() + offset);
    }

    template<class T>
    const T* ptr(Ref ref) const
    {
        static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
        uint32_t pageIndex, offset;
        decodeRef(ref, pageIndex, offset);
        SWC_ASSERT(pageIndex < pages_.size());
        SWC_ASSERT(offset + sizeof(T) <= N);
        return reinterpret_cast<const T*>(pages_[pageIndex]->bytes() + offset);
    }

    template<class T>
    T& at(Ref ref)
    {
        return *ptr<T>(ref);
    }

    template<class T>
    const T& at(Ref ref) const
    {
        return *ptr<T>(ref);
    }
};

SWC_END_NAMESPACE();

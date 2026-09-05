#pragma once
SWC_BEGIN_NAMESPACE();

class Arena
{
public:
    // Header and payload together fill one 64 KiB allocator bin. A 4 KiB payload plus its
    // header rounded up to the 5 KiB bin and wasted a fifth of every block, and a block that
    // small held a single 2 KiB function symbol before its tail went unused.
    static constexpr std::size_t K_DEFAULT_BLOCK_SIZE = 64 * 1024 - 64;

    explicit Arena(std::size_t blockSize = K_DEFAULT_BLOCK_SIZE) noexcept :
        head_(nullptr),
        defaultBlockSize_(blockSize)
    {
    }

    Arena(const Arena&)            = delete;
    Arena& operator=(const Arena&) = delete;
    Arena(Arena&& other) noexcept;
    Arena& operator=(Arena&& other) noexcept;
    ~Arena();

    void* allocate(std::size_t size, std::size_t alignment = alignof(std::max_align_t));

    template<typename T, typename... ARGS>
    T* make(ARGS&&... args)
    {
        void* mem = allocate(sizeof(T), alignof(T));
        return new (mem) T(std::forward<ARGS>(args)...);
    }

    template<typename T>
    static void destroy(T* ptr)
    {
        if (ptr)
            ptr->~T();
    }

    void reset()
    {
        releaseAll();
        head_ = nullptr;
    }

private:
    struct Block
    {
        std::size_t   size;
        std::size_t   used;
        std::uint8_t* data;
        Block*        next;
    };

    Block*      head_;
    std::size_t defaultBlockSize_;

    static bool canAllocateFrom(const Block* block, std::size_t size, std::size_t alignment) noexcept;
    Block*      addBlock(std::size_t minSize);
    void        releaseAll();
};

SWC_END_NAMESPACE();

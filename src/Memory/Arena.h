#pragma once
SWC_BEGIN_NAMESPACE()

class Arena
{
public:
    explicit Arena(std::size_t blockSize = 4096) noexcept :
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

    Block* addBlock(std::size_t minSize);
    void   releaseAll();
};

SWC_END_NAMESPACE()

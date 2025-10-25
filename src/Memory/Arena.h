#pragma once
SWC_BEGIN_NAMESPACE();

class Arena
{
    struct Block
    {
        char*  ptr;
        size_t size;
        size_t used;

        explicit Block(size_t n) :
            ptr(static_cast<char*>(::operator new(n))),
            size(n),
            used(0)
        {
        }

        ~Block() { ::operator delete(ptr); }
    };

    std::vector<std::unique_ptr<Block>> blocks_;
    size_t                              blockSize_;

    static size_t alignUp(size_t x, size_t a)
    {
        return (x + a - 1) & ~(a - 1);
    }

    void addBlock(size_t need)
    {
        size_t n = std::max(need, blockSize_);
        blocks_.push_back(std::make_unique<Block>(n));
    }

public:
    explicit Arena(size_t blockSize = 32 * 1024) :
        blockSize_(blockSize)
    {
    }

    ~Arena()
    {
        reset();
    }

    void* allocate(size_t n, size_t align = alignof(std::max_align_t));
    void  shrinkToFit();

    template<class T>
    T* allocArray(size_t count)
    {
        return static_cast<T*>(allocate(sizeof(T) * count, alignof(T)));
    }

    void reset()
    {
        blocks_.clear(); // frees all blocks
    }

    size_t totalAllocated() const
    {
        size_t total = 0;
        for (const auto& b : blocks_)
            total += b->size;
        return total;
    }

    size_t totalUsed() const
    {
        size_t total = 0;
        for (const auto& b : blocks_)
            total += b->used;
        return total;
    }
};

SWC_END_NAMESPACE();

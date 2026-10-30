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
        void*      mem       = allocate(sizeof(T), alignof(T));
        Finalizer* finalizer = nullptr;
        if constexpr (!std::is_trivially_destructible_v<T>)
            finalizer = static_cast<Finalizer*>(allocate(sizeof(Finalizer), alignof(Finalizer)));

        T* value = new (mem) T(std::forward<ARGS>(args)...);
        if constexpr (!std::is_trivially_destructible_v<T>)
            own(finalizer, value, 1);
        return value;
    }

    template<typename T>
    T* makeArray(size_t count)
    {
        auto*      values    = static_cast<T*>(allocate(sizeof(T) * count, alignof(T)));
        Finalizer* finalizer = nullptr;
        if constexpr (!std::is_trivially_destructible_v<T>)
            finalizer = static_cast<Finalizer*>(allocate(sizeof(Finalizer), alignof(Finalizer)));

        if constexpr (!std::is_trivially_default_constructible_v<T>)
        {
            size_t constructed = 0;
            try
            {
                for (; constructed < count; ++constructed)
                    new (values + constructed) T();
            }
            catch (...)
            {
                destroyObjects<T>(values, constructed);
                throw;
            }
        }

        if constexpr (!std::is_trivially_destructible_v<T>)
            own(finalizer, values, count);
        return values;
    }

    void reset()
    {
        releaseAll();
        head_ = nullptr;
    }

private:
    // Releasing arena pages alone loses the heap storage owned by their vectors, maps and
    // shared pointers. Keep cleanup records in the arena too; trivial payloads need none.
    struct Finalizer
    {
        void*  values;
        size_t count;
        void (*destroy)(void*, size_t) noexcept;
        Finalizer* previous;
    };

    template<typename T>
    void own(Finalizer* finalizer, T* values, size_t count)
    {
        *finalizer  = {values, count, &destroyObjects<T>, finalizers_};
        finalizers_ = finalizer;
    }

    template<typename T>
    static void destroyObjects(void* ptr, size_t count) noexcept
    {
        auto* values = static_cast<T*>(ptr);
        while (count)
            std::destroy_at(values + --count);
    }

    struct Block
    {
        std::size_t   size;
        std::size_t   used;
        std::uint8_t* data;
        Block*        next;
    };

    Block*      head_;
    std::size_t defaultBlockSize_;
    Finalizer*  finalizers_ = nullptr;

    static bool canAllocateFrom(const Block* block, std::size_t size, std::size_t alignment) noexcept;
    Block*      addBlock(std::size_t minSize);
    void        releaseAll();
};

SWC_END_NAMESPACE();

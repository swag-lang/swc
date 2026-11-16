#include "pch.h"
#include "Support/Memory/Arena.h"

SWC_BEGIN_NAMESPACE();

Arena::Arena(Arena&& other) noexcept :
    head_(other.head_),
    defaultBlockSize_(other.defaultBlockSize_),
    finalizers_(other.finalizers_)
{
    other.head_       = nullptr;
    other.finalizers_ = nullptr;
}

Arena& Arena::operator=(Arena&& other) noexcept
{
    if (this != &other)
    {
        releaseAll();
        head_             = other.head_;
        defaultBlockSize_ = other.defaultBlockSize_;
        finalizers_       = other.finalizers_;
        other.head_       = nullptr;
        other.finalizers_ = nullptr;
    }
    return *this;
}

Arena::~Arena()
{
    releaseAll();
}

void* Arena::allocate(std::size_t size, std::size_t alignment)
{
    // Zero-size allocation is undefined; normalize to 1.
    if (size == 0)
        size = 1;
    if (alignment == 0 || size > std::numeric_limits<std::size_t>::max() - alignment)
        throw std::bad_alloc();

    Block* block = head_;
    if (!block || !canAllocateFrom(block, size, alignment))
    {
        block = addBlock(size + alignment);
    }

    if (!canAllocateFrom(block, size, alignment))
        throw std::bad_alloc();

    auto        raw          = reinterpret_cast<std::uintptr_t>(block->data + block->used);
    std::size_t misalignment = raw % alignment;
    std::size_t padding      = misalignment ? (alignment - misalignment) : 0;

    if (block->used + padding + size > block->size)
    {
        // Shouldn’t happen because we requested enough when creating block,
        // but handle defensively.
        block        = addBlock(size + alignment);
        raw          = reinterpret_cast<std::uintptr_t>(block->data + block->used);
        misalignment = raw % alignment;
        padding      = misalignment ? (alignment - misalignment) : 0;
    }

    block->used += padding;
    void* ptr = block->data + block->used;
    block->used += size;
    return ptr;
}

bool Arena::canAllocateFrom(const Block* block, std::size_t size, std::size_t alignment) noexcept
{
    if (!block || alignment == 0 || block->used > block->size)
        return false;

    const auto        raw          = reinterpret_cast<std::uintptr_t>(block->data + block->used);
    const std::size_t misalignment = raw % alignment;
    const std::size_t padding      = misalignment ? (alignment - misalignment) : 0;
    const std::size_t available    = block->size - block->used;
    return padding <= available && size <= available - padding;
}

Arena::Block* Arena::addBlock(std::size_t minSize)
{
    const std::size_t blockSize = minSize > defaultBlockSize_ ? minSize : defaultBlockSize_;

    // Allocate Block header + buffer in one go.
    constexpr std::size_t headerSize = sizeof(Block);
    if (blockSize > std::numeric_limits<std::size_t>::max() - headerSize)
        throw std::bad_alloc();
    const std::size_t totalSize = headerSize + blockSize;

    auto* raw   = static_cast<uint8_t*>(operator new(totalSize));
    auto* block = reinterpret_cast<Block*>(raw);

    block->size = blockSize;
    block->used = 0;
    block->data = raw + headerSize;
    block->next = head_;

    head_ = block;
    return block;
}

void Arena::releaseAll()
{
    while (finalizers_)
    {
        Finalizer* finalizer = finalizers_;
        finalizers_          = finalizer->previous;
        finalizer->destroy(finalizer->values, finalizer->count);
    }

    Block* block = head_;
    while (block)
    {
        Block* next = block->next;
        operator delete(block);
        block = next;
    }
    head_ = nullptr;
}
SWC_END_NAMESPACE();

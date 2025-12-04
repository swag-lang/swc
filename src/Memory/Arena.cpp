#include "pch.h"
#include "Memory/Arena.h"

SWC_BEGIN_NAMESPACE()

Arena::Arena(Arena&& other) noexcept :
    head_(other.head_),
    defaultBlockSize_(other.defaultBlockSize_)
{
    other.head_ = nullptr;
}

Arena& Arena::operator=(Arena&& other) noexcept
{
    if (this != &other)
    {
        releaseAll();
        head_             = other.head_;
        defaultBlockSize_ = other.defaultBlockSize_;
        other.head_       = nullptr;
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

    Block* block = head_;
    if (!block || !canAllocateFrom(block, size, alignment))
    {
        block = addBlock(size + alignment);
    }

    std::uintptr_t raw          = reinterpret_cast<std::uintptr_t>(block->data + block->used);
    std::size_t    misalignment = raw % alignment;
    std::size_t    padding      = misalignment ? (alignment - misalignment) : 0;

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
    if (!block)
        return false;

    std::uintptr_t raw          = reinterpret_cast<std::uintptr_t>(block->data + block->used);
    std::size_t    misalignment = raw % alignment;
    std::size_t    padding      = misalignment ? (alignment - misalignment) : 0;

    return (block->used + padding + size) <= block->size;
}

Arena::Block* Arena::addBlock(std::size_t minSize)
{
    const std::size_t blockSize =
        minSize > defaultBlockSize_ ? minSize : defaultBlockSize_;

    // Allocate Block header + buffer in one go.
    const std::size_t headerSize = sizeof(Block);
    std::size_t       totalSize  = headerSize + blockSize;

    auto* raw   = static_cast<std::uint8_t*>(::operator new(totalSize));
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
    Block* block = head_;
    while (block)
    {
        Block* next = block->next;
        ::operator delete(reinterpret_cast<void*>(block));
        block = next;
    }
    head_ = nullptr;
}
SWC_END_NAMESPACE()

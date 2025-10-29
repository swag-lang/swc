#include "pch.h"
#include "Memory/Arena.h"

SWC_BEGIN_NAMESPACE()

void* Arena::allocate(size_t n, size_t align)
{
    if (blocks_.empty())
        addBlock(n + align);

    Block* b   = blocks_.back().get();
    size_t off = alignUp(b->used, align);

    if (off + n > b->size)
    {
        addBlock(n + align);
        b   = blocks_.back().get();
        off = alignUp(b->used, align);
    }

    void* mem = b->ptr + off;
    b->used   = off + n;
    return mem;
}

void Arena::shrinkToFit()
{
    // Drop any *trailing* blocks that were never used
    while (!blocks_.empty() && blocks_.back()->used == 0)
        blocks_.pop_back();

    // Reduce the vector's capacity as well
    blocks_.shrink_to_fit();
}

SWC_END_NAMESPACE()

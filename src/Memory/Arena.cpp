#include "pch.h"
#include "Memory/Arena.h"

SWC_BEGIN_NAMESPACE();

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

SWC_END_NAMESPACE();

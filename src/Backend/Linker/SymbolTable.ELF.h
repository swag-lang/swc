#pragma once
#include "Backend/Debug/SymbolTable.h"

SWC_BEGIN_NAMESPACE();

struct LinkImage;

namespace ELFSymbolTable
{
    // Object contributions keep link-time virtual addresses. They are non-allocated,
    // so resolving their absolute relocations never requires loader text relocations.
    void appendObject(LinkImage& image, std::span<const SymbolTable::Entry> entries);

    // Coalesces the linked contributions into the runtime's ordinary image-relative
    // table. A missing table is valid; a malformed table leaves the image unchanged.
    bool finalizeImage(ByteArray& image, Utf8& outError);
}

SWC_END_NAMESPACE();

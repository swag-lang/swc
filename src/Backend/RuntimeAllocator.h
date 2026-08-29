#pragma once
#include "Backend/RuntimeBase.h"

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    // Mirror of the Swag 'AllocatorRequest' (bin/runtime/api.swg): keep the field
    // order and layout in sync. The operation is carried by the IAllocator METHOD
    // being called (alloc/realloc/free/freeAll/assertAllocated), not by the request.
    struct AllocatorRequest
    {
        SourceCodeLocation callerLoc;
        String             hint;
        void*              address;
        uint64_t           size;
        uint64_t           oldSize;
        uint32_t           alignment = 0;
    };

    // Mirror of the Swag 'IAllocator' interface: the itable holds, after the typeinfo
    // slot, one entry per method in DECLARATION order - alloc, realloc, free, freeAll,
    // assertAllocated.
    struct IAllocator : Interface
    {
    };
}

SWC_END_NAMESPACE();

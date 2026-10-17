#pragma once
#include "Backend/RuntimeBase.h"

// WARNING!
// WARNING! This file must be in sync with "bin/runtime/context.swg"
// WARNING!

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    struct ScratchAllocator
    {
        Interface allocator;
        uint8_t*  block;
        uint64_t  capacity;
        uint64_t  used;
        uint64_t  maxUsed;
        void*     firstLeak;
        uint64_t  totalLeak;
        uint64_t  maxLeak;
        void*     releaseOwner;
        void (*releaseHook)(ScratchAllocator*);
    };

    struct ErrorValue
    {
        Any              value;
        void*            record;
        uint32_t         reserved;
        uint32_t         pushTraceIndex;
        uint32_t         pushHasError;
        uint32_t         padding;
        Any              pushCurError;
        ScratchAllocator pushErrorAllocator;
    };

    struct ValueBorrowRecord
    {
        ValueBorrowRecord*        next;
        ValueBorrowRecord*        previous;
        const void*               address;
        uint64_t                  size;
        uint64_t                  threadId;
        const SourceCodeLocation* location;
    };

    // The runtime's private 'ValueBorrowExtent': the address range every open borrow lies in.
    // Generated write guards skip the runtime call for a write outside it.
    struct ValueBorrowExtent
    {
        uint64_t low;
        uint64_t high; // Zero while no borrow is open
    };

    struct Context
    {
        Interface          allocator;
        ScratchAllocator   tempAllocator;
        ScratchAllocator   errorAllocator;
        RuntimeFlags       runtimeFlags;
        Interface          defaultAllocator;
        uint64_t           user0;
        uint64_t           user1;
        uint64_t           user2;
        uint64_t           user3;
        SourceCodeLocation traces[32];
        ErrorValue         errorLevels[4];
        void*              errorBlocks;
        SourceCodeLocation exceptionLoc;
        const void*        exceptionParams[4];
        void (*panic)(String, SourceCodeLocation);
        Any      curError;
        uint32_t errorIndex;
        uint32_t traceIndex;
        uint32_t hasError;
        void*    errorCaptures;
        uint64_t runtimeTlsIdPlusOne;
        void*    panicStack[64];
        uint32_t panicStackCount;
        void*    panicCatch;
        void*    cancelScope;
    };
}

SWC_END_NAMESPACE();

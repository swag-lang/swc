#pragma once
#include "Backend/Runtime.h"

// WARNING!
// WARNING! This file must be in sync with "bin/runtime/api.swg"
// WARNING!

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    struct ErrorValue
    {
        Any      value;
        uint32_t pushUsedAlloc;
        uint32_t pushTraceIndex;
        uint32_t pushHasError;
        uint32_t padding;
        Any      pushCurError;
    };

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
        ErrorValue         errors[32];
        SourceCodeLocation exceptionLoc;
        const void*        exceptionParams[4];
        void (*panic)(String, SourceCodeLocation);
        Any      curError;
        uint32_t errorIndex;
        uint32_t traceIndex;
        uint32_t hasError;
        uint64_t runtimeTlsIdPlusOne;
        void*    panicStack[64];
        uint32_t panicStackCount;
    };
}

SWC_END_NAMESPACE();

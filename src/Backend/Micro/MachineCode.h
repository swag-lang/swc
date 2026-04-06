#pragma once

#include "Backend/Micro/MicroBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct MachineCode
{
    using DebugSourceRange = EncoderDebugSourceRange;

    std::vector<std::byte>        bytes;
    std::vector<std::byte>        unwindInfo;
    std::vector<MicroRelocation>  codeRelocations;
    std::vector<DebugSourceRange> debugSourceRanges;

    Result emit(TaskContext& ctx, MicroBuilder& builder);
#if SWC_HAS_STATS
    size_t memStorageReserved() const
    {
        return bytes.capacity() * sizeof(std::byte) +
               unwindInfo.capacity() * sizeof(std::byte) +
               codeRelocations.capacity() * sizeof(MicroRelocation) +
               debugSourceRanges.capacity() * sizeof(DebugSourceRange);
    }
#endif
};

SWC_END_NAMESPACE();

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

    bool   resolveSourceCodeRefAtOffset(SourceCodeRef& outSourceCodeRef, uint32_t codeOffset) const;
    Result emit(TaskContext& ctx, MicroBuilder& builder);
};

SWC_END_NAMESPACE();

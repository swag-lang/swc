#pragma once

#include "Backend/Micro/MicroBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct MachineCode
{
    struct DebugSourceRange
    {
        uint32_t      codeStartOffset = 0;
        uint32_t      codeEndOffset   = 0;
        SourceCodeRef sourceCodeRef   = SourceCodeRef::invalid();
    };

    std::vector<std::byte>       bytes;
    std::vector<MicroRelocation> codeRelocations;
    std::vector<DebugSourceRange> debugSourceRanges;

    bool   resolveSourceCodeRefAtOffset(SourceCodeRef& outSourceCodeRef, uint32_t codeOffset) const;
    Result emit(TaskContext& ctx, MicroBuilder& builder);
};

SWC_END_NAMESPACE();

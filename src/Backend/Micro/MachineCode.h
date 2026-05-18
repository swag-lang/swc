#pragma once

#include "Backend/Micro/MicroBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class SourceFile;

struct MachineCode
{
    using DebugSourceRange = EncoderDebugSourceRange;

    struct ResolvedDebugSourceRange
    {
        const DebugSourceRange* debugRange = nullptr;
        ResolvedDebugSourceInfo source;
    };

    std::vector<std::byte>        bytes;
    std::vector<std::byte>        unwindInfo;
    std::vector<MicroRelocation>  codeRelocations;
    std::vector<DebugSourceRange> debugSourceRanges;

    const DebugSourceRange* findDebugSourceRangeAtOffset(uint32_t codeOffset) const;
    bool                    tryResolveDebugSourceRange(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, const DebugSourceRange& range) const;
    bool                    tryResolveDebugSourceRangeAtOffset(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, uint32_t codeOffset) const;
    Result                  emit(TaskContext& ctx, MicroBuilder& builder);
};

SWC_END_NAMESPACE();

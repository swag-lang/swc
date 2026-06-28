#pragma once

#include "Backend/Micro/MicroBuilder.h"
#include "Support/Core/ByteSpan.h"

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

    ByteArray                     bytes;
    ByteArray                     unwindInfo;
    std::vector<MicroRelocation>  codeRelocations;
    std::vector<DebugSourceRange> debugSourceRanges;

    // Physical register the debug local-stack base resolved to after register allocation, or
    // invalid when the function has no local stack frame. Locals are addressed against it.
    MicroReg debugStackBasePhysReg = MicroReg::invalid();

    const DebugSourceRange* findDebugSourceRangeAtOffset(uint32_t codeOffset) const;
    static bool             tryResolveDebugSourceRange(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, const DebugSourceRange& range);
    bool                    tryResolveDebugSourceRangeAtOffset(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, uint32_t codeOffset) const;
    Result                  emit(TaskContext& ctx, MicroBuilder& builder, MicroReg debugStackBaseVirtualReg = MicroReg::invalid());
};

SWC_END_NAMESPACE();

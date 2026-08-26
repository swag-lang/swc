#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

const MachineCode::DebugSourceRange* MachineCode::findDebugSourceRangeAtOffset(const uint32_t codeOffset) const
{
    for (const auto& range : debugSourceRanges)
    {
        if (codeOffset < range.codeStartOffset || codeOffset >= range.codeEndOffset)
            continue;
        return &range;
    }

    return nullptr;
}

bool MachineCode::tryResolveDebugSourceRange(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, const DebugSourceRange& range)
{
    outResolvedRange = {};
    if (!tryResolveDebugSourceInfo(ctx, outResolvedRange.source, range.debugSourceInfo))
        return false;

    outResolvedRange.debugRange = &range;
    return true;
}

bool MachineCode::tryResolveDebugSourceRangeAtOffset(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, const uint32_t codeOffset) const
{
    outResolvedRange = {};

    const auto* range = findDebugSourceRangeAtOffset(codeOffset);
    if (!range)
        return false;

    return tryResolveDebugSourceRange(ctx, outResolvedRange, *range);
}

Result MachineCode::emit(TaskContext& ctx, MicroBuilder& builder, MicroReg debugStackBaseVirtualReg, uint16_t sanitizerSafetyMask, const SymbolFunction* sanitizerFunction)
{
    const Runtime::BuildCfgBackend& backendBuildCfg   = ctx.compiler().buildCfg().backend;
    const bool                      computeUnwindInfo = backendBuildCfg.enableExceptions || backendBuildCfg.debugInfo;

    MicroPassContext passContext;
    passContext.callConvKind             = CallConvKind::Swag;
    passContext.preservePersistentRegs   = true;
    passContext.forceFramePointer        = computeUnwindInfo;
    passContext.debugStackBaseVirtualReg = debugStackBaseVirtualReg;
    passContext.sanitizerSafetyMask      = sanitizerSafetyMask;
    passContext.sanitizerFunction        = sanitizerFunction;

#ifdef _M_X64
    X64Encoder encoder(ctx);
#endif

    encoder.setBackendBuildCfg(builder.backendBuildCfg());
    encoder.clearDebugSourceRanges();

    SWC_RESULT(builder.runPasses(&encoder, passContext));

    debugStackBasePhysReg = passContext.debugStackBasePhysReg;

    // Diagnostics can abort lowering before any encodable instruction is produced.
    // Propagate the existing failure instead of crashing in the test runner.
    const auto codeSize = encoder.size();
    if (codeSize == 0)
        return Result::Error;

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    if (computeUnwindInfo)
        encoder.buildUnwindInfo(unwindInfo);
    else
        unwindInfo.clear();

    codeRelocations   = builder.codeRelocations();
    debugSourceRanges = encoder.debugSourceRanges();

    return Result::Continue;
}

SWC_END_NAMESPACE();

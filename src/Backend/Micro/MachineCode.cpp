#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroPass.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

bool MachineCode::resolveSourceCodeRefAtOffset(SourceCodeRef& outSourceCodeRef, const uint32_t codeOffset) const
{
    const DebugSourceRange* bestBefore = nullptr;
    for (const DebugSourceRange& range : debugSourceRanges)
    {
        if (!range.sourceCodeRef.isValid())
            continue;

        if (codeOffset >= range.codeStartOffset && codeOffset < range.codeEndOffset)
        {
            outSourceCodeRef = range.sourceCodeRef;
            return true;
        }

        if (range.codeStartOffset > codeOffset)
            continue;

        if (!bestBefore || bestBefore->codeStartOffset < range.codeStartOffset)
            bestBefore = &range;
    }

    if (bestBefore)
    {
        outSourceCodeRef = bestBefore->sourceCodeRef;
        return true;
    }

    outSourceCodeRef = SourceCodeRef::invalid();
    return false;
}

Result MachineCode::emit(TaskContext& ctx, MicroBuilder& builder)
{
    MicroPassContext passContext;
    passContext.callConvKind           = CallConvKind::Host;
    passContext.preservePersistentRegs = true;

#ifdef _M_X64
    X64Encoder encoder(ctx);
    encoder.setBackendBuildCfg(builder.backendBuildCfg());
    encoder.clearDebugSourceRanges();
#endif

#if SWC_HAS_STATS
    const size_t numMicroInstrNoOptim    = builder.instructions().count();
    const size_t numMicroOperandsNoOptim = builder.operands().count();
    const size_t memMicroStorageNoOptim  = builder.instructions().allocatedBytes() + builder.operands().allocatedBytes();
#endif

    SWC_RESULT_VERIFY(builder.runPasses(&encoder, passContext));

#if SWC_HAS_STATS
    const size_t numMicroInstrFinal    = builder.instructions().count();
    const size_t numMicroOperandsFinal = builder.operands().count();
    const size_t memMicroStorageFinal  = builder.instructions().allocatedBytes() + builder.operands().allocatedBytes();
    Stats::get().numMicroInstrNoOptim.fetch_add(numMicroInstrNoOptim, std::memory_order_relaxed);
    Stats::get().numMicroInstrFinal.fetch_add(numMicroInstrFinal, std::memory_order_relaxed);
    Stats::get().numMicroOperandsNoOptim.fetch_add(numMicroOperandsNoOptim, std::memory_order_relaxed);
    Stats::get().numMicroOperandsFinal.fetch_add(numMicroOperandsFinal, std::memory_order_relaxed);
    Stats::get().numMicroInstrOptimRemoved.fetch_add(passContext.optimizationInstrRemoved, std::memory_order_relaxed);
    Stats::get().numMicroInstrOptimAdded.fetch_add(passContext.optimizationInstrAdded, std::memory_order_relaxed);
    Stats::get().memMicroStorageNoOptim.fetch_add(memMicroStorageNoOptim, std::memory_order_relaxed);
    Stats::get().memMicroStorageFinal.fetch_add(memMicroStorageFinal, std::memory_order_relaxed);
#endif

    const auto codeSize = encoder.size();
    SWC_FORCE_ASSERT(codeSize != 0);

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    codeRelocations   = builder.codeRelocations();
    debugSourceRanges = encoder.debugSourceRanges();
    return Result::Continue;
}

SWC_END_NAMESPACE();

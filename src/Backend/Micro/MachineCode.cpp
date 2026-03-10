#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

Result MachineCode::emit(TaskContext& ctx, MicroBuilder& builder)
{
    const Runtime::BuildCfgBackend& backendBuildCfg   = ctx.compiler().buildCfg().backend;
    const bool                      computeUnwindInfo = backendBuildCfg.enableExceptions || backendBuildCfg.debugInfo;

    MicroPassContext passContext;
    passContext.callConvKind           = CallConvKind::Host;
    passContext.preservePersistentRegs = true;
    passContext.forceFramePointer      = computeUnwindInfo;

#ifdef _M_X64
    X64Encoder encoder(ctx);
#endif

    encoder.setBackendBuildCfg(builder.backendBuildCfg());
    encoder.clearDebugSourceRanges();

#if SWC_HAS_STATS
    const size_t numMicroInstrNoOptim = builder.instructions().count();
#endif

    SWC_RESULT_VERIFY(builder.runPasses(&encoder, passContext));

#if SWC_HAS_STATS
    const size_t numMicroInstrFinal   = builder.instructions().count();
    const size_t memMicroStorageFinal = builder.instructions().allocatedBytes() + builder.operands().allocatedBytes();
    Stats::get().numMicroInstrNoOptim.fetch_add(numMicroInstrNoOptim, std::memory_order_relaxed);
    Stats::get().numMicroInstrFinal.fetch_add(numMicroInstrFinal, std::memory_order_relaxed);
    Stats::get().memMicroStorageFinal.fetch_add(memMicroStorageFinal, std::memory_order_relaxed);
#endif

    const auto codeSize = encoder.size();
    SWC_ASSERT(codeSize != 0);

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

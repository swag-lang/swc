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

    SWC_RESULT(builder.runPasses(&encoder, passContext));

#if SWC_HAS_STATS
    Stats::get().numMicroInstrBeforePasses.fetch_add(passContext.statsInstrBeforePasses, std::memory_order_relaxed);
    Stats::get().numMicroInstrAfterOptim.fetch_add(passContext.statsInstrAfterOptim, std::memory_order_relaxed);
    Stats::get().numMicroInstrAfterRA.fetch_add(passContext.statsInstrAfterRA, std::memory_order_relaxed);
    Stats::get().numMicroInstrFinal.fetch_add(passContext.statsInstrFinal, std::memory_order_relaxed);
#endif

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

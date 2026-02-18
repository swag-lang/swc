#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/Passes/MicroEmitPass.h"
#include "Backend/Micro/Passes/MicroLegalizePass.h"
#include "Backend/Micro/Passes/MicroPass.h"
#include "Backend/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/Micro/Passes/MicroRegisterAllocationPass.h"

SWC_BEGIN_NAMESPACE();

void MachineCode::emit(TaskContext& ctx, MicroBuilder& builder)
{
    MicroRegisterAllocationPass regAllocPass;
    MicroPrologEpilogPass       persistentRegsPass;
    MicroLegalizePass           legalizePass;
    MicroEmitPass               encodePass;

    MicroPassContext passContext;
    passContext.callConvKind           = CallConvKind::Host;
    passContext.preservePersistentRegs = true;

#ifdef _M_X64
    X64Encoder encoder(ctx);
    encoder.setBackendBuildCfg(builder.backendBuildCfg());
#endif

    MicroPassManager passManager;
    passManager.add(regAllocPass);
    passManager.add(persistentRegsPass);
    passManager.add(legalizePass);
    passManager.add(encodePass);
    builder.runPasses(passManager, &encoder, passContext);

    const auto codeSize = encoder.size();
    SWC_FORCE_ASSERT(codeSize != 0);

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    codeRelocations = builder.codeRelocations();
}

SWC_END_NAMESPACE();


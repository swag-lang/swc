#include "pch.h"
#include "Backend/CodeGen/Micro/MachineCode.h"
#include "Backend/CodeGen/Encoder/X64Encoder.h"
#include "Backend/CodeGen/Micro/Passes/MicroEmitPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroLegalizePass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroRegisterAllocationPass.h"

SWC_BEGIN_NAMESPACE();

void MachineCode::emit(TaskContext& ctx, MicroInstrBuilder& builder)
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
    encoder.setBackendOptimizeLevel(builder.backendOptimizeLevel());
#endif

    MicroPassManager passManager;
    passManager.add(regAllocPass);
    passManager.add(persistentRegsPass);
    passManager.add(legalizePass);
    passManager.add(encodePass);
    builder.clearCodeRelocations();
    builder.clearPointerImmediateRelocations();
    builder.runPasses(passManager, &encoder, passContext);

    const auto codeSize = encoder.size();
    SWC_FORCE_ASSERT(codeSize != 0);

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    codeRelocations = builder.codeRelocations();
}

SWC_END_NAMESPACE();

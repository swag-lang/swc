#include "pch.h"
#include "Backend/CodeGen/Micro/LoweredMicroCode.h"
#include "Backend/CodeGen/Encoder/X64Encoder.h"
#include "Backend/CodeGen/Micro/Passes/MicroEmitPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroLegalizePass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroRegisterAllocationPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void lowerToHostObjectCode(TaskContext& ctx, MicroInstrBuilder& builder, LoweredMicroCode& outCode)
    {
        MicroRegisterAllocationPass regAllocPass;
        MicroPrologEpilogPass       persistentRegsPass;
        MicroLegalizePass           legalizePass;
        MicroEmitPass               encodePass;

        MicroPassContext passContext;
        passContext.callConvKind           = CallConvKind::Host;
        passContext.preservePersistentRegs = true;

        X64Encoder encoder(ctx);

        MicroPassManager passManager;
        passManager.add(regAllocPass);
        passManager.add(persistentRegsPass);
        passManager.add(legalizePass);
        passManager.add(encodePass);
        builder.clearCodeRelocations();
        builder.runPasses(passManager, &encoder, passContext);

        const auto codeSize = encoder.size();
        SWC_FORCE_ASSERT(codeSize != 0);

        outCode.bytes.resize(codeSize);
        encoder.copyTo(outCode.bytes);
        outCode.codeRelocations = builder.codeRelocations();
    }
}

void lowerMicroInstructions(TaskContext& ctx, MicroInstrBuilder& builder, LoweredMicroCode& outCode)
{
#ifdef _M_X64
    lowerToHostObjectCode(ctx, builder, outCode);
#else
    SWC_UNREACHABLE();
#endif
}

SWC_END_NAMESPACE();

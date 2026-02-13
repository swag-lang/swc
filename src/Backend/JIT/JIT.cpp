#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result compileWithEncoder(MicroInstrBuilder& builder, Encoder& encoder, JITExecMemory& outExecutableMemory)
    {
        MicroRegAllocPass regAllocPass;
        MicroEncodePass   encodePass;
        MicroPassManager  passManager;
        passManager.add(regAllocPass);
        passManager.add(encodePass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        builder.runPasses(passManager, &encoder, passContext);
        const auto codeSize = encoder.size();
        if (!codeSize)
            return Result::Error;

        std::vector<std::byte> linearCode(codeSize);
        encoder.copyTo(linearCode);

        if (!outExecutableMemory.allocateAndCopy(asByteSpan(linearCode)))
            return Result::Error;

        return Result::Continue;
    }
}

Result JIT::compile(TaskContext& ctx, MicroInstrBuilder& builder, JITExecMemory& outExecutableMemory)
{
#ifdef _M_X64
    X64Encoder encoder(ctx);
    return compileWithEncoder(builder, encoder, outExecutableMemory);
#else
    SWC_UNREACHABLE();
#endif
}

SWC_END_NAMESPACE();


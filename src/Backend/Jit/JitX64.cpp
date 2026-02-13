#include "pch.h"
#include "Backend/Jit/JitX64.h"
#include "Backend/Jit/JitExecutableMemory.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    Result JitX64::compile(TaskContext& ctx, const std::function<void(MicroInstrBuilder&)>& buildFn, JitExecutableMemory& outExecutableMemory)
    {
        MicroInstrBuilder builder(ctx);
        buildFn(builder);
        return compile(ctx, builder, outExecutableMemory);
    }

    Result JitX64::compile(TaskContext& ctx, MicroInstrBuilder& builder, JitExecutableMemory& outExecutableMemory)
    {
#if defined(_M_X64)
        X64Encoder       encoder(ctx);
        MicroEncodePass  encodePass;
        MicroPassManager passManager;
        passManager.add(encodePass);

        MicroPassContext passContext;
        builder.runPasses(passManager, &encoder, passContext);
        if (!encoder.size())
            return Result::Error;

        if (!outExecutableMemory.allocateAndCopy(encoder.data(), encoder.size()))
            return Result::Error;

        return Result::Continue;
#else
        (void) ctx;
        (void) builder;
        (void) outExecutableMemory;
        return Result::Error;
#endif
    }
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Backend/Jit/Jit.h"
#include "Backend/Jit/JitExecMemory.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    namespace
    {
        Result compileWithEncoder(MicroInstrBuilder& builder, Encoder& encoder, JitExecMemory& outExecutableMemory)
        {
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
        }
    }

    Result Jit::compile(TaskContext& ctx, const std::function<void(MicroInstrBuilder&)>& buildFn, JitExecMemory& outExecutableMemory)
    {
        MicroInstrBuilder builder(ctx);
        buildFn(builder);
        return compile(ctx, builder, outExecutableMemory);
    }

    Result Jit::compile(TaskContext& ctx, MicroInstrBuilder& builder, JitExecMemory& outExecutableMemory)
    {
#if defined(_M_X64)
        X64Encoder encoder(ctx);
        return compileWithEncoder(builder, encoder, outExecutableMemory);
#else
        (void) ctx;
        (void) builder;
        (void) outExecutableMemory;
        return Result::Error;
#endif
    }
}

SWC_END_NAMESPACE();

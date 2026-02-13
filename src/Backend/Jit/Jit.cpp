#include "pch.h"
#include "Backend/Jit/Jit.h"
#include "Backend/Jit/JitExecMemory.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    namespace
    {
        Result compileWithEncoder(MicroInstrBuilder& builder, Encoder& encoder, JitExecMemory& outExecutableMemory)
        {
            MicroRegAllocPass regAllocPass;
            MicroEncodePass  encodePass;
            MicroPassManager passManager;
            passManager.add(regAllocPass);
            passManager.add(encodePass);

            MicroPassContext passContext;
            passContext.callConvKind = CallConvKind::C;
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

    Result Jit::compile(TaskContext& ctx, MicroInstrBuilder& builder, JitExecMemory& outExecutableMemory)
    {
#ifdef _M_X64
        X64Encoder encoder(ctx);
        return compileWithEncoder(builder, encoder, outExecutableMemory);
#else
        SWC_UNREACHABLE();
#endif
    }
}

SWC_END_NAMESPACE();

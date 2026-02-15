#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/CodeGen/Encoder/X64Encoder.h"
#include "Backend/CodeGen/Micro/Passes/MicroEmitPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroLegalizePass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/CodeGen/Micro/Passes/MicroRegisterAllocationPass.h"
#include "Backend/JIT/JITExecMemoryManager.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result compileWithEncoder(TaskContext& ctx, MicroInstrBuilder& builder, Encoder& encoder, JITExecMemory& outExecutableMemory)
    {
        MicroRegisterAllocationPass regAllocPass;
        MicroPrologEpilogPass       persistentRegsPass;
        MicroLegalizePass           legalizePass;
        MicroEmitPass               encodePass;

        MicroPassContext passContext;
        passContext.callConvKind           = CallConvKind::Host;
        passContext.preservePersistentRegs = true;

        MicroPassManager passManager;
        passManager.add(regAllocPass);
        passManager.add(persistentRegsPass);
        passManager.add(legalizePass);
        passManager.add(encodePass);
        builder.runPasses(passManager, &encoder, passContext);

        const auto codeSize = encoder.size();
        if (!codeSize)
            return Result::Error;

        std::vector<std::byte> linearCode(codeSize);
        encoder.copyTo(linearCode);

        if (!ctx.compiler().jitMemMgr().allocateAndCopy(asByteSpan(linearCode), outExecutableMemory))
            return Result::Error;

        return Result::Continue;
    }
}

Result JIT::compile(TaskContext& ctx, MicroInstrBuilder& builder, JITExecMemory& outExecutableMemory)
{
#ifdef _M_X64
    X64Encoder encoder(ctx);
    return compileWithEncoder(ctx, builder, encoder, outExecutableMemory);
#else
    SWC_UNREACHABLE();
#endif
}

SWC_END_NAMESPACE();

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
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result patchCodeRelocations(MicroInstrBuilder& builder, JITExecMemory& executableMemory)
    {
        const auto& relocations = builder.codeRelocations();
        if (relocations.empty())
            return Result::Continue;

        auto* const basePtr = executableMemory.entryPoint<uint8_t*>();
        if (!basePtr || executableMemory.empty())
            return Result::Error;

        if (!Os::makeWritableExecutableMemory(basePtr, executableMemory.size()))
            return Result::Error;

        for (const auto& reloc : relocations)
        {
            if (reloc.targetAddress == 0)
                continue;

            if (reloc.kind != MicroInstrCodeRelocation::Kind::Rel32)
                return Result::Error;

            const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(int32_t);
            if (patchEndOffset > executableMemory.size())
                return Result::Error;

            const auto nextAddress = reinterpret_cast<uint64_t>(basePtr + patchEndOffset);
            const auto target      = reloc.targetAddress;
            const auto delta       = static_cast<int64_t>(target) - static_cast<int64_t>(nextAddress);
            if (delta < std::numeric_limits<int32_t>::min() || delta > std::numeric_limits<int32_t>::max())
                return Result::Error;

            const int32_t disp32 = static_cast<int32_t>(delta);
            std::memcpy(basePtr + reloc.codeOffset, &disp32, sizeof(disp32));
        }

        if (!Os::makeExecutableMemory(basePtr, executableMemory.size()))
            return Result::Error;

        return Result::Continue;
    }

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
        builder.clearCodeRelocations();
        builder.runPasses(passManager, &encoder, passContext);

        const auto codeSize = encoder.size();
        if (!codeSize)
            return Result::Error;

        std::vector<std::byte> linearCode(codeSize);
        encoder.copyTo(linearCode);

        if (!ctx.compiler().jitMemMgr().allocateAndCopy(asByteSpan(linearCode), outExecutableMemory))
            return Result::Error;

        RESULT_VERIFY(patchCodeRelocations(builder, outExecutableMemory));
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

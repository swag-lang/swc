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
    void patchCodeRelocations(MicroInstrBuilder& builder, JITExecMemory& executableMemory)
    {
        const auto& relocations = builder.codeRelocations();
        if (relocations.empty())
            return;

        auto* const basePtr = executableMemory.entryPoint<uint8_t*>();
        SWC_FORCE_ASSERT(basePtr != nullptr);
        SWC_FORCE_ASSERT(!executableMemory.empty());

        SWC_FORCE_ASSERT(Os::makeWritableExecutableMemory(basePtr, executableMemory.size()));

        for (const auto& reloc : relocations)
        {
            if (reloc.targetAddress == 0)
                continue;

            SWC_FORCE_ASSERT(reloc.kind == MicroInstrCodeRelocation::Kind::Rel32);

            const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(int32_t);
            SWC_FORCE_ASSERT(patchEndOffset <= executableMemory.size());

            const auto nextAddress = reinterpret_cast<uint64_t>(basePtr + patchEndOffset);
            const auto target      = reloc.targetAddress;
            const auto delta       = static_cast<int64_t>(target) - static_cast<int64_t>(nextAddress);
            SWC_FORCE_ASSERT(delta >= std::numeric_limits<int32_t>::min() && delta <= std::numeric_limits<int32_t>::max());

            const int32_t disp32 = static_cast<int32_t>(delta);
            std::memcpy(basePtr + reloc.codeOffset, &disp32, sizeof(disp32));
        }

        SWC_FORCE_ASSERT(Os::makeExecutableMemory(basePtr, executableMemory.size()));
    }

    void compileWithEncoder(TaskContext& ctx, MicroInstrBuilder& builder, Encoder& encoder, JITExecMemory& outExecutableMemory)
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
        SWC_FORCE_ASSERT(codeSize != 0);

        std::vector<std::byte> linearCode(codeSize);
        encoder.copyTo(linearCode);

        SWC_FORCE_ASSERT(ctx.compiler().jitMemMgr().allocateAndCopy(asByteSpan(linearCode), outExecutableMemory));

        patchCodeRelocations(builder, outExecutableMemory);
    }
}

void JIT::emit(TaskContext& ctx, MicroInstrBuilder& builder, JITExecMemory& outExecutableMemory)
{
#ifdef _M_X64
    X64Encoder encoder(ctx);
    compileWithEncoder(ctx, builder, encoder, outExecutableMemory);
#else
    SWC_UNREACHABLE();
#endif
}

SWC_END_NAMESPACE();

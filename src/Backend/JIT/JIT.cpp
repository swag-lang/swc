#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemoryManager.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void patchCodeRelocations(std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& executableMemory)
    {
        if (relocations.empty())
            return;

        SWC_FORCE_ASSERT(!linearCode.empty());
        auto* const basePtr = executableMemory.entryPoint<uint8_t*>();
        SWC_FORCE_ASSERT(basePtr != nullptr);
        SWC_FORCE_ASSERT(!executableMemory.empty());
        SWC_FORCE_ASSERT(executableMemory.size() >= linearCode.size_bytes());

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

}

void JIT::emit(TaskContext& ctx, std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& outExecutableMemory)
{
#ifdef _M_X64
    SWC_FORCE_ASSERT(ctx.compiler().jitMemMgr().allocateAndCopy(linearCode, outExecutableMemory));
    patchCodeRelocations(linearCode, relocations, outExecutableMemory);
#else
    SWC_UNREACHABLE();
#endif
}

SWC_END_NAMESPACE();

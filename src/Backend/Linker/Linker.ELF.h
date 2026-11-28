#pragma once
#include "Backend/Linker/Linker.h"

SWC_BEGIN_NAMESPACE();

// Integrated Linux ELF linker. Resolves archives and shared-library imports and
// writes executables, shared objects and static archives without a host toolchain.
class ELFLinker final : public Linker
{
public:
    explicit ELFLinker(NativeBackendBuilder& builder) :
        Linker(builder)
    {
    }
    Result      prepareLink(LinkJob& outJob) override;
    Result      tryPrepareIncrementalLink(bool& outPrepared, LinkJob& outJob, std::span<const fs::path> objectPaths, std::span<const Utf8> libraryNames) override;
    static void execute(LinkJob& job);

private:
    Result prepareFunctionCache(LinkJob& job) const;
};

SWC_END_NAMESPACE();

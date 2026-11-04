#pragma once
#include "Backend/Linker/Linker.h"

SWC_BEGIN_NAMESPACE();

// GNU/Linux final linking uses the host C driver for CRT/loader discovery.
// Indexed ELF archives are built internally from the prepared object bytes.
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

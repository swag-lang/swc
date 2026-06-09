#pragma once

#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkJob.h"

SWC_BEGIN_NAMESPACE();

// Base class for the integrated linker. A target-specific subclass lowers the backend output into a
// NativeLinkJob (a target-independent LinkImage plus output settings); the shared executeLink() and
// finishLink() turn that into the final on-disk artifact. There is no external linker process.
//
// The three phases mirror the workspace async pipeline:
//   prepareLink  - foreground, reads compiler state, produces a self-contained NativeLinkJob.
//   executeLink  - background-safe, serialises the image and writes the artifact (no compiler state).
//   finishLink   - foreground, reports diagnostics and validates the artifact.
class NativeLinker
{
public:
    explicit NativeLinker(NativeBackendBuilder& builder);
    virtual ~NativeLinker() = default;

    static std::unique_ptr<NativeLinker> create(NativeBackendBuilder& builder);

    // Discovers the MSVC/SDK library directories the integrated linker resolves imports against. Also
    // used for dry-run and show-config reporting.
    static Os::WindowsToolchainDiscoveryResult queryToolchainPaths(const NativeBackendBuilder& builder, Os::WindowsToolchainPaths& outToolchain);

    // Synchronous one-shot link on the calling thread.
    Result link();

    virtual Result prepareLink(NativeLinkJob& outJob) = 0;
    static void    executeLink(NativeLinkJob& job);
    Result         finishLink(const NativeLinkJob& job) const;

protected:
    NativeBackendBuilder* builder_ = nullptr;
};

SWC_END_NAMESPACE();

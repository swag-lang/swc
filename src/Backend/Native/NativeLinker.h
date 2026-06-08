#pragma once

#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkerToolRun.h"

SWC_BEGIN_NAMESPACE();

class NativeLinker
{
public:
    explicit NativeLinker(NativeBackendBuilder& builder);
    virtual ~NativeLinker() = default;

    static std::unique_ptr<NativeLinker>       create(NativeBackendBuilder& builder);
    static Os::WindowsToolchainDiscoveryResult queryToolchainPaths(const NativeBackendBuilder& builder, Os::WindowsToolchainPaths& outToolchain);

    // Synchronous one-shot link: prepare + run + finish, on the calling thread.
    Result link();

    // Three-phase link used by the workspace async pipeline. prepareLink builds the tool command on
    // the foreground thread (reads compiler state); executeToolRun spawns and waits on the process
    // and can run on a background thread; finishToolRun interprets the result and reports
    // diagnostics on the foreground thread.
    virtual Result      prepareLink(NativeLinkerToolRun& outRun) = 0;
    static void         executeToolRun(NativeLinkerToolRun& run);
    Result              finishToolRun(const NativeLinkerToolRun& run) const;

protected:
    Result prepareToolRun(NativeLinkerToolRun& outRun, const fs::path& exePath, const std::vector<Utf8>& args, const Os::ProcessRunOptions* options) const;

    NativeBackendBuilder* builder_ = nullptr;
};

SWC_END_NAMESPACE();

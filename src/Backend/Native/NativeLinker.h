#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeLinker
{
public:
    explicit NativeLinker(NativeBackendBuilder& builder);
    virtual ~NativeLinker() = default;

    static std::unique_ptr<NativeLinker>       create(NativeBackendBuilder& builder);
    static Os::WindowsToolchainDiscoveryResult queryToolchainPaths(const NativeBackendBuilder& builder, Os::WindowsToolchainPaths& outToolchain);

    virtual Result link() = 0;

protected:
    Result runToolAndValidateArtifacts(const fs::path& exePath, const std::vector<Utf8>& args) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();

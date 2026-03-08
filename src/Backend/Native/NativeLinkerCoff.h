#pragma once

#include "Backend/Native/NativeLinker.h"

SWC_BEGIN_NAMESPACE();

class NativeLinkerCoff final : public NativeLinker
{
public:
    explicit NativeLinkerCoff(NativeBackendBuilder& builder);

    Result link() override;

private:
    Result            discoverToolchain();
    Result            linkArtifact() const;
    std::vector<Utf8> buildLinkArguments(bool dll) const;
    std::vector<Utf8> buildLibArguments() const;
    void              appendLinkSearchPaths(std::vector<Utf8>& args) const;
    void              collectLinkLibraries(std::set<Utf8>& out) const;
    void              appendUserLinkerArgs(std::vector<Utf8>& args) const;

    NativeBackendBuilder&     builder_;
    Os::WindowsToolchainPaths toolchain_;
};

SWC_END_NAMESPACE();

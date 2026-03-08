#pragma once

#include "Backend/Native/NativeLinker.h"

SWC_BEGIN_NAMESPACE();

class NativeLinkerWindows final : public NativeLinker
{
public:
    explicit NativeLinkerWindows(NativeBackendBuilder& builder);

    bool link() override;

private:
    bool              discoverToolchain();
    bool              linkArtifact();
    std::vector<Utf8> buildLinkArguments(bool dll) const;
    std::vector<Utf8> buildLibArguments() const;
    void              appendLinkSearchPaths(std::vector<Utf8>& args) const;
    void              collectLinkLibraries(std::set<Utf8>& out) const;
    static Utf8       normalizeLibraryName(std::string_view value);
    void              appendUserLinkerArgs(std::vector<Utf8>& args) const;

    NativeBackendBuilder&     builder_;
    Os::WindowsToolchainPaths toolchain_;
};

SWC_END_NAMESPACE();

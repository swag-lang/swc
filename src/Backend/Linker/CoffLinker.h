#pragma once

#include "Backend/Linker/Linker.h"

SWC_BEGIN_NAMESPACE();

// External Windows linker backend (selected with --external-link). Instead of building the image in
// process like PELinker, it writes the COFF object files to disk and shells out to the platform
// toolchain (link.exe for executables/DLLs, lib.exe for static libraries). link.exe also produces the
// PDB itself (/DEBUG:FULL /PDB:), so the integrated PDB writer is bypassed on this path.
class CoffLinker final : public Linker
{
public:
    explicit CoffLinker(NativeBackendBuilder& builder);

    static Os::WindowsToolchainDiscoveryResult queryToolchainPaths(Os::WindowsToolchainPaths& outToolchain);
    static bool                                shouldForwardLinkerOutputLine(std::string_view line, bool dll);

    Result prepareLink(LinkJob& outJob) override;

private:
    Result                    discoverToolchain();
    Result                    writeObjectFiles() const;
    std::vector<Utf8>         buildLinkArguments(bool dll) const;
    std::vector<Utf8>         buildLibArguments() const;
    void                      appendLinkSearchPaths(std::vector<Utf8>& args) const;
    void                      collectLinkLibraries(std::set<Utf8>& out) const;
    void                      appendUserLinkerArgs(std::vector<Utf8>& args) const;
    Os::WindowsToolchainPaths toolchain_;
};

SWC_END_NAMESPACE();

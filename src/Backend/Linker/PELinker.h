#pragma once

#include "Backend/Linker/Linker.h"

SWC_BEGIN_NAMESPACE();

class Archive;
struct CoffObject;

// Integrated Windows PE linker. Lowers the native backend state directly into a LinkImage, resolves
// the remaining undefined symbols against dependency and system import/static libraries (pulling
// static members and turning DLL imports into an import table), and hands the image to the PE writer
// without invoking an out-of-process toolchain.
class PELinker final : public Linker
{
public:
    explicit PELinker(NativeBackendBuilder& builder);

    Result prepareLink(LinkJob& outJob) override;

private:
    Result buildImage(LinkImage& image) const;
    Result buildNativeImage(LinkImage& image) const;
    Result loadArchives(std::vector<Archive>& outArchives) const;
    void   collectLibrarySearch(std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs) const;
    Result resolveSymbols(LinkImage& image, std::vector<Archive>& archives) const;
    void   collectExports(LinkImage& image) const;
    void   buildDebugTable(LinkImage& image) const;
    void   collectDebugInfo(LinkJob& outJob) const;
};

SWC_END_NAMESPACE();

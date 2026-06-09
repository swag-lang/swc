#pragma once

#include "Backend/Linker/Linker.h"

SWC_BEGIN_NAMESPACE();

class Archive;
struct CoffObject;

// Integrated Windows PE linker. Reads the COFF objects the backend just wrote, resolves the remaining
// undefined symbols against the dependency and system import/static libraries (pulling static members
// and turning DLL imports into an import table), merges everything into a target-independent
// LinkImage and hands it to the PE writer -- no external link.exe involved.
class LinkerPe final : public Linker
{
public:
    explicit LinkerPe(NativeBackendBuilder& builder);

    Result prepareLink(LinkJob& outJob) override;

private:
    Result buildImage(LinkImage& image);
    Result readObjects(std::vector<CoffObject>& outObjects);
    Result loadArchives(std::vector<Archive>& outArchives);
    void   collectLibrarySearch(std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs) const;
    Result resolveSymbols(LinkImage& image, std::vector<CoffObject>& objects, std::vector<Archive>& archives);
    void   collectExports(LinkImage& image) const;
    void   buildDebugTable(LinkImage& image) const;
};

SWC_END_NAMESPACE();

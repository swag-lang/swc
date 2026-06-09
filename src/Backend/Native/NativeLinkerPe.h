#pragma once

#include "Backend/Native/NativeLinker.h"

SWC_BEGIN_NAMESPACE();

class NativeArchive;
struct CoffObject;

// Integrated Windows PE linker. Reads the COFF objects the backend just wrote, resolves the remaining
// undefined symbols against the dependency and system import/static libraries (pulling static members
// and turning DLL imports into an import table), merges everything into a target-independent
// LinkImage and hands it to the PE writer -- no external link.exe involved.
class NativeLinkerPe final : public NativeLinker
{
public:
    explicit NativeLinkerPe(NativeBackendBuilder& builder);

    Result prepareLink(NativeLinkJob& outJob) override;

private:
    Result buildImage(LinkImage& image);
    Result readObjects(std::vector<CoffObject>& outObjects);
    Result loadArchives(std::vector<NativeArchive>& outArchives);
    void   collectLibrarySearch(std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs) const;
    Result resolveSymbols(std::vector<CoffObject>& objects, std::vector<NativeArchive>& archives, LinkImage& image);
    void   collectExports(LinkImage& image) const;
    void   buildDebugTable(LinkImage& image) const;
};

SWC_END_NAMESPACE();

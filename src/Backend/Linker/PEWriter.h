#pragma once
#include "Backend/Linker/ImageWriter.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// Windows PE32+ image writer (executable or DLL) and the COFF archive outputs (static and import
// libraries). All symbol resolution, section layout, relocation patching, import-table/IAT synthesis
// and base-relocation generation happen here; the result is the exact bytes to write to disk. The
// per-image working state below is rebuilt on each writeImage call.
class PEWriter final : public ImageWriter
{
public:
    bool writeImage(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const LinkImage& image) override;
    bool buildStaticArchive(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& members) override;
    void buildImportLibrary(std::vector<std::byte>& outBytes, std::string_view dllFileName, const std::vector<Utf8>& exportNames) override;

private:
    struct OutSection
    {
        Utf8                   name;
        std::vector<std::byte> bytes;
        uint32_t               virtualSize = 0;
        bool                   isBss       = false;
        uint32_t               align       = 16;
        uint32_t               rva         = 0;
        uint32_t               fileOffset  = 0;
        uint32_t               rawSize     = 0;
    };

    struct ImportThunk
    {
        const LinkImport* import         = nullptr;
        uint32_t          textOffset     = 0; // offset of the 6-byte thunk within .text
        uint32_t          iatSlotInIdata = 0; // offset of the IAT slot within .idata
    };

    // Where a defined symbol lives: its section in sections_ and its byte offset within that section.
    struct SymbolLoc
    {
        uint32_t sectionIndex = 0;
        uint32_t value        = 0;
    };

    uint32_t resolveSymbolRva(bool& outFound, const Utf8& name) const;
    void     buildImports();
    void     buildExports();
    void     assignLayout();
    bool     applyRelocations(Diagnostic& outDiag);
    void     buildBaseRelocations();
    bool     emit(std::vector<std::byte>& outBytes, Diagnostic& outDiag);

    const LinkImage*                       image_ = nullptr;
    std::vector<OutSection>                sections_;
    std::vector<uint32_t>                  imageToOut_; // image.sections index -> sections_ index
    std::unordered_map<Utf8, SymbolLoc>    symbols_;    // name -> defining section + offset
    std::vector<ImportThunk>               thunks_;
    std::vector<uint32_t>                  idataRvaFixups_;  // positions in .idata holding idata-relative offsets
    std::vector<uint32_t>                  baseRelocSites_;  // RVAs needing IMAGE_REL_BASED_DIR64
    uint32_t                               headersSize_ = 0;
    int32_t                                textIndex_   = -1;
    int32_t                                idataIndex_  = -1;
    int32_t                                edataIndex_  = -1;
    int32_t                                relocIndex_  = -1;
    std::vector<uint32_t>                  edataRvaFixups_;  // edata-relative offsets to relocate by edata.rva
    std::vector<std::pair<uint32_t, Utf8>> eatSymbolFixups_; // export address table entries -> symbol RVA
    uint32_t                               importDirRva_  = 0;
    uint32_t                               importDirSize_ = 0;
    uint32_t                               iatRva_        = 0;
    uint32_t                               iatSize_       = 0;
};

SWC_END_NAMESPACE();

#pragma once
#include "Backend/Linker/LinkDebugInfo.h"

SWC_BEGIN_NAMESPACE();

// Final placement of a defined symbol once the image layout is known.
struct PdbSymbolAddress
{
    bool     found   = false;
    uint16_t segment = 0; // 1-based PE section index (CodeView "segment")
    uint32_t offset  = 0; // byte offset within that section
    uint32_t rva     = 0; // image-relative address
};

// A finalised PE section, as it appears in the image section table. Mirrors the fields a debugger needs
// to map an RVA back to a section and to reconstruct the original section headers stream.
struct PdbSectionInfo
{
    Utf8     name;
    uint32_t rva             = 0;
    uint32_t virtualSize     = 0;
    uint32_t rawSize         = 0;
    uint32_t fileOffset      = 0;
    uint32_t characteristics = 0;
};

// Builds a PDB 7.0 (MSF/DS) debug-info file from the self-contained LinkDebugInfo plus the final image
// layout. The produced GUID/age must be written verbatim into the image's RSDS CodeView debug-directory
// entry so debuggers (and profilers like Superluminal) match the image to this PDB.
class PdbWriter
{
public:
    struct SymbolResolver
    {
        virtual ~SymbolResolver()                                      = default;
        virtual PdbSymbolAddress resolve(const Utf8& symbolName) const = 0;
        // Resolves a section name + offset to a final placement (used for global/static data).
        virtual PdbSymbolAddress resolveSection(const Utf8& sectionName, uint32_t offset) const = 0;
    };

    // Returns the PDB bytes in outBytes and fills outGuid/outAge/outSignature. moduleName/pdbPath are used
    // for the module and object-name records. Never fails for well-formed input.
    static void build(ByteArray&                         outBytes,
                      std::array<uint8_t, 16>&           outGuid,
                      uint32_t&                          outAge,
                      uint32_t&                          outSignature,
                      const LinkDebugInfo&               debugInfo,
                      const std::vector<PdbSectionInfo>& sections,
                      const SymbolResolver&              resolver,
                      const Utf8&                        moduleName,
                      const Utf8&                        pdbPath);
};

SWC_END_NAMESPACE();

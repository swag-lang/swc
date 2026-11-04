#pragma once

#include "Backend/Linker/LinkImage.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// Reads the COFF subset emitted by NativeObjFileWriterCoff: sections, external
// symbols, and relocations. Symbol indices become names so downstream linking
// can work entirely by name.

struct CoffInputReloc
{
    uint32_t offset = 0; // patch offset within the section
    uint16_t type   = 0; // IMAGE_REL_AMD64_*
    Utf8     symbolName;
};

static_assert(sizeof(void*) != 8 || sizeof(CoffInputReloc) == 40);

struct CoffInputSection
{
    Utf8     name;
    uint32_t characteristics = 0;

    ByteArray bytes; // empty for an uninitialised section
    bool      isBss   = false;
    uint32_t  bssSize = 0;

    std::vector<CoffInputReloc> relocs;
};

// A symbol that this object defines in one of its sections.
struct CoffInputSymbol
{
    Utf8     name;
    uint32_t sectionIndex = 0; // 0-based index into CoffObject::sections
    uint32_t value        = 0;
};

struct CoffObject
{
    std::vector<CoffInputSection> sections;
    std::vector<CoffInputSymbol>  definedSymbols;
};

inline uint32_t coffSectionAlignmentFromCharacteristics(uint32_t characteristics)
{
    const uint32_t field = (characteristics & 0x00F00000u) >> 20;
    if (field == 0)
        return 1;

    return 1u << (field - 1);
}

// Decodes a COFF object image. Returns false and fills outDiag on a malformed/unsupported file.
bool readCoffObject(CoffObject& outObject, Diagnostic& outDiag, const ByteArray& bytes);
bool readCoffObject(CoffObject& outObject, Diagnostic& outDiag, std::span<const std::byte> bytes);

// Validates the complete object but materializes only its defined symbols.
bool readCoffDefinedSymbols(std::vector<CoffInputSymbol>& outSymbols, Diagnostic& outDiag, std::span<const std::byte> bytes);

// The COFF field decoders the two readers share: both the object reader and the PE linker
// walk section headers and relocation records, and read the same IMAGE_SCN_* and
// IMAGE_REL_* values out of them.
EnumFlags<LinkSectionFlagsE> linkSectionFlagsFromCoffCharacteristics(uint32_t characteristics);
bool                         linkRelocKindFromCoffType(LinkRelocKind& outKind, uint16_t type);

// Merges matching sections with alignment and rebased symbols and relocations.
// Collects defined symbols globally, dropping CodeView (.debug$*) and runtime
// symbol (.swagsym) sections. Appends to outImage; the caller fills in imports,
// exports, the entry symbol, and image options. Consumes objects so relocation
// symbol names can move into the image. Returns false and fills outDiag on an
// unsupported relocation kind.
bool mergeCoffObjectsIntoImage(LinkImage& outImage, Diagnostic& outDiag, std::vector<CoffObject>&& objects);

SWC_END_NAMESPACE();

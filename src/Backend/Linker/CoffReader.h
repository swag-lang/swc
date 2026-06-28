#pragma once
#include <span>

#include "Support/Core/Utf8.h"
#include "Backend/Linker/LinkImage.h"
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// Minimal reader for the COFF object files emitted by NativeObjFileWriterCoff. It decodes just the
// shape that the backend produces (sections, a flat external symbol table, and per-section
// relocations), turning relocation symbol indices into names so downstream linking can work purely
// by name. It is deliberately not a general-purpose COFF reader.

struct CoffInputReloc
{
    uint32_t offset = 0; // patch offset within the section
    Utf8     symbolName;
    uint16_t type = 0; // IMAGE_REL_AMD64_*
};

struct CoffInputSection
{
    Utf8                        name;
    uint32_t                    characteristics = 0;
    ByteArray                   bytes; // empty for an uninitialised section
    bool                        isBss   = false;
    uint32_t                    bssSize = 0;
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

// Decodes a COFF object image. Returns false and fills outDiag on a malformed/unsupported file.
bool readCoffObject(CoffObject& outObject, Diagnostic& outDiag, const ByteArray& bytes);
bool readCoffObject(CoffObject& outObject, Diagnostic& outDiag, std::span<const std::byte> bytes);

// Merges the given COFF objects into a single LinkImage: sections of the same name are concatenated
// (honouring alignment and rebasing symbols/relocations), defined symbols are collected globally, and
// CodeView debug sections (.debug$*) are dropped. Appends to outImage; the caller still fills in
// imports, exports, the entry symbol and image options. Returns false and fills outDiag on an
// unsupported relocation kind.
bool mergeCoffObjectsIntoImage(LinkImage& outImage, Diagnostic& outDiag, const std::vector<CoffObject>& objects);

SWC_END_NAMESPACE();

#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Flags.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

// Target-independent linker intermediate representation.
//
// Compiler/front-end specific code (LinkerPe::prepareLink) lowers the backend output into a
// LinkImage: a flat set of sections, symbols, relocations, imports and exports with no knowledge of
// the final container format. A target writer (the PE writer today, an ELF/Mach-O writer later)
// consumes a LinkImage and produces the final image bytes. This keeps the resolution/layout model in
// one place and isolates the per-OS object/executable encoding behind a single, small interface.

enum class LinkSectionFlagsE : uint32_t
{
    Zero      = 0,
    Code      = 1u << 0, // executable code
    Read      = 1u << 1,
    Write     = 1u << 2,
    Execute   = 1u << 3,
    Uninit    = 1u << 4, // bss: no file bytes, zero-initialised at load
    Exception = 1u << 5, // unwind function table (.pdata)
};

// Generic relocation semantics, independent of the COFF/ELF encoding it was decoded from.
enum class LinkRelocKind : uint8_t
{
    Abs64, // write the absolute 64-bit virtual address of (target + addend); needs a base relocation
    Rva32, // write the 32-bit image-relative address of (target + addend); no base relocation
};

struct LinkReloc
{
    uint32_t      sectionIndex = 0; // section whose bytes are patched (index into LinkImage::sections)
    uint32_t      offset       = 0; // byte offset of the patch site within that section
    Utf8          symbolName;       // name of the target symbol
    int64_t       addend = 0;
    LinkRelocKind kind   = LinkRelocKind::Abs64;
};

struct LinkSection
{
    Utf8                         name;
    ByteArray                    bytes;       // raw contents; empty for an uninitialised (bss) section
    uint32_t                     bssSize = 0; // size in bytes when the Uninit flag is set
    uint32_t                     align   = 16;
    EnumFlags<LinkSectionFlagsE> flags;
    std::vector<LinkReloc>       relocs;

    bool     isUninit() const { return flags.has(LinkSectionFlagsE::Uninit); }
    uint32_t virtualSize() const { return isUninit() ? bssSize : static_cast<uint32_t>(bytes.size()); }
};

// A symbol defined somewhere in the image (a function, a section base, an unwind record...).
struct LinkSymbol
{
    Utf8     name;
    uint32_t sectionIndex = 0; // section that defines it
    uint32_t value        = 0; // offset of the symbol within that section
};

// A symbol imported from a shared library, resolved at load time (by name, or by ordinal).
struct LinkImport
{
    Utf8     dll;        // owning module, e.g. "kernel32.dll"
    Utf8     importName; // exported name in that module (when byOrdinal is false)
    Utf8     symbolName; // the undefined symbol that other sections reference
    uint16_t ordinal   = 0;
    bool     byOrdinal = false;
    bool     isData    = false;
};

// A symbol exported from this image (shared-library output only).
struct LinkExport
{
    Utf8 name;       // exported name
    Utf8 symbolName; // the defined symbol it maps to
};

// A prepared object member for static archive output. The backend still gives it a stable object-like
// name for debug records and archive member headers, but the linker owns the bytes directly.
struct LinkArchiveMember
{
    Utf8      name;
    ByteArray bytes;
};

enum class LinkImageKind : uint8_t
{
    Executable,
    SharedLibrary,
};

enum class LinkWin32Subsystem : uint8_t
{
    Console,
    Windows,
};

struct LinkWin32ApplicationConfig
{
    Utf8               iconPath;
    ByteArray          iconBytes;
    Utf8               appName;
    Utf8               appDescription;
    Utf8               appCompany;
    Utf8               appCopyright;
    uint32_t           version   = 0;
    uint32_t           revision  = 0;
    uint32_t           buildNum  = 0;
    LinkWin32Subsystem subsystem = LinkWin32Subsystem::Console;

    bool hasIcon() const { return !iconBytes.empty(); }
    bool hasVersionInfo() const { return version != 0 || revision != 0 || buildNum != 0 || !appName.empty() || !appDescription.empty() || !appCompany.empty() || !appCopyright.empty(); }
};

struct LinkImage
{
    std::vector<LinkSection> sections;
    std::vector<LinkSymbol>  symbols;
    std::vector<LinkImport>  imports;
    std::vector<LinkExport>  exports;

    Utf8                       entrySymbol;
    Utf8                       moduleName; // output file name, used for the export directory of a shared library
    LinkImageKind              kind         = LinkImageKind::Executable;
    uint64_t                   imageBase    = 0;
    uint64_t                   stackReserve = 0;
    uint64_t                   stackCommit  = 0;
    LinkWin32ApplicationConfig win32;
};

SWC_END_NAMESPACE();

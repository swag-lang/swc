#pragma once
#include "Support/Core/ByteSpan.h"

SWC_BEGIN_NAMESPACE();

// Reader for Windows COFF archives (`!<arch>`), covering both static libraries (members are COFF
// objects) and import libraries (members are "short import" records describing a DLL export). Only
// the first linker member (the symbol -> member index) is decoded; that is all symbol resolution
// needs. Members are pulled on demand by the linker.

struct ArchiveImport
{
    Utf8     dll;
    Utf8     importName;
    uint16_t ordinal   = 0;
    bool     byOrdinal = false;
    bool     isData    = false;
};

class Archive
{
public:
    // Takes ownership of the archive bytes. Returns false and fills outError on a malformed archive.
    bool load(std::vector<std::byte> bytes, Utf8& outError);

    // Returns the file offset of the member header defining the given symbol, or 0 if this archive
    // does not provide it (0 is never a valid member offset because the magic occupies offset 0).
    uint32_t memberOffsetForSymbol(const Utf8& symbol) const;

    // Returns the raw member contents at the given member-header offset.
    ByteSpan memberData(uint32_t headerOffset, Utf8& outError) const;

    // If the member at the given offset is a short-import record, decodes it and returns true.
    bool tryReadImport(uint32_t headerOffset, ArchiveImport& outImport, Utf8& outError) const;

private:
    std::vector<std::byte>             bytes_;
    std::unordered_map<Utf8, uint32_t> symbolToMember_;
};

// Builds a COFF static library (`!<arch>`) from the given object files: a symbol-directory linker
// member, a long-names member, and the object members. Returns false and fills outError on failure.
bool buildStaticArchive(const std::vector<fs::path>& memberPaths, std::vector<std::byte>& outBytes, Utf8& outError);

// Builds an import library: a COFF archive of short-import records, one per exported name, so a
// dependent link resolves those names as by-name imports from the given DLL file.
bool buildImportLibrary(std::string_view dllFileName, const std::vector<Utf8>& exportNames, std::vector<std::byte>& outBytes, Utf8& outError);

SWC_END_NAMESPACE();

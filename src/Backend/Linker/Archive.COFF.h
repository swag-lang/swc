#pragma once
#include "Backend/Linker/Archive.h"

SWC_BEGIN_NAMESPACE();

struct ArchiveImport
{
    Utf8     dll;
    Utf8     importName;
    uint16_t ordinal   = 0;
    bool     byOrdinal = false;
    bool     isData    = false;
};

// If the member at the given offset is a COFF short-import record, decode it.
bool tryReadCoffImport(ArchiveImport& outImport, Diagnostic& outDiag, const Archive& archive, uint32_t headerOffset);

// Decode a COFF short-import record from bytes already returned by Archive::memberData().
bool tryReadCoffImport(ArchiveImport& outImport, std::span<const std::byte> data);

// Builds a COFF static library (`!<arch>`) from prepared object members: both linker directories,
// an optional long-names member, and the object members. Returns false and fills outDiag on failure.
bool buildCoffStaticArchive(ByteArray& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& inputMembers);

// Builds an import library: a COFF archive of short-import records, one per exported name, so a
// dependent link resolves those names as by-name imports from the given DLL file. Returns false
// and fills outDiag when the member count exceeds the COFF directory limit.
bool buildCoffImportLibrary(ByteArray& outBytes, Diagnostic& outDiag, std::string_view dllFileName, const std::vector<Utf8>& exportNames);

SWC_END_NAMESPACE();

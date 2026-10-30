#pragma once

#include "Backend/Linker/LinkImage.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/StringMap.h"
#include "Support/Core/Utf8.h"
#include "Support/Os/ReadOnlyFileMapping.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

struct ArchiveImport
{
    Utf8     dll;
    Utf8     importName;
    uint16_t ordinal   = 0;
    bool     byOrdinal = false;
    bool     isData    = false;
};

// Reads COFF static and import libraries. Symbol lookup decodes only the first
// linker member; the linker then loads the referenced members on demand.
class Archive
{
public:
    Archive()                          = default;
    Archive(const Archive&)            = delete;
    Archive& operator=(const Archive&) = delete;
    Archive(Archive&& other) noexcept;
    Archive& operator=(Archive&& other) noexcept;

    // Takes ownership of the archive bytes. Returns false and fills outDiag on a malformed archive.
    bool load(Diagnostic& outDiag, ByteArray bytes);

    // Map immutable file bytes, falling back to an owned read if mapping is unavailable.
    // A read failure leaves the previous archive intact; malformed bytes fill outDiag.
    bool loadFile(Diagnostic& outDiag, const fs::path& path);

    // Returns the file offset of the member header defining the given symbol, or 0 if this archive
    // does not provide it (0 is never a valid member offset because the magic occupies offset 0).
    uint32_t memberOffsetForSymbol(const Utf8& symbol) const;

    // Returns the raw member contents at the given member-header offset.
    std::span<const std::byte> memberData(Diagnostic& outDiag, uint32_t headerOffset) const;

    // If the member at the given offset is a short-import record, decodes it and returns true.
    bool tryReadImport(ArchiveImport& outImport, Diagnostic& outDiag, uint32_t headerOffset) const;

    // Decodes a short-import record from member bytes already returned by memberData().
    bool tryReadImport(ArchiveImport& outImport, std::span<const std::byte> data) const;

    // The file the archive was read from. The debug records of its members are grouped under it.
    const fs::path& sourcePath() const { return sourcePath_; }
    void            setSourcePath(fs::path path) { sourcePath_ = std::move(path); }

private:
    bool decode(Diagnostic& outDiag);

    // Symbol names borrow bytes_, so the index must move with its immutable buffer.
    // A flat table avoids per-symbol allocations for large import libraries.
    ByteArray                                ownedBytes_;
    std::unique_ptr<Os::ReadOnlyFileMapping> mapping_;
    ByteView                                 bytes_;
    StringMap<uint32_t>                      symbolToMember_;
    fs::path                                 sourcePath_;
};

// Builds a COFF static library (`!<arch>`) from prepared object members: both linker directories,
// an optional long-names member, and the object members. Returns false and fills outDiag on failure.
bool buildCoffStaticArchive(ByteArray& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& inputMembers);

// Builds an import library: a COFF archive of short-import records, one per exported name, so a
// dependent link resolves those names as by-name imports from the given DLL file. Returns false
// and fills outDiag when the member count exceeds the COFF directory limit.
bool buildCoffImportLibrary(ByteArray& outBytes, Diagnostic& outDiag, std::string_view dllFileName, const std::vector<Utf8>& exportNames);

SWC_END_NAMESPACE();

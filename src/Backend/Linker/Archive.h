#pragma once

#include "Backend/Linker/LinkImage.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/StringMap.h"
#include "Support/Core/Utf8.h"
#include "Support/Os/ReadOnlyFileMapping.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// Reads GNU/COFF static archives and COFF import libraries with 32-bit indexes.
// Symbol lookup decodes only the first linker member; referenced objects are loaded on demand.
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

    // ELF COMMON definitions can be superseded by a strong definition in a later member.
    // Return every matching directory entry without changing first-definition COFF lookup.
    std::vector<uint32_t> memberOffsetsForSymbol(const Utf8& symbol) const;

    // Returns the raw member contents at the given member-header offset.
    std::span<const std::byte> memberData(Diagnostic& outDiag, uint32_t headerOffset) const;

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

SWC_END_NAMESPACE();

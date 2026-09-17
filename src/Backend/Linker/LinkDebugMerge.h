#pragma once
#include "Backend/Linker/CoffReader.h"
#include "Backend/Linker/LinkDebugInfo.h"

SWC_BEGIN_NAMESPACE();

// Carries the CodeView of the archive members an image pulls in over to that image's PDB.
//
// An executable takes its dependencies' code from their static archives, and each member brings
// the debug records its own compilation wrote. Those records name types by the member's private
// indices, and every member repeats the types it uses, so each member is renumbered into the
// image's type stream, where one copy of every identical record is kept.
//
// Only type records travel. A member's id records (function ids, build information) describe that
// member alone, and the PDB writer produces its own per compiland; a function id is read only for
// the procedure type it names.
//
// Members are grouped into one compiland per archive. An archive holds one object per function, and
// one compiland each would grow the PDB module table with the size of the library.
class LinkDebugMerger
{
public:
    explicit LinkDebugMerger(LinkDebugInfo& debugInfo);

    // Appends the debug records of one pulled member to the compiland named after its archive.
    // Returns false when the member's type records cannot be read; nothing of that member is kept.
    bool appendObject(const CoffObject& object, const Utf8& compilandName);

private:
    struct ObjectTypes;
    struct ObjectSymbols;

    bool     mergeTypes(ObjectTypes& outTypes, std::span<const std::byte> section);
    void     commitTypes(ObjectTypes& types);
    void     mergeSymbols(ObjectSymbols& symbols, const ObjectTypes& types);
    void     mergeSymbolRecords(ObjectSymbols& symbols, const ObjectTypes& types, std::span<const std::byte> records, uint32_t sectionOffset);
    void     mergeLines(ObjectSymbols& symbols, std::span<const std::byte> lines, uint32_t sectionOffset);
    uint32_t imageFileIndex(ObjectSymbols& symbols, uint32_t checksumOffset);
    uint32_t compilandIndex(const Utf8& name);

    LinkDebugInfo*                            debugInfo_ = nullptr;
    std::unordered_map<std::string, uint32_t> typeIndices_;
    std::unordered_map<Utf8, uint32_t>        fileIndices_;
    std::unordered_map<Utf8, uint32_t>        compilands_;
    std::set<std::pair<Utf8, uint32_t>>       udts_;
};

SWC_END_NAMESPACE();

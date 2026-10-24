#include "pch.h"
#include "Backend/Debug/SymbolTable.h"
#include "Backend/BinaryPatch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/StringMap.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_ENTRY_SIZE     = 4;
    constexpr uint32_t K_ENTRY_NAME     = 8;
    constexpr uint32_t K_ENTRY_FILE     = 12;
    constexpr uint32_t K_ENTRY_LINE     = 16;
    constexpr uint32_t K_HEADER_VERSION = 4;
    constexpr uint32_t K_HEADER_COUNT   = 8;
    constexpr uint32_t K_HEADER_STRINGS = 12;

    struct StringBlob
    {
        uint32_t insert(const std::string_view value)
        {
            if (value.empty())
                return 0;
            const auto [offset, inserted] = offsets.try_emplace(value, Math::hash(value), base + static_cast<uint32_t>(bytes.size()));
            if (inserted)
                bytes.appendCString(value);
            return *offset;
        }

        uint32_t  base = 0;
        ByteArray bytes;
        // build keeps the source entries alive and unchanged until this map is destroyed.
        StringMap<uint32_t> offsets;
    };

    Utf8 readString(const std::span<const std::byte> bytes, const uint32_t offset)
    {
        if (!offset || offset >= bytes.size())
            return {};
        const auto* begin = reinterpret_cast<const char*>(bytes.data() + offset);
        return Utf8(std::string_view{begin, strnlen(begin, bytes.size() - offset)});
    }
}

bool SymbolTable::makeEntry(Entry& outEntry, const TaskContext& ctx, const NativeFunctionInfo& info)
{
    outEntry = {};
    if (!info.machineCode)
        return false;

    // The runtime names its stack frames from this table in every configuration, so the scoped
    // name is computed here when debug information did not already record it.
    outEntry.symbolName = info.symbolName;
    if (!info.debugName.empty())
        outEntry.name = info.debugName;
    else if (info.symbol)
        outEntry.name = info.symbol->getFullScopedName(ctx);
    else
        outEntry.name = info.symbolName;
    outEntry.size = static_cast<uint32_t>(info.machineCode->bytes.size());

    MachineCode::ResolvedDebugSourceRange resolved;
    if (info.machineCode->tryResolveDebugSourceRangeAtOffset(ctx, resolved, 0) && resolved.source.sourceFile)
    {
        outEntry.file = resolved.source.sourceFile->genericPathString();
        outEntry.line = resolved.source.codeRange.line;
    }

    return true;
}

namespace
{
    void buildSymbolTable(ByteArray& outBytes, std::vector<SymbolTable::Relocation>* outRelocations, const std::span<const SymbolTable::Entry> entries)
    {
        outBytes.clear();
        if (outRelocations)
            outRelocations->clear();
        if (entries.empty())
            return;

        StringBlob strings;
        strings.base = SymbolTable::HEADER_SIZE + static_cast<uint32_t>(entries.size()) * SymbolTable::ENTRY_SIZE;

        outBytes.appendLe32(SymbolTable::MAGIC);
        outBytes.appendLe32(SymbolTable::VERSION_PLAIN);
        outBytes.appendLe32(static_cast<uint32_t>(entries.size()));
        outBytes.appendLe32(strings.base);

        if (outRelocations)
            outRelocations->reserve(entries.size());
        for (const SymbolTable::Entry& entry : entries)
        {
            const uint32_t nameOffset = strings.insert(entry.name.view());
            const uint32_t fileOffset = strings.insert(entry.file.view());

            if (outRelocations)
                outRelocations->push_back({.offset = static_cast<uint32_t>(outBytes.size()) + SymbolTable::ENTRY_START_RVA, .symbolName = entry.symbolName});
            outBytes.appendLe32(0);
            outBytes.appendLe32(entry.size);
            outBytes.appendLe32(nameOffset);
            outBytes.appendLe32(fileOffset);
            outBytes.appendLe32(entry.line);
        }

        outBytes.append(strings.bytes);
    }
}

void SymbolTable::build(ByteArray& outBytes, std::vector<Relocation>& outRelocations, const std::span<const Entry> entries)
{
    buildSymbolTable(outBytes, &outRelocations, entries);
}

void SymbolTable::build(ByteArray& outBytes, const std::span<const Entry> entries)
{
    buildSymbolTable(outBytes, nullptr, entries);
}

bool SymbolTable::read(std::vector<Entry>& outEntries, const std::span<const std::byte> bytes, const std::span<const Relocation> relocations)
{
    if (bytes.size() < HEADER_SIZE || BinaryPatch::readU32(bytes, 0) != MAGIC || BinaryPatch::readU32(bytes, K_HEADER_VERSION) != VERSION_PLAIN)
        return false;

    const uint32_t count    = BinaryPatch::readU32(bytes, K_HEADER_COUNT);
    const uint32_t blobBase = BinaryPatch::readU32(bytes, K_HEADER_STRINGS);
    if (HEADER_SIZE + static_cast<uint64_t>(count) * ENTRY_SIZE > blobBase || blobBase > bytes.size())
        return false;

    // Only looked up by entry offset: one flat table instead of a node per relocation.
    FlatKeyMap<const Utf8*> targets;
    targets.reserve(relocations.size());
    for (const Relocation& relocation : relocations)
        targets.emplace(relocation.offset, &relocation.symbolName);

    std::vector<Entry> entries;
    entries.reserve(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        const uint32_t     entryOffset = HEADER_SIZE + i * ENTRY_SIZE;
        const Utf8* const* target      = targets.find(entryOffset + ENTRY_START_RVA);
        if (!target)
            return false;

        Entry entry;
        entry.symbolName = **target;
        entry.size       = BinaryPatch::readU32(bytes, entryOffset + K_ENTRY_SIZE);
        entry.name       = readString(bytes, BinaryPatch::readU32(bytes, entryOffset + K_ENTRY_NAME));
        entry.file       = readString(bytes, BinaryPatch::readU32(bytes, entryOffset + K_ENTRY_FILE));
        entry.line       = BinaryPatch::readU32(bytes, entryOffset + K_ENTRY_LINE);
        entries.push_back(std::move(entry));
    }

    outEntries.insert(outEntries.end(), std::make_move_iterator(entries.begin()), std::make_move_iterator(entries.end()));
    return true;
}

SWC_END_NAMESPACE();

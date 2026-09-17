#include "pch.h"
#include "Backend/Debug/SymbolTable.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/SourceFile.h"

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
        uint32_t insert(const Utf8& value)
        {
            if (value.empty())
                return 0;
            const auto it = offsets.find(value);
            if (it != offsets.end())
                return it->second;

            const uint32_t offset = base + static_cast<uint32_t>(bytes.size());
            offsets.emplace(value, offset);
            bytes.appendCString(value.view());
            return offset;
        }

        uint32_t                           base = 0;
        ByteArray                          bytes;
        std::unordered_map<Utf8, uint32_t> offsets;
    };

    uint32_t readU32(const std::span<const std::byte> bytes, const size_t offset)
    {
        uint32_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

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

    outEntry.symbolName = info.symbolName;
    outEntry.name       = info.debugName.empty() ? info.symbolName : info.debugName;
    outEntry.size       = static_cast<uint32_t>(info.machineCode->bytes.size());

    MachineCode::ResolvedDebugSourceRange resolved;
    if (info.machineCode->tryResolveDebugSourceRangeAtOffset(ctx, resolved, 0) && resolved.source.sourceFile)
    {
        outEntry.file = Utf8(resolved.source.sourceFile->path());
        outEntry.line = resolved.source.codeRange.line;
    }

    return true;
}

void SymbolTable::build(ByteArray& outBytes, std::vector<Relocation>& outRelocations, const std::span<const Entry> entries)
{
    outBytes.clear();
    outRelocations.clear();
    if (entries.empty())
        return;

    StringBlob strings;
    strings.base = HEADER_SIZE + static_cast<uint32_t>(entries.size()) * ENTRY_SIZE;

    outBytes.appendLe32(MAGIC);
    outBytes.appendLe32(VERSION_PLAIN);
    outBytes.appendLe32(static_cast<uint32_t>(entries.size()));
    outBytes.appendLe32(strings.base);

    outRelocations.reserve(entries.size());
    for (const Entry& entry : entries)
    {
        const uint32_t nameOffset = strings.insert(entry.name);
        const uint32_t fileOffset = strings.insert(entry.file);

        outRelocations.push_back({.offset = static_cast<uint32_t>(outBytes.size()) + ENTRY_START_RVA, .symbolName = entry.symbolName});
        outBytes.appendLe32(0);
        outBytes.appendLe32(entry.size);
        outBytes.appendLe32(nameOffset);
        outBytes.appendLe32(fileOffset);
        outBytes.appendLe32(entry.line);
    }

    outBytes.append(strings.bytes);
}

bool SymbolTable::read(std::vector<Entry>& outEntries, const std::span<const std::byte> bytes, const std::span<const Relocation> relocations)
{
    if (bytes.size() < HEADER_SIZE || readU32(bytes, 0) != MAGIC || readU32(bytes, K_HEADER_VERSION) != VERSION_PLAIN)
        return false;

    const uint32_t count    = readU32(bytes, K_HEADER_COUNT);
    const uint32_t blobBase = readU32(bytes, K_HEADER_STRINGS);
    if (HEADER_SIZE + static_cast<uint64_t>(count) * ENTRY_SIZE > blobBase || blobBase > bytes.size())
        return false;

    std::unordered_map<uint32_t, const Utf8*> targets;
    targets.reserve(relocations.size());
    for (const Relocation& relocation : relocations)
        targets.emplace(relocation.offset, &relocation.symbolName);

    std::vector<Entry> entries;
    entries.reserve(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        const uint32_t entryOffset = HEADER_SIZE + i * ENTRY_SIZE;
        const auto     target      = targets.find(entryOffset + ENTRY_START_RVA);
        if (target == targets.end())
            return false;

        Entry entry;
        entry.symbolName = *target->second;
        entry.size       = readU32(bytes, entryOffset + K_ENTRY_SIZE);
        entry.name       = readString(bytes, readU32(bytes, entryOffset + K_ENTRY_NAME));
        entry.file       = readString(bytes, readU32(bytes, entryOffset + K_ENTRY_FILE));
        entry.line       = readU32(bytes, entryOffset + K_ENTRY_LINE);
        entries.push_back(std::move(entry));
    }

    outEntries.insert(outEntries.end(), std::make_move_iterator(entries.begin()), std::make_move_iterator(entries.end()));
    return true;
}

SWC_END_NAMESPACE();

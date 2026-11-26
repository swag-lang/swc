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

    void appendLz4Length(ByteArray& bytes, size_t length)
    {
        while (length >= 255)
        {
            bytes.pushBack(std::byte{255});
            length -= 255;
        }
        bytes.pushBack(static_cast<std::byte>(length));
    }

    void appendLz4Sequence(ByteArray& bytes, std::span<const std::byte> literals, uint16_t distance, size_t matchSize)
    {
        constexpr size_t inlineLength = 15;
        const size_t     matchLength  = distance ? matchSize - 4 : 0;
        bytes.pushBack(static_cast<std::byte>((std::min(literals.size(), inlineLength) << 4) | std::min(matchLength, inlineLength)));
        if (literals.size() >= inlineLength)
            appendLz4Length(bytes, literals.size() - inlineLength);
        bytes.append(literals);
        if (!distance)
            return;
        bytes.appendLe16(distance);
        if (matchLength >= inlineLength)
            appendLz4Length(bytes, matchLength - inlineLength);
    }

    void appendLz4Block(ByteArray& packed, const std::span<const std::byte> bytes)
    {
        if (bytes.size() < 12)
        {
            appendLz4Sequence(packed, bytes, 0, 0);
            return;
        }
        constexpr size_t      hashBits = 16;
        std::vector<uint32_t> last(1 << hashBits, UINT32_MAX);
        size_t                literalStart = 0;
        size_t                cursor       = 0;
        // LZ4 leaves at least five trailing literals, and the last match starts
        // at least twelve bytes before the end of the block.
        const size_t matchLimit = bytes.size() - 5;
        const auto readWord = [&](const size_t offset) {
            uint32_t word;
            std::memcpy(&word, bytes.data() + offset, sizeof(word));
            if constexpr (std::endian::native == std::endian::big)
                word = std::byteswap(word);
            return word;
        };
        while (cursor + 12 <= bytes.size())
        {
            const uint32_t word     = readWord(cursor);
            const uint32_t hash     = (word * 2654435761u) >> (32 - hashBits);
            const uint32_t previous = std::exchange(last[hash], static_cast<uint32_t>(cursor));
            if (previous == UINT32_MAX || cursor - previous > UINT16_MAX || readWord(previous) != word)
            {
                ++cursor;
                continue;
            }
            const size_t maxLength = matchLimit - cursor;
            const auto*  match     = bytes.data() + cursor;
            const auto*  candidate = bytes.data() + previous;
            size_t       length    = 4;
            while (length + sizeof(uint64_t) <= maxLength &&
                   std::memcmp(match + length, candidate + length, sizeof(uint64_t)) == 0)
                length += sizeof(uint64_t);
            while (length < maxLength && match[length] == candidate[length])
                ++length;
            appendLz4Sequence(packed, bytes.subspan(literalStart, cursor - literalStart), static_cast<uint16_t>(cursor - previous), length);
            cursor += length;
            literalStart = cursor;
        }
        appendLz4Sequence(packed, bytes.subspan(literalStart), 0, 0);
    }

    void appendVarUInt(ByteArray& bytes, uint32_t value)
    {
        while (value >= 128)
        {
            bytes.pushBack(static_cast<std::byte>((value & 127) | 128));
            value >>= 7;
        }
        bytes.pushBack(static_cast<std::byte>(value));
    }

    ByteArray compactStackEntries(uint32_t& count, const ByteArray& table)
    {
        count = table.readLe32(K_HEADER_COUNT);
        if (!count || count > (table.size() - SymbolTable::HEADER_SIZE) / SymbolTable::ENTRY_SIZE)
            return {};
        const size_t stringsOffset = SymbolTable::HEADER_SIZE + static_cast<size_t>(count) * SymbolTable::ENTRY_SIZE;
        if (table.readLe32(K_HEADER_STRINGS) != stringsOffset)
            return {};

        constexpr size_t             fieldSize = sizeof(uint32_t);
        constexpr size_t             fields    = SymbolTable::ENTRY_SIZE / fieldSize;
        std::array<uint32_t, fields> previous{};
        ByteArray                    compact;
        compact.reserve(table.size());
        for (size_t entry = SymbolTable::HEADER_SIZE; entry < stringsOffset; entry += SymbolTable::ENTRY_SIZE)
        {
            const size_t start = compact.size();
            for (size_t field = 0; field < fields; ++field)
            {
                const size_t offset = field * fieldSize;
                uint32_t     value  = table.readLe32(entry + offset);
                if (offset != K_ENTRY_SIZE)
                {
                    const uint32_t delta = value - previous[field];
                    previous[field] = value;
                    value = (delta << 1) ^ (0u - (delta >> 31));
                }
                appendVarUInt(compact, value);
            }

            // Expansion reads each row before writing the row to its final position.
            if (compact.size() - start > SymbolTable::ENTRY_SIZE)
                return {};
        }
        compact.append(table.span().subspan(stringsOffset));
        return compact;
    }

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

ByteArray SymbolTable::packRuntimeSymbols(const ByteArray& table)
{
    // Small tables do not amortize the header and match dictionary.
    if (table.size() < 256 || table.size() > UINT32_MAX)
        return {};

    ByteArray packed;
    packed.appendLe32(MAGIC);
    packed.appendLe32(VERSION_LZ4);
    packed.appendLe32(static_cast<uint32_t>(table.size()));
    packed.appendLe32(0);
    appendLz4Block(packed, table.span());

    uint32_t count = 0;
    const ByteArray compact = compactStackEntries(count, table);
    if (!compact.empty())
    {
        ByteArray candidate;
        candidate.appendLe32(MAGIC);
        candidate.appendLe32(VERSION_COMPACT_LZ4);
        candidate.appendLe32(static_cast<uint32_t>(table.size()));
        candidate.appendLe32(0);
        candidate.appendLe32(static_cast<uint32_t>(compact.size()));
        candidate.appendLe32(count);
        appendLz4Block(candidate, compact.span());
        if (candidate.size() < table.size() && candidate.size() < packed.size())
        {
            candidate.writeLe32(12, static_cast<uint32_t>(candidate.size() - COMPACT_HEADER_SIZE));
            return candidate;
        }
    }

    if (packed.size() >= table.size())
        return {};
    packed.writeLe32(12, static_cast<uint32_t>(packed.size() - HEADER_SIZE));
    return packed;
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

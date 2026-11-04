#include "pch.h"
#include "Backend/Linker/ELFSymbolTable.h"
#include "Backend/Linker/LinkImage.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // This is an object-only envelope. Published images use SymbolTable::VERSION_PLAIN,
    // shared with PE and the runtime; no platform parser leaks into that format.
    constexpr uint32_t K_OBJECT_VERSION     = 3;
    constexpr uint32_t K_OBJECT_HEADER_SIZE = 24;
    constexpr uint32_t K_OBJECT_ENTRY_SIZE  = 24;
    constexpr uint64_t K_ELF_HEADER_SIZE    = 64;
    constexpr uint64_t K_ELF_SECTION_SIZE   = 64;
    constexpr uint64_t K_ELF_PROGRAM_SIZE   = 56;
    constexpr uint64_t K_TARGET_PAGE_SIZE   = 4096;

    struct TableSection
    {
        uint64_t header = 0;
        uint64_t offset = 0;
        uint64_t size   = 0;
    };

    bool tableError(Utf8& error, std::string_view reason)
    {
        error = reason;
        return false;
    }

    bool findTable(TableSection& outSection, Utf8& error, const ByteArray& image)
    {
        if (image.size() < K_ELF_HEADER_SIZE || image.readLe32(0) != 0x464c457f ||
            image[4] != std::byte{2} || image[5] != std::byte{1} || image[6] != std::byte{1} ||
            (image.readLe16(16) != 2 && image.readLe16(16) != 3) || image.readLe16(18) != 62 ||
            image.readLe32(20) != 1 || image.readLe16(52) != K_ELF_HEADER_SIZE)
            return tableError(error, "runtime symbols need an ELF64 x86-64 image");

        const uint64_t headers    = image.readLe64(40);
        const uint16_t count      = image.readLe16(60);
        const uint16_t namesIndex = image.readLe16(62);
        // A stripped image can omit its section table entirely.
        if (!headers && !count)
            return true;
        if (!count || image.readLe16(58) != K_ELF_SECTION_SIZE || namesIndex >= count ||
            !image.containsRange(headers, static_cast<uint64_t>(count) * K_ELF_SECTION_SIZE))
            return tableError(error, "the ELF section table is invalid");

        // SHN_UNDEF means the image has no section names to locate a debug table.
        if (!namesIndex)
            return true;

        const uint64_t namesHeader = headers + static_cast<uint64_t>(namesIndex) * K_ELF_SECTION_SIZE;
        const uint64_t namesOffset = image.readLe64(namesHeader + 24);
        const uint64_t namesSize   = image.readLe64(namesHeader + 32);
        if (image.readLe32(namesHeader + 4) != 3 || !image.containsRange(namesOffset, namesSize))
            return tableError(error, "the ELF section-name table is invalid");
        for (uint32_t index = 1; index < count; ++index)
        {
            const uint64_t header     = headers + index * K_ELF_SECTION_SIZE;
            const uint32_t nameOffset = image.readLe32(header);
            if (nameOffset >= namesSize)
                return tableError(error, "an ELF section name is outside its table");
            const char* name = reinterpret_cast<const char*>(image.data() + namesOffset + nameOffset);
            const char* end  = static_cast<const char*>(std::memchr(name, 0, namesSize - nameOffset));
            if (!end)
                return tableError(error, "an ELF section name is not terminated");
            if (std::string_view(name, end) != SymbolTable::IMAGE_SECTION)
                continue;
            if (outSection.header)
                return tableError(error, "the ELF image has more than one runtime symbol section");
            outSection = {.header = header, .offset = image.readLe64(header + 24), .size = image.readLe64(header + 32)};
            if (image.readLe32(header + 4) != 1 || image.readLe64(header + 8) != 0 ||
                outSection.size > UINT32_MAX || !image.containsRange(outSection.offset, outSection.size))
                return tableError(error, "the ELF runtime symbol section is invalid");
        }
        return true;
    }

    bool imageBase(uint64_t& outBase, Utf8& error, const ByteArray& image)
    {
        const uint64_t headers = image.readLe64(32);
        const uint16_t count   = image.readLe16(56);
        if (!count || image.readLe16(54) != K_ELF_PROGRAM_SIZE ||
            !image.containsRange(headers, static_cast<uint64_t>(count) * K_ELF_PROGRAM_SIZE))
            return tableError(error, "the ELF program table is invalid");
        outBase = UINT64_MAX;
        for (uint32_t index = 0; index < count; ++index)
        {
            const uint64_t header = headers + index * K_ELF_PROGRAM_SIZE;
            if (image.readLe32(header) != 1)
                continue;
            const uint64_t offset     = image.readLe64(header + 8);
            const uint64_t address    = image.readLe64(header + 16);
            const uint64_t fileSize   = image.readLe64(header + 32);
            const uint64_t memorySize = image.readLe64(header + 40);
            const uint64_t alignment  = std::max<uint64_t>(1, image.readLe64(header + 48));
            if (!std::has_single_bit(alignment) || memorySize < fileSize || address > UINT64_MAX - memorySize ||
                !image.containsRange(offset, fileSize) || address % alignment != offset % alignment)
                return tableError(error, "an ELF load segment is invalid");
            // dladdr's image base denotes the first mapped segment, not necessarily
            // zero: ET_EXEC normally begins at 0x400000, while ET_DYN is relocated.
            // Linux x86-64 maps ordinary segments on 4 KiB pages; p_align can be
            // smaller or larger and does not define the loader's mapping boundary.
            outBase = std::min(outBase, address & ~(K_TARGET_PAGE_SIZE - 1));
        }
        if (outBase == UINT64_MAX)
            return tableError(error, "the ELF image has no load segment");
        return true;
    }

    bool readString(Utf8& out, const ByteArray& image, uint64_t contribution, uint64_t size, uint32_t strings, uint32_t offset)
    {
        if (!offset)
            return true;
        if (offset < strings || offset >= size)
            return false;
        const char* begin = reinterpret_cast<const char*>(image.data() + contribution + offset);
        const char* end   = static_cast<const char*>(std::memchr(begin, 0, size - offset));
        if (!end)
            return false;
        out = std::string_view(begin, end);
        return true;
    }

    bool readContributions(std::vector<SymbolTable::Entry>& entries, std::vector<uint32_t>& addresses, Utf8& error, const ByteArray& image, const TableSection& section, uint64_t base)
    {
        uint64_t cursor = 0;
        while (cursor < section.size)
        {
            if (section.size - cursor < K_OBJECT_HEADER_SIZE)
                return tableError(error, "an ELF runtime symbol contribution is truncated");
            const uint64_t contribution = section.offset + cursor;
            if (image.readLe32(contribution) != SymbolTable::MAGIC || image.readLe32(contribution + 4) != K_OBJECT_VERSION)
                return tableError(error, "an ELF runtime symbol contribution has an unsupported format");
            const uint32_t count   = image.readLe32(contribution + 8);
            const uint32_t strings = image.readLe32(contribution + 12);
            const uint64_t size    = image.readLe64(contribution + 16);
            if (size < K_OBJECT_HEADER_SIZE || size > section.size - cursor ||
                strings != K_OBJECT_HEADER_SIZE + static_cast<uint64_t>(count) * K_OBJECT_ENTRY_SIZE || strings > size ||
                count > (UINT32_MAX - SymbolTable::HEADER_SIZE) / SymbolTable::ENTRY_SIZE - entries.size())
                return tableError(error, "an ELF runtime symbol contribution has invalid bounds");
            for (uint32_t index = 0; index < count; ++index)
            {
                const uint64_t     entry   = contribution + K_OBJECT_HEADER_SIZE + static_cast<uint64_t>(index) * K_OBJECT_ENTRY_SIZE;
                const uint64_t     address = image.readLe64(entry);
                SymbolTable::Entry symbol;
                symbol.size = image.readLe32(entry + 8);
                symbol.line = image.readLe32(entry + 20);
                if (address < base || address - base > UINT32_MAX || symbol.size > UINT32_MAX - (address - base))
                    return tableError(error, "an ELF runtime symbol is outside the image-relative address range");
                if (!readString(symbol.name, image, contribution, size, strings, image.readLe32(entry + 12)) ||
                    !readString(symbol.file, image, contribution, size, strings, image.readLe32(entry + 16)))
                    return tableError(error, "an ELF runtime symbol string is outside its contribution");
                addresses.push_back(static_cast<uint32_t>(address - base));
                entries.push_back(std::move(symbol));
            }
            cursor += size;
            if (cursor == section.size)
                break;
            // GNU ld aligns each input contribution to the section's eight-byte boundary.
            const uint64_t padding = (8 - cursor % 8) % 8;
            if (padding > section.size - cursor)
                return tableError(error, "an ELF runtime symbol contribution has truncated padding");
            for (uint64_t index = 0; index < padding; ++index)
                if (image[section.offset + cursor + index] != std::byte{0})
                    return tableError(error, "an ELF runtime symbol contribution has invalid padding");
            cursor += padding;
        }
        return true;
    }
}

void ELFSymbolTable::appendObject(LinkImage& image, const std::span<const SymbolTable::Entry> entries)
{
    if (entries.empty())
        return;
    ByteArray plain;
    SymbolTable::build(plain, entries);
    const uint32_t plainStrings = plain.readLe32(12);
    const uint64_t extra        = K_OBJECT_HEADER_SIZE - SymbolTable::HEADER_SIZE + entries.size() * (K_OBJECT_ENTRY_SIZE - SymbolTable::ENTRY_SIZE);
    SWC_ASSERT(plain.size() + extra <= UINT32_MAX);
    const auto  delta = static_cast<uint32_t>(extra);
    LinkSection section;
    section.name  = Utf8(SymbolTable::IMAGE_SECTION);
    section.align = 8;
    section.flags = LinkSectionFlagsE::Debug;
    section.bytes.appendLe32(SymbolTable::MAGIC);
    section.bytes.appendLe32(K_OBJECT_VERSION);
    section.bytes.appendLe32(static_cast<uint32_t>(entries.size()));
    section.bytes.appendLe32(plainStrings + delta);
    section.bytes.appendLe64(plain.size() + delta);
    section.relocs.reserve(entries.size());
    for (size_t index = 0; index < entries.size(); ++index)
    {
        const uint32_t offset = SymbolTable::HEADER_SIZE + static_cast<uint32_t>(index) * SymbolTable::ENTRY_SIZE;
        section.relocs.push_back({.offset = static_cast<uint32_t>(section.bytes.size()), .kind = LinkRelocKind::Abs64, .symbolName = entries[index].symbolName});
#if SWC_DEBUG_MODE
        section.relocs.back().sectionIndex = static_cast<uint32_t>(image.sections.size());
#endif
        section.bytes.appendLe64(0);
        section.bytes.appendLe32(plain.readLe32(offset + 4));
        for (const uint32_t field : {8u, 12u})
        {
            const uint32_t string = plain.readLe32(offset + field);
            section.bytes.appendLe32(string ? string + delta : 0);
        }
        section.bytes.appendLe32(plain.readLe32(offset + 16));
    }
    section.bytes.append(plain.span().subspan(plainStrings));
    image.sections.push_back(std::move(section));
}

bool ELFSymbolTable::finalizeImage(ByteArray& image, Utf8& outError)
{
    outError.clear();
    TableSection section;
    if (!findTable(section, outError, image))
        return false;
    if (!section.header)
        return true;
    uint64_t base;
    if (!imageBase(base, outError, image))
        return false;
    std::vector<SymbolTable::Entry> entries;
    std::vector<uint32_t>           addresses;
    if (!readContributions(entries, addresses, outError, image, section, base))
        return false;
    ByteArray table;
    SymbolTable::build(table, entries);
    if (table.size() > section.size)
        return tableError(outError, "the ELF runtime symbol table exceeds its reserved section");
    for (size_t index = 0; index < addresses.size(); ++index)
        table.writeLe32(SymbolTable::HEADER_SIZE + index * SymbolTable::ENTRY_SIZE, addresses[index]);
    std::fill_n(image.data() + section.offset, section.size, std::byte{0});
    std::memcpy(image.data() + section.offset, table.data(), table.size());
    image.writeLe64(section.header + 32, table.size());
    return true;
}

SWC_END_NAMESPACE();

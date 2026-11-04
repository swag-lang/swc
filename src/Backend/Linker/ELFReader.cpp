#include "pch.h"
#include "Backend/Linker/ELFReader.h"

SWC_BEGIN_NAMESPACE();

namespace ELF
{
    namespace
    {
        bool inputError(Utf8& error, const Utf8& name, std::string_view reason)
        {
            error = std::format("{}: {}", name, reason);
            return false;
        }
    }

    bool File::string(std::string& out, Utf8& error, const Section& strings, const uint64_t offset) const
    {
        if (offset >= strings.size || !bytes.containsRange(strings.offset, strings.size))
            return inputError(error, name, "ELF string lies outside its string table");
        const char* begin = reinterpret_cast<const char*>(bytes.data() + strings.offset + offset);
        const auto* end = static_cast<const char*>(std::memchr(begin, 0, strings.size - offset));
        if (!end)
            return inputError(error, name, "ELF string has no null terminator");
        out.assign(begin, end);
        return true;
    }

    bool File::read(Utf8& error, const std::span<const std::byte> input)
    {
        bytes = ByteView(input);
        sections.clear();
        symbols.clear();
        relocations.clear();
        needed.clear();
        soname.clear();
        if (!bytes.containsRange(0, 64) || bytes.readLe32(0) != 0x464c457f ||
            input[4] != std::byte{2} || input[5] != std::byte{1} || input[6] != std::byte{1} ||
            bytes.readLe16(18) != 62 || bytes.readLe32(20) != 1 || bytes.readLe16(52) != 64 || bytes.readLe16(58) != 64)
            return inputError(error, name, "link input needs a little-endian ELF64 x86-64 file");
        const uint16_t type = bytes.readLe16(16);
        if (type != 1 && type != 3)
            return inputError(error, name, "link input needs a relocatable object or shared library");
        shared = type == 3;
        const uint64_t table = bytes.readLe64(40);
        const uint32_t count = bytes.readLe16(60);
        const uint32_t names = bytes.readLe16(62);
        if (!count || !names || names >= count || !bytes.containsRange(table, uint64_t{count} * 64))
            return inputError(error, name, "ELF input has no complete section table");
        sections.resize(count);
        for (uint32_t index = 0; index < count; ++index)
        {
            const uint64_t header = table + uint64_t{index} * 64;
            Section& section = sections[index];
            section.type = bytes.readLe32(header + 4);
            section.flags = bytes.readLe64(header + 8);
            section.address = bytes.readLe64(header + 16);
            section.offset = bytes.readLe64(header + 24);
            section.size = bytes.readLe64(header + 32);
            section.link = bytes.readLe32(header + 40);
            section.info = bytes.readLe32(header + 44);
            section.align = std::max<uint64_t>(1, bytes.readLe64(header + 48));
            section.entrySize = bytes.readLe64(header + 56);
            if (!std::has_single_bit(section.align) ||
                (section.type != SHT_NOBITS && !bytes.containsRange(section.offset, section.size)))
                return inputError(error, name, "ELF section has unbounded contents or a non-power-of-two alignment");
        }
        if (sections[names].type != SHT_STRTAB)
            return inputError(error, name, "ELF section names need a string table");
        size_t symbolTable = 0;
        for (size_t index = 1; index < sections.size(); ++index)
        {
            Section& section = sections[index];
            if (!string(section.name, error, sections[names], bytes.readLe32(table + index * 64)))
                return false;
            if (section.type == (shared ? SHT_DYNSYM : SHT_SYMTAB))
            {
                if (symbolTable)
                    return inputError(error, name, "ELF input has more than one primary symbol table");
                symbolTable = index;
            }
        }
        if (!symbolTable)
            return inputError(error, name, "ELF input has no symbol table");
        const Section& syms = sections[symbolTable];
        if (syms.entrySize != 24 || syms.size % 24 || syms.link >= count || sections[syms.link].type != SHT_STRTAB)
            return inputError(error, name, "ELF symbols need complete ELF64 entries and a linked string table");
        symbols.resize(syms.size / 24);
        for (size_t index = 0; index < symbols.size(); ++index)
        {
            const uint64_t entry = syms.offset + index * 24;
            Symbol& symbol = symbols[index];
            if (!string(symbol.name, error, sections[syms.link], bytes.readLe32(entry)))
                return false;
            symbol.info = std::to_integer<uint8_t>(input[entry + 4]);
            symbol.visibility = std::to_integer<uint8_t>(input[entry + 5]) & 3;
            symbol.section = bytes.readLe16(entry + 6);
            symbol.value = bytes.readLe64(entry + 8);
            symbol.size = bytes.readLe64(entry + 16);
            if (symbol.section && symbol.section != SHN_ABS && symbol.section != SHN_COMMON && symbol.section >= count)
                return inputError(error, name, "ELF symbol references a section outside its input");
            if (!shared && symbol.section == SHN_COMMON && (symbol.size > UINT32_MAX || symbol.value > UINT32_MAX))
                return inputError(error, name, "ELF common symbol exceeds the image size or alignment range");
            if (!shared && symbol.section == SHN_COMMON && !std::has_single_bit(std::max<uint64_t>(1, symbol.value)))
                return inputError(error, name, "ELF common symbol alignment needs a power of two");
            if (!shared && symbol.section && symbol.section < count &&
                (symbol.value > sections[symbol.section].size || symbol.size > sections[symbol.section].size - symbol.value))
                return inputError(error, name, "ELF symbol extends beyond its section");
        }
        for (const Section& section : sections)
        {
            if (!shared && section.type == SHT_RELA)
            {
                if (section.entrySize != 24 || section.size % 24 || section.link != symbolTable || !section.info || section.info >= count)
                    return inputError(error, name, "ELF relocations need complete RELA entries and valid section and symbol indexes");
                for (uint64_t offset = 0; offset < section.size; offset += 24)
                {
                    const uint64_t entry = section.offset + offset;
                    const uint64_t info = bytes.readLe64(entry + 8);
                    if ((info >> 32) >= symbols.size())
                        return inputError(error, name, "ELF relocation references a symbol outside its table");
                    relocations.push_back({.section = section.info, .symbol = static_cast<uint32_t>(info >> 32), .type = static_cast<uint32_t>(info), .offset = bytes.readLe64(entry), .addend = std::bit_cast<int64_t>(bytes.readLe64(entry + 16))});
                }
            }
            else if (!shared && section.type == 9)
                return inputError(error, name, "ELF64 objects need explicit-addend RELA relocations");
            else if (shared && section.type == SHT_DYNAMIC)
            {
                if (section.size % 16 || section.link >= count || sections[section.link].type != SHT_STRTAB)
                    return inputError(error, name, "ELF dynamic entries need a linked string table");
                for (uint64_t offset = 0; offset < section.size; offset += 16)
                {
                    const uint64_t tag = bytes.readLe64(section.offset + offset);
                    if (tag != 1 && tag != 14)
                        continue;
                    std::string text;
                    if (!string(text, error, sections[section.link], bytes.readLe64(section.offset + offset + 8)))
                        return false;
                    if (tag == 1)
                        needed.push_back(std::move(text));
                    else
                        soname = std::move(text);
                }
            }
        }
        std::map<uint16_t, std::string> versions;
        for (const Section& section : sections)
        {
            if (!shared || section.type != 0x6ffffffd)
                continue;
            if (section.link >= count || sections[section.link].type != SHT_STRTAB)
                return inputError(error, name, "ELF version definitions need a linked string table");
            uint64_t offset = 0;
            for (uint64_t iteration = 0; iteration <= section.size / 20; ++iteration)
            {
                if (offset > section.size || section.size - offset < 20)
                    return inputError(error, name, "ELF version definition extends beyond its section");
                const uint64_t entry = section.offset + offset;
                const uint32_t auxiliary = bytes.readLe32(entry + 12);
                if (auxiliary > section.size - offset || section.size - offset - auxiliary < 8)
                    return inputError(error, name, "ELF version name extends beyond its section");
                std::string version;
                if (!string(version, error, sections[section.link], bytes.readLe32(entry + auxiliary)))
                    return false;
                versions.emplace(bytes.readLe16(entry + 4), std::move(version));
                const uint32_t next = bytes.readLe32(entry + 16);
                if (!next)
                    break;
                if (next < 20 || next > section.size - offset)
                    return inputError(error, name, "ELF version chain extends beyond its section");
                offset += next;
            }
        }
        for (const Section& section : sections)
        {
            if (!shared || section.type != 0x6fffffff)
                continue;
            if (section.entrySize != 2 || section.link != symbolTable || section.size < symbols.size() * 2)
                return inputError(error, name, "ELF symbol versions do not cover the dynamic symbol table");
            for (size_t index = 0; index < symbols.size(); ++index)
            {
                const uint16_t version = bytes.readLe16(section.offset + index * 2);
                symbols[index].hiddenVersion = (version & 0x8000) != 0;
                const auto found = versions.find(version & 0x7fff);
                if ((version & 0x7fff) > 1 && found != versions.end())
                    symbols[index].version = found->second;
            }
        }
        return true;
    }

    uint32_t hash(const std::string_view name)
    {
        uint32_t result = 0;
        for (const unsigned char character : name)
        {
            result = (result << 4) + character;
            const uint32_t high = result & 0xf0000000;
            result ^= high >> 24;
            result &= ~high;
        }
        return result;
    }
}

SWC_END_NAMESPACE();

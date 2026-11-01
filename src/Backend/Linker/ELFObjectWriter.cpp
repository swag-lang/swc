#include "pch.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_PROGBITS = 1;
    constexpr uint32_t K_SYMTAB = 2;
    constexpr uint32_t K_STRTAB = 3;
    constexpr uint32_t K_RELA = 4;
    constexpr uint32_t K_NOBITS = 8;
    constexpr uint64_t K_WRITE = 1;
    constexpr uint64_t K_ALLOC = 2;
    constexpr uint64_t K_EXEC = 4;
    constexpr uint32_t K_ABS64 = 1;
    constexpr uint32_t K_PC32 = 2;
    constexpr uint32_t K_PLT32 = 4;
    constexpr uint16_t K_RESERVED_SECTION = 0xff00;

    struct ElfSection
    {
        Utf8 name;
        uint32_t type = K_PROGBITS;
        uint64_t flags = 0;
        uint64_t alignment = 1;
        uint64_t entrySize = 0;
        uint32_t link = 0;
        uint32_t info = 0;
        uint64_t size = 0;
        uint64_t offset = 0;
        uint32_t nameOffset = 0;
        ByteArray bytes;
    };

    bool objectError(Diagnostic& outDiag, std::string_view reason)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_elf_object);
        outDiag.addArgument(Diagnostic::ARG_BECAUSE, Utf8(reason));
        return false;
    }

    uint32_t appendString(ByteArray& table, std::string_view text)
    {
        const auto offset = static_cast<uint32_t>(table.size());
        table.append(text);
        table.pushBack(std::byte{0});
        return offset;
    }

    void appendSymbol(ByteArray& table, uint32_t name, uint8_t info, uint16_t section, uint64_t value)
    {
        table.appendLe32(name);
        table.pushBack(std::byte{info});
        table.pushBack(std::byte{0}); // STV_DEFAULT
        table.appendLe16(section);
        table.appendLe64(value);
        table.appendLe64(0);
    }
}

bool buildElfObject(ByteArray& outBytes, Diagnostic& outDiag, const LinkImage& image)
{
    outBytes.clear();
    if (image.sections.size() >= K_RESERVED_SECTION / 2 - 5)
        return objectError(outDiag, "the section count exceeds the ELF object's supported index range");

    // Index zero is the mandatory null section. Original sections retain consecutive
    // indices so a symbol's section number does not depend on relocation discovery.
    std::vector<ElfSection> sections(1);
    sections.front().type = 0;
    sections.front().alignment = 0;
    for (const LinkSection& source : image.sections)
    {
        if (source.bytes.size() > UINT32_MAX)
            return objectError(outDiag, "a section exceeds the native image size limit");
        if (!std::has_single_bit(source.align))
            return objectError(outDiag, "section alignment needs to be a nonzero power of two");
        if (source.name.view().contains('\0'))
            return objectError(outDiag, "a section name contains a null byte");
        if (source.isUninit() && (!source.bytes.empty() || !source.relocs.empty()))
            return objectError(outDiag, "a zero-filled section cannot hold file bytes or relocations");
        ElfSection section;
        section.name = source.name;
        section.type = source.isUninit() ? K_NOBITS : K_PROGBITS;
        section.flags = K_ALLOC;
        if (source.flags.has(LinkSectionFlagsE::Write))
            section.flags |= K_WRITE;
        if (source.flags.has(LinkSectionFlagsE::Execute))
            section.flags |= K_EXEC;
        section.alignment = source.align;
        section.size = source.virtualSize();
        section.bytes = source.bytes;
        sections.push_back(std::move(section));
    }

    std::map<Utf8, const LinkSymbol*> definitions;
    for (const LinkSymbol& symbol : image.symbols)
    {
        if (symbol.name.empty() || symbol.name.view().contains('\0'))
            return objectError(outDiag, "a symbol needs a nonempty name without null bytes");
        if (symbol.sectionIndex >= image.sections.size() || symbol.value > image.sections[symbol.sectionIndex].virtualSize())
            return objectError(outDiag, "a symbol lies outside its section");
        if (!definitions.emplace(symbol.name, &symbol).second)
            return objectError(outDiag, "more than one definition has the same symbol name");
    }

    // Public aliases participate in resolution before undefined symbols are collected.
    for (const LinkExport& exported : image.exports)
    {
        const auto found = definitions.find(exported.symbolName);
        if (found == definitions.end())
            return objectError(outDiag, "an export has no definition in the object");
        if (exported.name.empty() || exported.name.view().contains('\0'))
            return objectError(outDiag, "an export needs a nonempty name without null bytes");
        if (exported.name != exported.symbolName && !definitions.emplace(exported.name, found->second).second)
            return objectError(outDiag, "an export name conflicts with another symbol");
    }

    std::set<Utf8> undefined;
    for (const LinkSection& source : image.sections)
    {
        for (const LinkReloc& relocation : source.relocs)
        {
            if (relocation.symbolName.empty() || relocation.symbolName.view().contains('\0'))
                return objectError(outDiag, "a relocation needs a nonempty symbol name without null bytes");
            if (!definitions.contains(relocation.symbolName))
                undefined.insert(relocation.symbolName);
        }
    }

    ElfSection strings;
    strings.name = ".strtab";
    strings.type = K_STRTAB;
    strings.bytes.pushBack(std::byte{0});
    ElfSection symbols;
    symbols.name = ".symtab";
    symbols.type = K_SYMTAB;
    symbols.alignment = 8;
    symbols.entrySize = 24;
    symbols.info = 1; // Only the null symbol is local.
    symbols.bytes.resize(24);
    std::map<Utf8, uint32_t> symbolIndices;
    for (const auto& [name, symbol] : definitions)
    {
        symbolIndices.emplace(name, static_cast<uint32_t>(symbols.bytes.size() / 24));
        const uint8_t type = image.sections[symbol->sectionIndex].flags.has(LinkSectionFlagsE::Code) ? 2 : 1;
        appendSymbol(symbols.bytes, appendString(strings.bytes, name.view()), 0x10 | type, static_cast<uint16_t>(symbol->sectionIndex + 1), symbol->value);
    }
    for (const Utf8& name : undefined)
    {
        symbolIndices.emplace(name, static_cast<uint32_t>(symbols.bytes.size() / 24));
        appendSymbol(symbols.bytes, appendString(strings.bytes, name.view()), 0x10, 0, 0);
    }

    const uint32_t symbolsIndex = static_cast<uint32_t>(sections.size());
    symbols.link = symbolsIndex + 1;
    sections.push_back(std::move(symbols));
    sections.push_back(std::move(strings));
    std::set<Utf8> importedData;
    for (const LinkImport& imported : image.imports)
    {
        if (imported.isData)
            importedData.insert(imported.symbolName);
    }
    for (uint32_t index = 0; index < image.sections.size(); ++index)
    {
        const LinkSection& source = image.sections[index];
        if (source.relocs.empty())
            continue;
        ElfSection relocs;
        relocs.name = ".rela" + source.name;
        relocs.type = K_RELA;
        relocs.alignment = 8;
        relocs.entrySize = 24;
        relocs.link = symbolsIndex;
        relocs.info = index + 1;
        for (const LinkReloc& relocation : source.relocs)
        {
            uint32_t type;
            uint64_t addend;
            size_t width;
            if (relocation.kind == LinkRelocKind::Abs64)
            {
                type = K_ABS64;
                width = 8;
                if (!source.bytes.containsRange(relocation.offset, width))
                    return objectError(outDiag, "an absolute relocation extends beyond its section");
                addend = source.bytes.readLe64(relocation.offset) + static_cast<uint64_t>(relocation.addend);
            }
            else if (relocation.kind == LinkRelocKind::Rel32)
            {
                type = undefined.contains(relocation.symbolName) && !importedData.contains(relocation.symbolName) ? K_PLT32 : K_PC32;
                width = 4;
                if (!source.bytes.containsRange(relocation.offset, width))
                    return objectError(outDiag, "a relative relocation extends beyond its section");
                const int32_t embedded = std::bit_cast<int32_t>(source.bytes.readLe32(relocation.offset));
                // LinkReloc measures from the end of the displacement; ELF measures
                // from its first byte. Preserve both the embedded and explicit addends.
                addend = static_cast<uint64_t>(static_cast<int64_t>(embedded)) + static_cast<uint64_t>(relocation.addend) - 4;
            }
            else
                return objectError(outDiag, "ELF relocatable objects do not support image-relative relocations");
            std::fill_n(sections[index + 1].bytes.begin() + relocation.offset, width, std::byte{0});
            relocs.bytes.appendLe64(relocation.offset);
            relocs.bytes.appendLe64((static_cast<uint64_t>(symbolIndices.at(relocation.symbolName)) << 32) | type);
            relocs.bytes.appendLe64(addend);
        }
        sections.push_back(std::move(relocs));
    }

    ElfSection stack;
    stack.name = ".note.GNU-stack"; // No executable process stack is needed.
    sections.push_back(std::move(stack));
    const uint16_t namesIndex = static_cast<uint16_t>(sections.size());
    ElfSection names;
    names.name = ".shstrtab";
    names.type = K_STRTAB;
    names.bytes.pushBack(std::byte{0});
    for (size_t index = 1; index < sections.size(); ++index)
        sections[index].nameOffset = appendString(names.bytes, sections[index].name.view());
    names.nameOffset = appendString(names.bytes, names.name.view());
    sections.push_back(std::move(names));

    ByteArray bytes(64);
    bytes.writeLe32(0, 0x464c457f);
    bytes[4] = std::byte{2}; // ELFCLASS64
    bytes[5] = std::byte{1}; // ELFDATA2LSB
    bytes[6] = std::byte{1}; // EV_CURRENT
    bytes.writeLe16(16, 1); // ET_REL
    bytes.writeLe16(18, 62); // EM_X86_64
    bytes.writeLe32(20, 1);
    bytes.writeLe16(52, 64);
    bytes.writeLe16(58, 64);
    bytes.writeLe16(60, static_cast<uint16_t>(sections.size()));
    bytes.writeLe16(62, namesIndex);
    for (size_t index = 1; index < sections.size(); ++index)
    {
        ElfSection& section = sections[index];
        // SHT_NOBITS has virtual alignment but occupies no file bytes.
        if (section.type != K_NOBITS)
            bytes.align(section.alignment);
        section.offset = bytes.size();
        if (section.type != K_NOBITS)
        {
            section.size = section.bytes.size();
            bytes.append(section.bytes);
        }
    }
    bytes.align(8);
    bytes.writeLe64(40, bytes.size());
    for (const ElfSection& section : sections)
    {
        bytes.appendLe32(section.nameOffset);
        bytes.appendLe32(section.type);
        bytes.appendLe64(section.flags);
        bytes.appendLe64(0);
        bytes.appendLe64(section.offset);
        bytes.appendLe64(section.size);
        bytes.appendLe32(section.link);
        bytes.appendLe32(section.info);
        bytes.appendLe64(section.alignment);
        bytes.appendLe64(section.entrySize);
    }
    outBytes = std::move(bytes);
    return true;
}

SWC_END_NAMESPACE();

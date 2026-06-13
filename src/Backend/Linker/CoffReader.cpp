#include "pch.h"
#include "Backend/Linker/CoffReader.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h" // windows.h -> IMAGE_* definitions
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 readStringTableName(ByteSpan bytes, size_t stringTableOffset, uint32_t nameOffset)
    {
        const size_t start = stringTableOffset + nameOffset;
        if (start >= bytes.size())
            return {};
        const auto* begin = reinterpret_cast<const char*>(bytes.data() + start);
        size_t      len   = 0;
        while (start + len < bytes.size() && begin[len] != '\0')
            ++len;
        return Utf8{std::string_view{begin, len}};
    }

    uint32_t alignmentFromCharacteristics(uint32_t characteristics)
    {
        const uint32_t field = (characteristics & 0x00F00000u) >> 20;
        if (field == 0)
            return 1;
        return 1u << (field - 1);
    }

    EnumFlags<LinkSectionFlagsE> flagsFromCharacteristics(uint32_t characteristics)
    {
        EnumFlags<LinkSectionFlagsE> flags;
        if (characteristics & IMAGE_SCN_CNT_CODE)
            flags.add(LinkSectionFlagsE::Code);
        if (characteristics & IMAGE_SCN_MEM_EXECUTE)
            flags.add(LinkSectionFlagsE::Execute);
        if (characteristics & IMAGE_SCN_MEM_READ)
            flags.add(LinkSectionFlagsE::Read);
        if (characteristics & IMAGE_SCN_MEM_WRITE)
            flags.add(LinkSectionFlagsE::Write);
        if (characteristics & IMAGE_SCN_CNT_UNINITIALIZED_DATA)
            flags.add(LinkSectionFlagsE::Uninit);
        return flags;
    }

    bool linkRelocKindFromCoffType(LinkRelocKind& outKind, uint16_t type)
    {
        switch (type)
        {
            case IMAGE_REL_AMD64_ADDR64:
                outKind = LinkRelocKind::Abs64;
                return true;
            case IMAGE_REL_AMD64_ADDR32NB:
                outKind = LinkRelocKind::Rva32;
                return true;
            default:
                return false;
        }
    }

    Utf8 symbolName(const IMAGE_SYMBOL& record, ByteSpan bytes, size_t stringTableOffset)
    {
        if (record.N.Name.Short != 0)
        {
            const auto* shortName = reinterpret_cast<const char*>(record.N.ShortName);
            size_t      len       = 0;
            while (len < IMAGE_SIZEOF_SHORT_NAME && shortName[len] != '\0')
                ++len;
            return Utf8{std::string_view{shortName, len}};
        }
        return readStringTableName(bytes, stringTableOffset, record.N.Name.Long);
    }
}

bool readCoffObject(CoffObject& outObject, Diagnostic& outDiag, ByteSpan bytes)
{
    outObject = {};

    IMAGE_FILE_HEADER fileHeader{};
    if (!ByteUtils::tryReadValue(fileHeader, bytes, 0))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_truncated_header);
        return false;
    }

    if (fileHeader.Machine != IMAGE_FILE_MACHINE_AMD64)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_unsupported_machine);
        return false;
    }

    const size_t sectionTableOffset = sizeof(IMAGE_FILE_HEADER) + fileHeader.SizeOfOptionalHeader;
    const size_t sectionCount       = fileHeader.NumberOfSections;
    const size_t symbolTableOffset  = fileHeader.PointerToSymbolTable;
    const size_t symbolCount        = fileHeader.NumberOfSymbols;
    const size_t stringTableOffset  = symbolTableOffset + symbolCount * sizeof(IMAGE_SYMBOL);

    // Decode the symbol table first: relocations reference symbols by record index, and we want their
    // names. Auxiliary records keep the index space contiguous but carry no name of their own.
    std::vector<Utf8>     recordNames(symbolCount);
    std::vector           recordSectionNumber(symbolCount, 0);
    std::vector<uint32_t> recordValue(symbolCount, 0);
    for (size_t i = 0; i < symbolCount;)
    {
        IMAGE_SYMBOL record{};
        if (!ByteUtils::tryReadValue(record, bytes, symbolTableOffset + i * sizeof(IMAGE_SYMBOL)))
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_truncated_symbols);
            return false;
        }

        recordNames[i]         = symbolName(record, bytes, stringTableOffset);
        recordSectionNumber[i] = record.SectionNumber;
        recordValue[i]         = record.Value;

        const size_t step = 1 + record.NumberOfAuxSymbols;
        i += step;
    }

    // Decode sections, including their raw bytes and relocations.
    outObject.sections.resize(sectionCount);
    for (size_t s = 0; s < sectionCount; ++s)
    {
        IMAGE_SECTION_HEADER header{};
        if (!ByteUtils::tryReadValue(header, bytes, sectionTableOffset + s * sizeof(IMAGE_SECTION_HEADER)))
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_truncated_section);
            return false;
        }

        CoffInputSection& section = outObject.sections[s];

        char nameBuffer[IMAGE_SIZEOF_SHORT_NAME + 1] = {};
        std::memcpy(nameBuffer, header.Name, IMAGE_SIZEOF_SHORT_NAME);
        section.name            = Utf8{std::string_view{nameBuffer}};
        section.characteristics = header.Characteristics;

        const bool isUninit = (header.Characteristics & IMAGE_SCN_CNT_UNINITIALIZED_DATA) != 0;
        if (isUninit)
        {
            section.isBss   = true;
            section.bssSize = header.SizeOfRawData;
        }
        else if (header.SizeOfRawData != 0 && header.PointerToRawData != 0)
        {
            if (header.PointerToRawData + header.SizeOfRawData > bytes.size())
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_section_out_of_bounds);
                return false;
            }
            const auto rawBegin = bytes.begin() + header.PointerToRawData;
            const auto rawEnd   = rawBegin + header.SizeOfRawData;
            section.bytes.assign(rawBegin, rawEnd);
        }

        if (header.NumberOfRelocations == 0 && (header.Characteristics & IMAGE_SCN_LNK_NRELOC_OVFL) == 0)
            continue;

        size_t   relocOffset = header.PointerToRelocations;
        uint32_t relocCount  = header.NumberOfRelocations;
        if (header.Characteristics & IMAGE_SCN_LNK_NRELOC_OVFL)
        {
            // The real count lives in the first record; skip that placeholder.
            IMAGE_RELOCATION overflow{};
            if (!ByteUtils::tryReadValue(overflow, bytes, relocOffset))
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_truncated_reloc_overflow);
                return false;
            }
            relocCount = overflow.RelocCount;
            relocOffset += sizeof(IMAGE_RELOCATION);
            if (relocCount > 0)
                relocCount -= 1;
        }

        section.relocs.reserve(relocCount);
        for (uint32_t r = 0; r < relocCount; ++r)
        {
            IMAGE_RELOCATION reloc{};
            if (!ByteUtils::tryReadValue(reloc, bytes, relocOffset + r * sizeof(IMAGE_RELOCATION)))
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_truncated_relocs);
                return false;
            }

            if (reloc.SymbolTableIndex >= recordNames.size())
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_reloc_symbol_out_of_range);
                return false;
            }

            CoffInputReloc out;
            out.offset     = reloc.VirtualAddress;
            out.symbolName = recordNames[reloc.SymbolTableIndex];
            out.type       = reloc.Type;
            section.relocs.push_back(std::move(out));
        }
    }

    // Collect the symbols this object defines (those bound to one of its sections).
    for (size_t i = 0; i < symbolCount; ++i)
    {
        const int32_t sectionNumber = recordSectionNumber[i];
        if (sectionNumber <= 0 || std::cmp_greater(sectionNumber, sectionCount))
            continue;
        if (recordNames[i].empty())
            continue;

        CoffInputSymbol symbol;
        symbol.name         = recordNames[i];
        symbol.sectionIndex = static_cast<uint32_t>(sectionNumber - 1);
        symbol.value        = recordValue[i];
        outObject.definedSymbols.push_back(std::move(symbol));
    }

    return true;
}

bool mergeCoffObjectsIntoImage(LinkImage& outImage, Diagnostic& outDiag, const std::vector<CoffObject>& objects)
{
    std::unordered_map<Utf8, uint32_t> sectionByName; // name -> outImage.sections index
    std::unordered_set<Utf8>           definedNames;

    // Seed with any sections already present (typically none).
    for (uint32_t i = 0; i < outImage.sections.size(); ++i)
        sectionByName[outImage.sections[i].name] = i;
    for (const LinkSymbol& symbol : outImage.symbols)
        definedNames.insert(symbol.name);

    for (const CoffObject& object : objects)
    {
        std::vector<int64_t>  baseOffset(object.sections.size(), -1); // -1 marks a dropped section
        std::vector<uint32_t> mergedIndex(object.sections.size(), 0);

        for (size_t s = 0; s < object.sections.size(); ++s)
        {
            const CoffInputSection& section = object.sections[s];
            if (section.name.view().starts_with(".debug"))
                continue; // CodeView debug info is replaced by the embedded symbolizer table

            uint32_t   mergedIdx = 0;
            const auto it        = sectionByName.find(section.name);
            if (it == sectionByName.end())
            {
                LinkSection merged;
                merged.name  = section.name;
                merged.align = 1;
                mergedIdx    = static_cast<uint32_t>(outImage.sections.size());
                outImage.sections.push_back(std::move(merged));
                sectionByName.emplace(section.name, mergedIdx);
            }
            else
            {
                mergedIdx = it->second;
            }

            LinkSection&   merged = outImage.sections[mergedIdx];
            const uint32_t align  = alignmentFromCharacteristics(section.characteristics);
            merged.align          = std::max(merged.align, align);
            merged.flags.add(flagsFromCharacteristics(section.characteristics));

            uint32_t base = 0;
            if (section.isBss)
            {
                merged.bssSize = Math::alignUpU32(merged.bssSize, align);
                base           = merged.bssSize;
                merged.bssSize += section.bssSize;
                merged.flags.add(LinkSectionFlagsE::Uninit);
            }
            else
            {
                base = Math::alignUpU32(static_cast<uint32_t>(merged.bytes.size()), align);
                merged.bytes.resize(base, std::byte{0});
                merged.bytes.insert(merged.bytes.end(), section.bytes.begin(), section.bytes.end());
            }

            baseOffset[s]  = base;
            mergedIndex[s] = mergedIdx;

            for (const CoffInputReloc& reloc : section.relocs)
            {
                LinkRelocKind kind;
                if (!linkRelocKindFromCoffType(kind, reloc.type))
                {
                    outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_unsupported_reloc);
                    outDiag.addArgument(Diagnostic::ARG_VALUE, std::to_string(reloc.type));
                    outDiag.addArgument(Diagnostic::ARG_TARGET, section.name);
                    return false;
                }

                LinkReloc out;
                out.sectionIndex = mergedIdx;
                out.offset       = base + reloc.offset;
                out.symbolName   = reloc.symbolName;
                out.kind         = kind;
                merged.relocs.push_back(std::move(out));
            }
        }

        for (const CoffInputSymbol& symbol : object.definedSymbols)
        {
            if (symbol.sectionIndex >= baseOffset.size() || baseOffset[symbol.sectionIndex] < 0)
                continue; // defined in a dropped section
            if (!definedNames.insert(symbol.name).second)
                continue; // first definition wins

            LinkSymbol out;
            out.name         = symbol.name;
            out.sectionIndex = mergedIndex[symbol.sectionIndex];
            out.value        = static_cast<uint32_t>(baseOffset[symbol.sectionIndex]) + symbol.value;
            outImage.symbols.push_back(std::move(out));
        }
    }

    return true;
}

SWC_END_NAMESPACE();

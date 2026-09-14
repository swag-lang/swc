#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/Archive.h"
#include "Backend/Linker/CoffReader.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t TEXT_HEADER = sizeof(IMAGE_FILE_HEADER);
    constexpr size_t TEXT_DATA   = TEXT_HEADER + 2 * sizeof(IMAGE_SECTION_HEADER);
    constexpr size_t RELOC_DATA  = TEXT_DATA + 4;

    template<typename T>
    void writeRecord(ByteArray& bytes, const size_t offset, const T& record)
    {
        static_assert(std::is_trivially_copyable_v<T>);
        std::memcpy(bytes.data() + offset, &record, sizeof(record));
    }

    ByteArray makeCoffReaderObject(const bool overflow)
    {
        const size_t relocData  = RELOC_DATA + (overflow ? sizeof(IMAGE_RELOCATION) : 0);
        const size_t symbolData = relocData + 2 * sizeof(IMAGE_RELOCATION);
        ByteArray    bytes(symbolData + 5 * sizeof(IMAGE_SYMBOL));

        IMAGE_FILE_HEADER file{};
        file.Machine              = IMAGE_FILE_MACHINE_AMD64;
        file.NumberOfSections     = 2;
        file.PointerToSymbolTable = static_cast<uint32_t>(symbolData);
        file.NumberOfSymbols      = 5;
        writeRecord(bytes, 0, file);

        IMAGE_SECTION_HEADER text{};
        std::memcpy(text.Name, ".text", 5);
        text.SizeOfRawData        = 4;
        text.PointerToRawData     = TEXT_DATA;
        text.PointerToRelocations = RELOC_DATA;
        text.NumberOfRelocations  = overflow ? 0xFFFF : 2;
        text.Characteristics      = IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ;
        if (overflow)
            text.Characteristics |= IMAGE_SCN_LNK_NRELOC_OVFL;
        writeRecord(bytes, TEXT_HEADER, text);
        bytes.writeLe32(TEXT_DATA, 0x12345678);

        IMAGE_SECTION_HEADER bss{};
        std::memcpy(bss.Name, ".bss", 4);
        bss.SizeOfRawData   = 64;
        bss.Characteristics = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE;
        writeRecord(bytes, TEXT_HEADER + sizeof(text), bss);

        IMAGE_RELOCATION reloc{};
        if (overflow)
        {
            reloc.RelocCount = 3; // Includes the count record itself.
            writeRecord(bytes, RELOC_DATA, reloc);
        }
        reloc.VirtualAddress   = 1;
        reloc.SymbolTableIndex = 3;
        reloc.Type             = IMAGE_REL_AMD64_REL32;
        writeRecord(bytes, relocData, reloc);
        reloc.SymbolTableIndex = 0;
        writeRecord(bytes, relocData + sizeof(reloc), reloc);

        IMAGE_SYMBOL symbol{};
        symbol.N.Name.Long        = 4;
        symbol.SectionNumber      = 1;
        symbol.Value              = 1;
        symbol.StorageClass       = IMAGE_SYM_CLASS_EXTERNAL;
        symbol.NumberOfAuxSymbols = 1;
        writeRecord(bytes, symbolData, symbol);
        // Record 1 is an auxiliary record; it must not become a definition.
        symbol = {};
        std::memcpy(symbol.N.ShortName, "aux", 3);
        symbol.SectionNumber = 1;
        writeRecord(bytes, symbolData + sizeof(symbol), symbol);
        symbol = {};
        std::memcpy(symbol.N.ShortName, "bss", 3);
        symbol.SectionNumber = 2;
        symbol.Value         = 3;
        symbol.StorageClass  = IMAGE_SYM_CLASS_EXTERNAL;
        writeRecord(bytes, symbolData + 2 * sizeof(symbol), symbol);
        symbol = {};
        std::memcpy(symbol.N.ShortName, "external", 8);
        symbol.StorageClass = IMAGE_SYM_CLASS_EXTERNAL;
        writeRecord(bytes, symbolData + 3 * sizeof(symbol), symbol);
        symbol = {};
        std::memcpy(symbol.N.ShortName, "local", 5);
        symbol.SectionNumber = 1;
        symbol.StorageClass  = IMAGE_SYM_CLASS_STATIC;
        writeRecord(bytes, symbolData + 4 * sizeof(symbol), symbol);

        constexpr std::string_view longName = "defined_function_name";
        bytes.appendLe32(static_cast<uint32_t>(4 + longName.size() + 1));
        bytes.appendCString(longName);
        return bytes;
    }

    bool rejectsCoffObject(const ByteArray& bytes, const DiagnosticId expected)
    {
        CoffObject                   object;
        std::vector<CoffInputSymbol> symbols;
        Diagnostic                   fullDiag;
        Diagnostic                   symbolsDiag;
        if (readCoffObject(object, fullDiag, bytes) || readCoffDefinedSymbols(symbols, symbolsDiag, bytes.span()))
            return false;
        return !fullDiag.elements().empty() && !symbolsDiag.elements().empty() &&
               fullDiag.elements().front()->id() == expected && symbolsDiag.elements().front()->id() == expected;
    }
}

SWC_TEST_BEGIN(CoffReader_DefinedSymbolsPreserveObjectSemantics)
{
    for (const bool overflow : {false, true})
    {
        ByteArray                    bytes = makeCoffReaderObject(overflow);
        CoffObject                   object;
        std::vector<CoffInputSymbol> symbols(1); // Reading replaces previous output.
        Diagnostic                   diag;
        if (!readCoffObject(object, diag, bytes) || !readCoffDefinedSymbols(symbols, diag, bytes.span()))
            return Result::Error;
        bytes = ByteArray{};

        if (symbols.size() != 3 || object.definedSymbols.size() != symbols.size() || object.sections.size() != 2)
            return Result::Error;
        if (symbols[0].name != "defined_function_name" || symbols[0].sectionIndex != 0 || symbols[0].value != 1 ||
            symbols[1].name != "bss" || symbols[1].sectionIndex != 1 || symbols[1].value != 3 ||
            symbols[2].name != "local" || symbols[2].sectionIndex != 0 || symbols[2].value != 0)
            return Result::Error;
        for (size_t i = 0; i < symbols.size(); ++i)
        {
            if (symbols[i].name != object.definedSymbols[i].name || symbols[i].sectionIndex != object.definedSymbols[i].sectionIndex || symbols[i].value != object.definedSymbols[i].value)
                return Result::Error;
        }
        const CoffInputSection& text = object.sections[0];
        const CoffInputSection& bss  = object.sections[1];
        if (text.name != ".text" || text.isBss || text.bytes.size() != 4 || text.bytes.readLe32(0) != 0x12345678 || text.relocs.size() != 2 ||
            text.relocs[0].symbolName != "external" || text.relocs[1].symbolName != "defined_function_name" ||
            text.relocs[0].offset != 1 || text.relocs[0].type != IMAGE_REL_AMD64_REL32 ||
            bss.name != ".bss" || !bss.isBss || bss.bssSize != 64 || !bss.bytes.empty() || !bss.relocs.empty())
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(CoffReader_DefinedSymbolsValidateDiscardedData)
{
    const ByteArray valid = makeCoffReaderObject(false);
    ByteArray       bytes(sizeof(IMAGE_FILE_HEADER) - 1);
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_truncated_header))
        return Result::Error;
    bytes = valid;
    bytes.writeLe16(offsetof(IMAGE_FILE_HEADER, Machine), IMAGE_FILE_MACHINE_I386);
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_unsupported_machine))
        return Result::Error;
    bytes = valid;
    bytes.writeLe32(offsetof(IMAGE_FILE_HEADER, PointerToSymbolTable), static_cast<uint32_t>(bytes.size()));
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_truncated_symbols))
        return Result::Error;
    bytes = valid;
    bytes.writeLe16(offsetof(IMAGE_FILE_HEADER, SizeOfOptionalHeader), 0xFFFF);
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_truncated_section))
        return Result::Error;
    bytes = valid;
    bytes.writeLe32(TEXT_HEADER + offsetof(IMAGE_SECTION_HEADER, PointerToRawData), static_cast<uint32_t>(bytes.size() - 1));
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_section_out_of_bounds))
        return Result::Error;
    bytes.writeLe32(TEXT_HEADER + offsetof(IMAGE_SECTION_HEADER, PointerToRawData), 0xFFFFFFF0);
    bytes.writeLe32(TEXT_HEADER + offsetof(IMAGE_SECTION_HEADER, SizeOfRawData), 0x40);
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_section_out_of_bounds))
        return Result::Error;
    bytes = valid;
    bytes.writeLe32(TEXT_HEADER + offsetof(IMAGE_SECTION_HEADER, PointerToRelocations), static_cast<uint32_t>(bytes.size() - 1));
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_truncated_relocs))
        return Result::Error;
    bytes = valid;
    bytes.writeLe32(RELOC_DATA + offsetof(IMAGE_RELOCATION, SymbolTableIndex), 5);
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_reloc_symbol_out_of_range))
        return Result::Error;
    bytes = makeCoffReaderObject(true);
    bytes.writeLe32(TEXT_HEADER + offsetof(IMAGE_SECTION_HEADER, PointerToRelocations), static_cast<uint32_t>(bytes.size() - 1));
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_truncated_reloc_overflow))
        return Result::Error;
    bytes                         = makeCoffReaderObject(true);
    const uint32_t overflowOffset = static_cast<uint32_t>(bytes.size() - sizeof(IMAGE_RELOCATION));
    bytes.writeLe32(TEXT_HEADER + offsetof(IMAGE_SECTION_HEADER, PointerToRelocations), overflowOffset);
    bytes.writeLe32(overflowOffset, 2);
    if (!rejectsCoffObject(bytes, DiagnosticId::cmd_err_link_coff_truncated_relocs))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(CoffReader_ArchiveIndexesDefinitionsOnly)
{
    std::vector<LinkArchiveMember> members = {{.name = "symbols.obj", .bytes = makeCoffReaderObject(true)}};
    ByteArray                      bytes;
    Diagnostic                     diag;
    if (!buildCoffStaticArchive(bytes, diag, members))
        return Result::Error;
    Archive archive;
    if (!archive.load(diag, std::move(bytes)))
        return Result::Error;
    const uint32_t offset = archive.memberOffsetForSymbol("defined_function_name");
    if (!offset || archive.memberOffsetForSymbol("bss") != offset || archive.memberOffsetForSymbol("local") != offset || archive.memberOffsetForSymbol("external") ||
        !std::ranges::equal(archive.memberData(diag, offset), members[0].bytes))
        return Result::Error;
    members[0].bytes.writeLe32(RELOC_DATA + sizeof(IMAGE_RELOCATION) + offsetof(IMAGE_RELOCATION, SymbolTableIndex), 5);
    if (buildCoffStaticArchive(bytes, diag, members) || diag.elements().empty() || diag.elements().front()->id() != DiagnosticId::cmd_err_link_coff_reloc_symbol_out_of_range)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

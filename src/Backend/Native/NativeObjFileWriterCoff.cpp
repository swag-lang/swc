#include "pch.h"
#include "Backend/Native/NativeObjFileWriterCoff.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugRecordCollector.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/FileSystem.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t COFF_RELOCATION_OVERFLOW_LIMIT = 0xFFFFu;

    bool needsCoffRelocationOverflow(size_t relocationCount)
    {
        return relocationCount >= COFF_RELOCATION_OVERFLOW_LIMIT;
    }
}

NativeObjFileWriterCoff::NativeObjFileWriterCoff(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

Result NativeObjFileWriterCoff::buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description)
{
    outBytes.clear();
    SWC_ASSERT(builder_ != nullptr);
    CoffSectionBuild textSection;
    textSection.data.name            = ".text";
    textSection.data.characteristics = IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    SWC_RESULT(buildTextSection(description, textSection));

    std::vector<CoffSectionBuild> sections;
    sections.push_back(std::move(textSection));

    if (description.includeData && !builder_->mergedRData.bytes.empty())
    {
        CoffSectionBuild section;
        section.data = builder_->mergedRData;
        SWC_RESULT(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    if (description.includeData && !builder_->mergedData.bytes.empty())
    {
        CoffSectionBuild section;
        section.data = builder_->mergedData;
        SWC_RESULT(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    if (description.includeData && builder_->mergedBss.bss)
    {
        CoffSectionBuild section;
        section.data = builder_->mergedBss;
        sections.push_back(std::move(section));
    }

    CollectedDebugRecords debugRecords;
    collectDebugRecords(*builder_, description.functions, description.startup, description.includeData, debugRecords);

    DebugInfoObjectResult        debugInfoResult;
    const DebugInfoObjectRequest debugInfoRequest = {
        .ctx          = &builder_->ctx(),
        .targetOs     = builder_->ctx().cmdLine().targetOs,
        .objectPath   = description.objPath,
        .functions    = debugRecords.functions,
        .globals      = debugRecords.globals,
        .constants    = debugRecords.constants,
        .emitCodeView = builder_->compiler().buildCfg().backend.debugInfo,
    };
    SWC_RESULT(DebugInfo::buildObject(debugInfoRequest, debugInfoResult));
    for (auto& debugSectionData : debugInfoResult.sections)
    {
        CoffSectionBuild section;
        section.data = std::move(debugSectionData);
        SWC_RESULT(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    for (size_t i = 0; i < sections.size(); ++i)
        sections[i].sectionNumber = static_cast<uint16_t>(i + 1);

    std::vector<CoffSymbolRecord>      symbols;
    std::unordered_map<Utf8, uint32_t> symbolIndices;
    addDefinedSymbols(description, sections, debugInfoResult.symbols, symbols, symbolIndices);
    addUndefinedSymbols(sections, symbols, symbolIndices);

    return buildCoffFile(outBytes, sections, symbols, symbolIndices);
}

Result NativeObjFileWriterCoff::writeObjectFile(const NativeObjDescription& description)
{
    ByteArray fileData;
    SWC_RESULT(buildObjectFile(fileData, description));

    FileSystem::IoErrorInfo ioError;
    if (FileSystem::writeBinaryFile(description.objPath, fileData.data(), fileData.size(), ioError) == Result::Continue)
        return Result::Continue;

    if (ioError.problem == FileSystem::IoProblem::OpenWrite)
        return builder_->reportError(DiagnosticId::cmd_err_native_obj_open_failed, Diagnostic::ARG_PATH, Utf8(description.objPath));

    return builder_->reportError(DiagnosticId::cmd_err_native_obj_write_failed, Diagnostic::ARG_PATH, Utf8(description.objPath));
}

void NativeObjFileWriterCoff::appendAlignedCodeBytes(CoffSectionBuild& textSection, uint32_t& outOffset, const ByteArray& bytes)
{
    const uint32_t alignedOffset = Math::alignUpU32(static_cast<uint32_t>(textSection.data.bytes.size()), 16);
    if (textSection.data.bytes.size() < alignedOffset)
        textSection.data.bytes.resize(alignedOffset, std::byte{0});
    outOffset = alignedOffset;
    textSection.data.bytes.append(bytes);
}

Result NativeObjFileWriterCoff::buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection) const
{
    if (description.startup)
        appendAlignedCodeBytes(textSection, description.startup->textOffset, description.startup->code.bytes);
    for (NativeFunctionInfo* info : description.functions)
        appendAlignedCodeBytes(textSection, info->textOffset, info->machineCode->bytes);

    if (description.startup)
        SWC_RESULT(appendCodeRelocations(*description.startup, description.startup->code, textSection, description.allowUnresolvedSymbols));
    for (const NativeFunctionInfo* info : description.functions)
        SWC_RESULT(appendCodeRelocations(*info, *info->machineCode, textSection, description.allowUnresolvedSymbols));

    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    for (const auto& relocation : code.codeRelocations)
        SWC_RESULT(appendSingleCodeRelocation(startup.textOffset, startup.debugName, relocation, textSection, allowUnresolvedSymbols));
    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    for (const auto& relocation : code.codeRelocations)
        SWC_RESULT(appendSingleCodeRelocation(owner.textOffset, owner.debugName, relocation, textSection, allowUnresolvedSymbols));
    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendSingleCodeRelocation(const uint32_t functionOffset, const Utf8& ownerName, const MicroRelocation& relocation, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    NativeCodeRelocationTarget target;
    target.bytes                  = &textSection.data.bytes;
    target.relocations            = &textSection.relocations;
    target.functionOffset         = functionOffset;
    target.allowUnresolvedSymbols = allowUnresolvedSymbols;
    return builder_->appendCodeRelocation(target, ownerName, relocation);
}

Result NativeObjFileWriterCoff::applySectionRelocations(CoffSectionBuild& section)
{
    for (const auto& relocation : section.data.relocations)
    {
        switch (relocation.type)
        {
            case IMAGE_REL_AMD64_ADDR64:
                SWC_ASSERT(relocation.offset + sizeof(uint64_t) <= section.data.bytes.size());
                writeU64(section.data.bytes, relocation.offset, relocation.addend);
                break;

            case IMAGE_REL_AMD64_ADDR32NB:
            case IMAGE_REL_AMD64_SECREL:
                SWC_ASSERT(relocation.offset + sizeof(uint32_t) <= section.data.bytes.size());
                writeU32(section.data.bytes, relocation.offset, static_cast<uint32_t>(relocation.addend));
                break;

            case IMAGE_REL_AMD64_SECTION:
                SWC_ASSERT(relocation.offset + sizeof(uint16_t) <= section.data.bytes.size());
                writeU16(section.data.bytes, relocation.offset, static_cast<uint16_t>(relocation.addend));
                break;

            default:
                SWC_UNREACHABLE();
        }

        section.relocations.push_back(relocation);
    }

    section.data.relocations.clear();

    return Result::Continue;
}

void NativeObjFileWriterCoff::writeU16(ByteArray& bytes, const uint32_t offset, const uint16_t value)
{
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

void NativeObjFileWriterCoff::writeU32(ByteArray& bytes, const uint32_t offset, const uint32_t value)
{
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

void NativeObjFileWriterCoff::writeU64(ByteArray& bytes, const uint32_t offset, const uint64_t value)
{
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

void NativeObjFileWriterCoff::addSymbolRecord(std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices, CoffSymbolRecord record)
{
    symbolIndices.emplace(record.name, static_cast<uint32_t>(symbols.size()));
    symbols.push_back(std::move(record));
}

void NativeObjFileWriterCoff::addDefinedSymbols(const NativeObjDescription& description, const std::vector<CoffSectionBuild>& sections, const std::vector<DebugInfoDefinedSymbol>& extraSymbols, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices) const
{
    if (description.startup)
    {
        addSymbolRecord(symbols, symbolIndices, {
                                                    .name          = description.startup->symbolName,
                                                    .sectionNumber = static_cast<int16_t>(sections[0].sectionNumber),
                                                    .value         = description.startup->textOffset,
                                                    .type          = static_cast<uint16_t>(IMAGE_SYM_DTYPE_FUNCTION << 8),
                                                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                                                });
    }

    for (const NativeFunctionInfo* info : description.functions)
    {
        if (!info)
            continue;
        addSymbolRecord(symbols, symbolIndices, {
                                                    .name          = info->symbolName,
                                                    .sectionNumber = static_cast<int16_t>(sections[0].sectionNumber),
                                                    .value         = info->textOffset,
                                                    .type          = static_cast<uint16_t>(IMAGE_SYM_DTYPE_FUNCTION << 8),
                                                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                                                });
    }

    for (const auto& extraSymbol : extraSymbols)
    {
        int16_t sectionNumber = 0;
        for (const auto& section : sections)
        {
            if (section.data.name != extraSymbol.sectionName)
                continue;

            sectionNumber = static_cast<int16_t>(section.sectionNumber);
            break;
        }

        SWC_ASSERT(sectionNumber != 0);
        if (sectionNumber == 0)
            continue;

        addSymbolRecord(symbols, symbolIndices, {
                                                    .name          = extraSymbol.name,
                                                    .sectionNumber = sectionNumber,
                                                    .value         = extraSymbol.value,
                                                    .type          = extraSymbol.type,
                                                    .storageClass  = extraSymbol.storageClass,
                                                });
    }

    if (!description.includeData)
        return;

    for (const auto& section : sections)
    {
        if (section.data.name == ".rdata")
        {
            addSymbolRecord(symbols, symbolIndices, {
                                                        .name          = nativeScopedSectionBaseSymbol(builder_->compiler(), K_R_DATA_BASE_SYMBOL),
                                                        .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                                                        .value         = 0,
                                                        .type          = 0,
                                                        .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                                                    });
        }
        else if (section.data.name == ".data")
        {
            addSymbolRecord(symbols, symbolIndices, {
                                                        .name          = nativeScopedSectionBaseSymbol(builder_->compiler(), K_DATA_BASE_SYMBOL),
                                                        .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                                                        .value         = 0,
                                                        .type          = 0,
                                                        .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                                                    });
        }
        else if (section.data.name == ".bss")
        {
            addSymbolRecord(symbols, symbolIndices, {
                                                        .name          = nativeScopedSectionBaseSymbol(builder_->compiler(), K_BSS_BASE_SYMBOL),
                                                        .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                                                        .value         = 0,
                                                        .type          = 0,
                                                        .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                                                    });
        }
    }
}

void NativeObjFileWriterCoff::addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices)
{
    for (const auto& section : sections)
    {
        for (const auto& relocation : section.relocations)
        {
            if (symbolIndices.contains(relocation.symbolName))
                continue;

            symbolIndices.emplace(relocation.symbolName, static_cast<uint32_t>(symbols.size()));
            symbols.push_back({.name = relocation.symbolName, .sectionNumber = 0, .value = 0, .type = 0, .storageClass = IMAGE_SYM_CLASS_EXTERNAL});
        }
    }
}

Result NativeObjFileWriterCoff::buildCoffFile(ByteArray& outBytes, std::vector<CoffSectionBuild>& sections, const std::vector<CoffSymbolRecord>& symbols, const std::unordered_map<Utf8, uint32_t>& symbolIndices)
{
    outBytes.clear();
    CoffStringTable stringTable;
    for (const auto& symbol : symbols)
        stringTable.add(symbol.name);

    uint32_t fileOffset = sizeof(IMAGE_FILE_HEADER) + static_cast<uint32_t>(sections.size()) * sizeof(IMAGE_SECTION_HEADER);
    fileOffset          = Math::alignUpU32(fileOffset, 4);

    for (auto& section : sections)
    {
        if (!section.data.bss && !section.data.bytes.empty())
        {
            section.pointerToRawData = fileOffset;
            section.sizeOfRawData    = static_cast<uint32_t>(section.data.bytes.size());
            fileOffset += section.sizeOfRawData;
            fileOffset = Math::alignUpU32(fileOffset, 4);
        }
        else if (section.data.bss)
        {
            section.pointerToRawData = 0;
            section.sizeOfRawData    = section.data.bssSize;
        }

        if (!section.relocations.empty())
        {
            section.hasRelocationOverflow = needsCoffRelocationOverflow(section.relocations.size());
            section.pointerToRelocations  = fileOffset;
            section.numberOfRelocations   = section.hasRelocationOverflow ? static_cast<uint16_t>(COFF_RELOCATION_OVERFLOW_LIMIT) : static_cast<uint16_t>(section.relocations.size());

            const size_t relocationRecordCount = section.relocations.size() + (section.hasRelocationOverflow ? 1u : 0u);
            SWC_ASSERT(relocationRecordCount <= std::numeric_limits<uint32_t>::max() / sizeof(IMAGE_RELOCATION));
            fileOffset += static_cast<uint32_t>(relocationRecordCount * sizeof(IMAGE_RELOCATION));
            fileOffset = Math::alignUpU32(fileOffset, 4);
        }
    }

    const uint32_t symbolTableOffset = fileOffset;
    fileOffset += static_cast<uint32_t>(symbols.size() * sizeof(IMAGE_SYMBOL));
    const uint32_t stringTableOffset = fileOffset;
    fileOffset += stringTable.size;

    outBytes.resize(fileOffset, std::byte{0});

    IMAGE_FILE_HEADER header{};
    header.Machine              = IMAGE_FILE_MACHINE_AMD64;
    header.NumberOfSections     = static_cast<WORD>(sections.size());
    header.TimeDateStamp        = 0;
    header.PointerToSymbolTable = symbolTableOffset;
    header.NumberOfSymbols      = static_cast<DWORD>(symbols.size());
    header.SizeOfOptionalHeader = 0;
    header.Characteristics      = 0;
    std::memcpy(outBytes.data(), &header, sizeof(header));

    uint32_t sectionHeaderOffset = sizeof(IMAGE_FILE_HEADER);
    for (const auto& section : sections)
    {
        IMAGE_SECTION_HEADER headerSection{};
        std::memset(headerSection.Name, 0, sizeof(headerSection.Name));
        std::memcpy(headerSection.Name, section.data.name.data(), std::min<size_t>(section.data.name.size(), IMAGE_SIZEOF_SHORT_NAME));
        headerSection.SizeOfRawData        = section.sizeOfRawData;
        headerSection.PointerToRawData     = section.pointerToRawData;
        headerSection.PointerToRelocations = section.pointerToRelocations;
        headerSection.NumberOfRelocations  = section.numberOfRelocations;
        headerSection.Characteristics      = section.data.characteristics;
        if (section.hasRelocationOverflow)
            headerSection.Characteristics |= IMAGE_SCN_LNK_NRELOC_OVFL;
        std::memcpy(outBytes.data() + sectionHeaderOffset, &headerSection, sizeof(headerSection));
        sectionHeaderOffset += sizeof(IMAGE_SECTION_HEADER);
    }

    for (const auto& section : sections)
    {
        if (!section.data.bss && !section.data.bytes.empty())
            std::memcpy(outBytes.data() + section.pointerToRawData, section.data.bytes.data(), section.data.bytes.size());

        if (section.relocations.empty())
            continue;

        uint32_t relocOffset = section.pointerToRelocations;
        if (section.hasRelocationOverflow)
        {
            const size_t relocationRecordCount = section.relocations.size() + 1;
            SWC_ASSERT(relocationRecordCount <= std::numeric_limits<DWORD>::max());

            IMAGE_RELOCATION relocRecord{};
            relocRecord.RelocCount = static_cast<DWORD>(relocationRecordCount);
            std::memcpy(outBytes.data() + relocOffset, &relocRecord, sizeof(relocRecord));
            relocOffset += sizeof(IMAGE_RELOCATION);
        }

        for (const auto& relocation : section.relocations)
        {
            const auto it = symbolIndices.find(relocation.symbolName);
            SWC_ASSERT(it != symbolIndices.end());

            IMAGE_RELOCATION relocRecord{};
            relocRecord.VirtualAddress   = relocation.offset;
            relocRecord.SymbolTableIndex = it->second;
            relocRecord.Type             = relocation.type;
            std::memcpy(outBytes.data() + relocOffset, &relocRecord, sizeof(relocRecord));
            relocOffset += sizeof(IMAGE_RELOCATION);
        }
    }

    uint32_t symbolOffset = symbolTableOffset;
    for (const auto& symbol : symbols)
    {
        IMAGE_SYMBOL record{};
        if (symbol.name.size() <= IMAGE_SIZEOF_SHORT_NAME)
        {
            std::memcpy(record.N.ShortName, symbol.name.data(), symbol.name.size());
        }
        else
        {
            record.N.Name.Short = 0;
            record.N.Name.Long  = stringTable.offsets.at(symbol.name);
        }

        record.Value              = symbol.value;
        record.SectionNumber      = symbol.sectionNumber;
        record.Type               = symbol.type;
        record.StorageClass       = symbol.storageClass;
        record.NumberOfAuxSymbols = symbol.numAuxSymbols;
        std::memcpy(outBytes.data() + symbolOffset, &record, sizeof(record));
        symbolOffset += sizeof(IMAGE_SYMBOL);
    }

    std::memcpy(outBytes.data() + stringTableOffset, &stringTable.size, sizeof(uint32_t));
    uint32_t stringCursor = stringTableOffset + sizeof(uint32_t);
    for (const Utf8& entry : stringTable.entries)
    {
        std::memcpy(outBytes.data() + stringCursor, entry.data(), entry.size());
        stringCursor += static_cast<uint32_t>(entry.size());
        outBytes[stringCursor++] = std::byte{0};
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();

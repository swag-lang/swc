#include "pch.h"
#include "Backend/Native/NativeObjFileWriterCoff.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 unresolvedFunctionSymbolName(const TaskContext& ctx, const SymbolFunction& function)
    {
        Utf8 key = function.getFullScopedName(ctx);
        key += "|";
        key += std::to_string(function.tokRef().get());
        return std::format("__swc_ext_fn_{:08x}", Math::hash(key.view()));
    }
}

NativeObjFileWriterCoff::NativeObjFileWriterCoff(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

Result NativeObjFileWriterCoff::writeObjectFile(const NativeObjDescription& description)
{
    CoffSectionBuild textSection;
    textSection.data.name            = ".text";
    textSection.data.characteristics = IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    SWC_RESULT_VERIFY(buildTextSection(description, textSection));

    std::vector<CoffSectionBuild> sections;
    sections.push_back(std::move(textSection));

    if (description.includeData && !builder_.mergedRData.bytes.empty())
    {
        CoffSectionBuild section;
        section.data = builder_.mergedRData;
        SWC_RESULT_VERIFY(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    if (description.includeData && !builder_.mergedData.bytes.empty())
    {
        CoffSectionBuild section;
        section.data = builder_.mergedData;
        sections.push_back(std::move(section));
    }

    if (description.includeData && builder_.mergedBss.bss)
    {
        CoffSectionBuild section;
        section.data = builder_.mergedBss;
        sections.push_back(std::move(section));
    }

    std::vector<DebugInfoFunctionRecord> debugFunctions;
    if (description.startup)
    {
        debugFunctions.push_back({
            .symbolName  = description.startup->symbolName,
            .debugName   = description.startup->debugName,
            .textOffset  = description.startup->textOffset,
            .machineCode = &description.startup->code,
        });
    }

    for (const NativeFunctionInfo* info : description.functions)
    {
        if (!info)
            continue;

        debugFunctions.push_back({
            .symbolName  = info->symbolName,
            .debugName   = info->debugName,
            .textOffset  = info->textOffset,
            .machineCode = info->machineCode,
        });
    }

    DebugInfoObjectResult        debugInfoResult;
    const DebugInfoObjectRequest debugInfoRequest = {
        .ctx               = &builder_.ctx(),
        .targetOs          = builder_.ctx().cmdLine().targetOs,
        .objectPath        = description.objPath,
        .textSectionNumber = 1,
        .functions         = debugFunctions,
        .emitCodeView      = builder_.compiler().buildCfg().backend.debugInfo,
    };
    SWC_RESULT_VERIFY(DebugInfo::buildObject(debugInfoRequest, debugInfoResult));
    for (auto& debugSectionData : debugInfoResult.sections)
    {
        CoffSectionBuild section;
        section.data = std::move(debugSectionData);
        SWC_RESULT_VERIFY(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    for (size_t i = 0; i < sections.size(); ++i)
        sections[i].sectionNumber = static_cast<uint16_t>(i + 1);

    std::vector<CoffSymbolRecord>      symbols;
    std::unordered_map<Utf8, uint32_t> symbolIndices;
    addDefinedSymbols(description, sections, debugInfoResult.symbols, symbols, symbolIndices);
    addUndefinedSymbols(sections, symbols, symbolIndices);

    return flushCoffFile(description.objPath, sections, symbols, symbolIndices);
}

Result NativeObjFileWriterCoff::buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection) const
{
    const auto appendCode = [&](uint32_t& outOffset, const std::vector<std::byte>& bytes) {
        const uint32_t alignedOffset = Math::alignUpU32(static_cast<uint32_t>(textSection.data.bytes.size()), 16);
        if (textSection.data.bytes.size() < alignedOffset)
            textSection.data.bytes.resize(alignedOffset, std::byte{0});
        outOffset = alignedOffset;
        textSection.data.bytes.insert(textSection.data.bytes.end(), bytes.begin(), bytes.end());
    };

    if (description.startup)
        appendCode(description.startup->textOffset, description.startup->code.bytes);
    for (NativeFunctionInfo* info : description.functions)
        appendCode(info->textOffset, info->machineCode->bytes);

    if (description.startup)
        SWC_RESULT_VERIFY(appendCodeRelocations(*description.startup, description.startup->code, textSection, description.allowUnresolvedSymbols));
    for (const NativeFunctionInfo* info : description.functions)
        SWC_RESULT_VERIFY(appendCodeRelocations(*info, *info->machineCode, textSection, description.allowUnresolvedSymbols));

    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    for (const auto& relocation : code.codeRelocations)
        SWC_RESULT_VERIFY(appendSingleCodeRelocation(startup.textOffset, relocation, textSection, allowUnresolvedSymbols));
    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    for (const auto& relocation : code.codeRelocations)
        SWC_RESULT_VERIFY(appendSingleCodeRelocation(owner.textOffset, relocation, textSection, allowUnresolvedSymbols));
    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendSingleCodeRelocation(const uint32_t functionOffset, const MicroRelocation& relocation, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    const uint32_t patchOffset = functionOffset + relocation.codeOffset;
    SWC_ASSERT(patchOffset + sizeof(uint64_t) <= textSection.data.bytes.size());

    NativeSectionRelocation record;
    record.offset = patchOffset;

    switch (relocation.kind)
    {
        case MicroRelocation::Kind::LocalFunctionAddress:
        {
            const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
            SWC_ASSERT(target != nullptr);
            const auto it = builder_.functionBySymbol.find(const_cast<SymbolFunction*>(target));
            if (it != builder_.functionBySymbol.end())
            {
                record.symbolName = it->second->symbolName;
            }
            else if (allowUnresolvedSymbols && target)
            {
                record.symbolName = unresolvedFunctionSymbolName(builder_.ctx(), *target);
            }
            else
            {
                SWC_ASSERT(false);
                return builder_.reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation);
            }
            record.addend = 0;
            writeU64(textSection.data.bytes, patchOffset, 0);
            break;
        }

        case MicroRelocation::Kind::ForeignFunctionAddress:
        {
            const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
            SWC_ASSERT(target != nullptr);
            record.symbolName = target->resolveForeignFunctionName(builder_.ctx());
            record.addend     = 0;
            writeU64(textSection.data.bytes, patchOffset, 0);
            break;
        }

        case MicroRelocation::Kind::ConstantAddress:
        {
            uint32_t  shardIndex = 0;
            const Ref ref        = builder_.compiler().cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
            SWC_ASSERT(ref != INVALID_REF);
            record.symbolName = K_R_DATA_BASE_SYMBOL;
            record.addend     = builder_.rdataShardBaseOffsets[shardIndex] + ref;
            writeU64(textSection.data.bytes, patchOffset, record.addend);
            break;
        }

        case MicroRelocation::Kind::GlobalInitAddress:
            record.symbolName = K_DATA_BASE_SYMBOL;
            record.addend     = relocation.targetAddress;
            writeU64(textSection.data.bytes, patchOffset, record.addend);
            break;

        case MicroRelocation::Kind::GlobalZeroAddress:
            record.symbolName = K_BSS_BASE_SYMBOL;
            record.addend     = relocation.targetAddress;
            writeU64(textSection.data.bytes, patchOffset, record.addend);
            break;

        case MicroRelocation::Kind::CompilerAddress:
            SWC_UNREACHABLE();
    }

    textSection.relocations.push_back(record);
    return Result::Continue;
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
                SWC_ASSERT(false);
                return Result::Error;
        }

        section.relocations.push_back(relocation);
    }

    section.data.relocations.clear();

    return Result::Continue;
}

void NativeObjFileWriterCoff::writeU16(std::vector<std::byte>& bytes, const uint32_t offset, const uint16_t value)
{
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

void NativeObjFileWriterCoff::writeU32(std::vector<std::byte>& bytes, const uint32_t offset, const uint32_t value)
{
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

void NativeObjFileWriterCoff::writeU64(std::vector<std::byte>& bytes, const uint32_t offset, const uint64_t value)
{
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

void NativeObjFileWriterCoff::addDefinedSymbols(const NativeObjDescription& description, const std::vector<CoffSectionBuild>& sections, const std::vector<DebugInfoDefinedSymbol>& extraSymbols, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices)
{
    const auto add = [&](CoffSymbolRecord record) {
        symbolIndices.emplace(record.name, static_cast<uint32_t>(symbols.size()));
        symbols.push_back(std::move(record));
    };

    if (description.startup)
    {
        add({
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
        add({
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

        add({
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
            add({
                .name          = K_R_DATA_BASE_SYMBOL,
                .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                .value         = 0,
                .type          = 0,
                .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
            });
        }
        else if (section.data.name == ".data")
        {
            add({
                .name          = K_DATA_BASE_SYMBOL,
                .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                .value         = 0,
                .type          = 0,
                .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
            });
        }
        else if (section.data.name == ".bss")
        {
            add({
                .name          = K_BSS_BASE_SYMBOL,
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
            symbols.push_back({
                .name          = relocation.symbolName,
                .sectionNumber = 0,
                .value         = 0,
                .type          = 0,
                .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
            });
        }
    }
}

Result NativeObjFileWriterCoff::flushCoffFile(const fs::path& objPath, std::vector<CoffSectionBuild>& sections, const std::vector<CoffSymbolRecord>& symbols, const std::unordered_map<Utf8, uint32_t>& symbolIndices) const
{
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
            if (section.relocations.size() > 0xFFFFu)
                return builder_.reportError(DiagnosticId::cmd_err_native_too_many_coff_relocations);
            section.pointerToRelocations = fileOffset;
            section.numberOfRelocations  = static_cast<uint16_t>(section.relocations.size());
            fileOffset += static_cast<uint32_t>(section.relocations.size() * sizeof(IMAGE_RELOCATION));
            fileOffset = Math::alignUpU32(fileOffset, 4);
        }
    }

    const uint32_t symbolTableOffset = fileOffset;
    fileOffset += static_cast<uint32_t>(symbols.size() * sizeof(IMAGE_SYMBOL));
    const uint32_t stringTableOffset = fileOffset;
    fileOffset += stringTable.size;

    std::vector fileData(fileOffset, std::byte{0});

    IMAGE_FILE_HEADER header{};
    header.Machine              = IMAGE_FILE_MACHINE_AMD64;
    header.NumberOfSections     = static_cast<WORD>(sections.size());
    header.TimeDateStamp        = 0;
    header.PointerToSymbolTable = symbolTableOffset;
    header.NumberOfSymbols      = static_cast<DWORD>(symbols.size());
    header.SizeOfOptionalHeader = 0;
    header.Characteristics      = 0;
    std::memcpy(fileData.data(), &header, sizeof(header));

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
        std::memcpy(fileData.data() + sectionHeaderOffset, &headerSection, sizeof(headerSection));
        sectionHeaderOffset += sizeof(IMAGE_SECTION_HEADER);
    }

    for (const auto& section : sections)
    {
        if (!section.data.bss && !section.data.bytes.empty())
            std::memcpy(fileData.data() + section.pointerToRawData, section.data.bytes.data(), section.data.bytes.size());

        if (section.relocations.empty())
            continue;

        uint32_t relocOffset = section.pointerToRelocations;
        for (const auto& relocation : section.relocations)
        {
            const auto it = symbolIndices.find(relocation.symbolName);
            SWC_ASSERT(it != symbolIndices.end());

            IMAGE_RELOCATION relocRecord{};
            relocRecord.VirtualAddress   = relocation.offset;
            relocRecord.SymbolTableIndex = it->second;
            relocRecord.Type             = relocation.type;
            std::memcpy(fileData.data() + relocOffset, &relocRecord, sizeof(relocRecord));
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
        std::memcpy(fileData.data() + symbolOffset, &record, sizeof(record));
        symbolOffset += sizeof(IMAGE_SYMBOL);
    }

    std::memcpy(fileData.data() + stringTableOffset, &stringTable.size, sizeof(uint32_t));
    uint32_t stringCursor = stringTableOffset + sizeof(uint32_t);
    for (const Utf8& entry : stringTable.entries)
    {
        std::memcpy(fileData.data() + stringCursor, entry.data(), entry.size());
        stringCursor += static_cast<uint32_t>(entry.size());
        fileData[stringCursor++] = std::byte{0};
    }

    std::ofstream file(objPath, std::ios::binary | std::ios::trunc);
    if (!file.is_open())
        return builder_.reportError(DiagnosticId::cmd_err_native_obj_open_failed, Diagnostic::ARG_PATH, Utf8(objPath));

    file.write(reinterpret_cast<const char*>(fileData.data()), static_cast<std::streamsize>(fileData.size()));
    if (!file.good())
        return builder_.reportError(DiagnosticId::cmd_err_native_obj_write_failed, Diagnostic::ARG_PATH, Utf8(objPath));

    return Result::Continue;
}

SWC_END_NAMESPACE();

#include "pch.h"
#include "Backend/Native/NativeObjectFileWriter.WindowsCoff.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    NativeObjectFileWriterWindowsCoff::NativeObjectFileWriterWindowsCoff(NativeBackendBuilder& builder) :
        builder_(builder)
    {
    }

    bool NativeObjectFileWriterWindowsCoff::writeObjectFile(const NativeObjDescription& description)
    {
        CoffSectionBuild textSection;
        textSection.data.name            = ".text";
        textSection.data.characteristics = IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
        if (!buildTextSection(description, textSection))
            return false;

        std::vector<CoffSectionBuild> sections;
        sections.push_back(std::move(textSection));

        if (description.includeData && !builder_.mergedRData_.bytes.empty())
        {
            CoffSectionBuild section;
            section.data = builder_.mergedRData_;
            if (!buildDataRelocations(section))
                return false;
            sections.push_back(std::move(section));
        }

        if (description.includeData && !builder_.mergedData_.bytes.empty())
        {
            CoffSectionBuild section;
            section.data = builder_.mergedData_;
            sections.push_back(std::move(section));
        }

        if (description.includeData && builder_.mergedBss_.bss)
        {
            CoffSectionBuild section;
            section.data = builder_.mergedBss_;
            sections.push_back(std::move(section));
        }

        for (size_t i = 0; i < sections.size(); ++i)
            sections[i].sectionNumber = static_cast<uint16_t>(i + 1);

        std::vector<CoffSymbolRecord>      symbols;
        std::unordered_map<Utf8, uint32_t> symbolIndices;
        addDefinedSymbols(description, sections, symbols, symbolIndices);
        addUndefinedSymbols(sections, symbols, symbolIndices);

        return flushCoffFile(description.objPath, sections, symbols, symbolIndices);
    }

    bool NativeObjectFileWriterWindowsCoff::buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection)
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
        {
            if (info)
                appendCode(info->textOffset, info->machineCode->bytes);
        }

        if (description.startup && !appendCodeRelocations(*description.startup, description.startup->code, textSection))
            return false;
        for (const NativeFunctionInfo* info : description.functions)
        {
            if (info && !appendCodeRelocations(*info, *info->machineCode, textSection))
                return false;
        }

        return true;
    }

    bool NativeObjectFileWriterWindowsCoff::appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection)
    {
        for (const auto& relocation : code.codeRelocations)
        {
            if (!appendSingleCodeRelocation(startup.textOffset, relocation, textSection))
                return false;
        }

        return true;
    }

    bool NativeObjectFileWriterWindowsCoff::appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection)
    {
        for (const auto& relocation : code.codeRelocations)
        {
            if (!appendSingleCodeRelocation(owner.textOffset, relocation, textSection))
                return false;
        }

        return true;
    }

    bool NativeObjectFileWriterWindowsCoff::appendSingleCodeRelocation(const uint32_t functionOffset, const MicroRelocation& relocation, CoffSectionBuild& textSection)
    {
        const uint32_t patchOffset = functionOffset + relocation.codeOffset;
        if (patchOffset + sizeof(uint64_t) > textSection.data.bytes.size())
            return builder_.reportError("native backend text relocation offset is out of range");

        NativeSectionRelocation record;
        record.offset = patchOffset;

        switch (relocation.kind)
        {
            case MicroRelocation::Kind::LocalFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                if (!target)
                    return builder_.reportError("native backend encountered an invalid local relocation target");
                const auto it = builder_.functionBySymbol_.find(const_cast<SymbolFunction*>(target));
                if (it == builder_.functionBySymbol_.end())
                    return builder_.reportError(std::format("native backend cannot resolve local function [{}]", target->getFullScopedName(builder_.ctx_)));
                record.symbolName = it->second->symbolName;
                record.addend     = 0;
                writeU64(textSection.data.bytes, patchOffset, 0);
                break;
            }

            case MicroRelocation::Kind::ForeignFunctionAddress:
            {
                const auto* target = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
                if (!target)
                    return builder_.reportError("native backend encountered an invalid foreign relocation target");
                record.symbolName = target->resolveForeignFunctionName(builder_.ctx_);
                record.addend     = 0;
                writeU64(textSection.data.bytes, patchOffset, 0);
                break;
            }

            case MicroRelocation::Kind::ConstantAddress:
            {
                uint32_t  shardIndex = 0;
                const Ref ref        = builder_.compiler_.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(relocation.targetAddress));
                if (ref == INVALID_REF)
                    return builder_.reportError("native backend cannot resolve constant relocation");
                record.symbolName = K_RDataBaseSymbol;
                record.addend     = builder_.rdataShardBaseOffsets_[shardIndex] + ref;
                writeU64(textSection.data.bytes, patchOffset, record.addend);
                break;
            }

            case MicroRelocation::Kind::GlobalInitAddress:
                record.symbolName = K_DataBaseSymbol;
                record.addend     = relocation.targetAddress;
                writeU64(textSection.data.bytes, patchOffset, record.addend);
                break;

            case MicroRelocation::Kind::GlobalZeroAddress:
                record.symbolName = K_BssBaseSymbol;
                record.addend     = relocation.targetAddress;
                writeU64(textSection.data.bytes, patchOffset, record.addend);
                break;

            case MicroRelocation::Kind::CompilerAddress:
                return builder_.reportError("native backend encountered a compiler segment relocation while emitting code");
        }

        textSection.relocations.push_back(record);
        return true;
    }

    bool NativeObjectFileWriterWindowsCoff::buildDataRelocations(CoffSectionBuild& section) const
    {
        for (const auto& relocation : section.data.relocations)
        {
            if (relocation.offset + sizeof(uint64_t) > section.data.bytes.size())
                return builder_.reportError("native backend data relocation offset is out of range");
            writeU64(section.data.bytes, relocation.offset, relocation.addend);
            section.relocations.push_back(relocation);
        }

        return true;
    }

    void NativeObjectFileWriterWindowsCoff::writeU64(std::vector<std::byte>& bytes, const uint32_t offset, const uint64_t value)
    {
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }

    void NativeObjectFileWriterWindowsCoff::addDefinedSymbols(const NativeObjDescription&          description,
                                                              const std::vector<CoffSectionBuild>& sections,
                                                              std::vector<CoffSymbolRecord>&       symbols,
                                                              std::unordered_map<Utf8, uint32_t>&  symbolIndices)
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

        if (!description.includeData)
            return;

        for (const auto& section : sections)
        {
            if (section.data.name == ".rdata")
            {
                add({
                    .name          = K_RDataBaseSymbol,
                    .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
            else if (section.data.name == ".data")
            {
                add({
                    .name          = K_DataBaseSymbol,
                    .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
            else if (section.data.name == ".bss")
            {
                add({
                    .name          = K_BssBaseSymbol,
                    .sectionNumber = static_cast<int16_t>(section.sectionNumber),
                    .value         = 0,
                    .type          = 0,
                    .storageClass  = IMAGE_SYM_CLASS_EXTERNAL,
                });
            }
        }
    }

    void NativeObjectFileWriterWindowsCoff::addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections,
                                                                std::vector<CoffSymbolRecord>&       symbols,
                                                                std::unordered_map<Utf8, uint32_t>&  symbolIndices)
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

    bool NativeObjectFileWriterWindowsCoff::flushCoffFile(const fs::path&                           objPath,
                                                          std::vector<CoffSectionBuild>&            sections,
                                                          const std::vector<CoffSymbolRecord>&      symbols,
                                                          const std::unordered_map<Utf8, uint32_t>& symbolIndices) const
    {
        struct CoffStringTable
        {
            uint32_t add(const Utf8& name)
            {
                if (name.size() <= IMAGE_SIZEOF_SHORT_NAME)
                    return 0;
                if (const auto it = offsets.find(name); it != offsets.end())
                    return it->second;

                const uint32_t offset = size;
                offsets.emplace(name, offset);
                entries.push_back(name);
                size += static_cast<uint32_t>(name.size()) + 1;
                return offset;
            }

            uint32_t                           size = 4;
            std::unordered_map<Utf8, uint32_t> offsets;
            std::vector<Utf8>                  entries;
        };

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
                    return builder_.reportError("native backend emitted too many COFF relocations in one section");
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
        header.Characteristics      = IMAGE_FILE_LARGE_ADDRESS_AWARE | IMAGE_FILE_DEBUG_STRIPPED;
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
                if (it == symbolIndices.end())
                    return builder_.reportError(std::format("native backend cannot resolve COFF symbol [{}]", relocation.symbolName));

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
            return builder_.reportError(std::format("cannot open [{}] for writing", makeUtf8(objPath)));

        file.write(reinterpret_cast<const char*>(fileData.data()), static_cast<std::streamsize>(fileData.size()));
        if (!file.good())
            return builder_.reportError(std::format("cannot write [{}]", makeUtf8(objPath)));

        return true;
    }

    std::unique_ptr<NativeObjectFileWriter> createNativeObjectFileWriterWindowsCoff(NativeBackendBuilder& builder)
    {
        return std::make_unique<NativeObjectFileWriterWindowsCoff>(builder);
    }
}

SWC_END_NAMESPACE();

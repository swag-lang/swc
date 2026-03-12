#include "pch.h"
#include "Backend/Native/NativeObjFileWriterCoff.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Constant.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct FunctionDebugStorage
    {
        std::vector<DebugInfoLocalRecord>    parameters;
        std::vector<DebugInfoLocalRecord>    locals;
        std::vector<DebugInfoConstantRecord> constants;
    };

    DebugInfoLocalRecord makeDebugLocalRecord(const Utf8& name, const Utf8& linkageName, const TypeRef typeRef, const bool isConst, const uint32_t offset, const MicroReg baseReg)
    {
        DebugInfoLocalRecord record;
        record.name        = name;
        record.linkageName = linkageName;
        record.typeRef     = typeRef;
        record.isConst     = isConst;
        record.offset      = offset;
        record.baseReg     = baseReg;
        return record;
    }

    DebugInfoDataRecord makeDebugDataRecord(const Utf8& name, const Utf8& linkageName, const TypeRef typeRef, const bool isConst, const Utf8& symbolName, const Utf8& sectionName, const uint32_t symbolOffset, const bool isGlobal)
    {
        DebugInfoDataRecord record;
        record.name         = name;
        record.linkageName  = linkageName;
        record.typeRef      = typeRef;
        record.isConst      = isConst;
        record.symbolName   = symbolName;
        record.sectionName  = sectionName;
        record.symbolOffset = symbolOffset;
        record.isGlobal     = isGlobal;
        return record;
    }

    DebugInfoConstantRecord makeDebugConstantRecord(const Utf8& name, const Utf8& linkageName, const TypeRef typeRef, const bool isConst, const ConstantRef valueRef)
    {
        DebugInfoConstantRecord record;
        record.name        = name;
        record.linkageName = linkageName;
        record.typeRef     = typeRef;
        record.isConst     = isConst;
        record.valueRef    = valueRef;
        return record;
    }

    Utf8 unresolvedFunctionSymbolName(const TaskContext& ctx, const SymbolFunction& function)
    {
        Utf8 key = function.getFullScopedName(ctx);
        key += "|";
        key += std::to_string(function.tokRef().get());
        return std::format("__swc_ext_fn_{:08x}", Math::hash(key.view()));
    }

    Utf8 debugDataSymbolName(const TaskContext& ctx, const SymbolVariable& symbol)
    {
        Utf8 key = symbol.getFullScopedName(ctx);
        key += "|";
        key += std::to_string(symbol.tokRef().get());
        key += "|";
        key += std::to_string(symbol.offset());
        return std::format("__swc_dbg_data_{:08x}", Math::hash(key.view()));
    }

    bool shouldEmitDebugVariable(const TaskContext& ctx, const SymbolVariable& symbol)
    {
        if (!symbol.idRef().isValid() || symbol.typeRef().isInvalid())
            return false;

        return !symbol.name(ctx).empty();
    }

    bool shouldEmitDebugConstant(const TaskContext& ctx, const SymbolConstant& symbol)
    {
        if (!symbol.idRef().isValid() || symbol.typeRef().isInvalid() || symbol.cstRef().isInvalid())
            return false;

        return !symbol.name(ctx).empty();
    }

    Utf8 dataSectionName(const SymbolVariable& symbol)
    {
        switch (symbol.globalStorageKind())
        {
            case DataSegmentKind::GlobalInit:
                return ".data";
            case DataSegmentKind::GlobalZero:
                return ".bss";
            default:
                return {};
        }
    }

    void appendDebugConstantRecord(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const SymbolConstant& symbol)
    {
        if (!shouldEmitDebugConstant(ctx, symbol))
            return;

        out.push_back(makeDebugConstantRecord(Utf8(symbol.name(ctx)), symbol.getFullScopedName(ctx), symbol.typeRef(), true, symbol.cstRef()));
    }

    void collectGlobalDebugConstantsRec(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const SymbolMap& symbolMap)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            if (const auto* constant = symbol->safeCast<SymbolConstant>())
            {
                appendDebugConstantRecord(out, ctx, *constant);
                continue;
            }

            if (!symbol->isModule() && !symbol->isNamespace())
                continue;

            collectGlobalDebugConstantsRec(out, ctx, *symbol->asSymMap());
        }
    }

    void collectFunctionDebugConstants(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const SymbolFunction& function)
    {
        std::vector<const Symbol*> symbols;
        function.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            const auto* constant = symbol->safeCast<SymbolConstant>();
            if (constant)
                appendDebugConstantRecord(out, ctx, *constant);
        }
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
    SWC_RESULT(buildTextSection(description, textSection));

    std::vector<CoffSectionBuild> sections;
    sections.push_back(std::move(textSection));

    if (description.includeData && !builder_.mergedRData.bytes.empty())
    {
        CoffSectionBuild section;
        section.data = builder_.mergedRData;
        SWC_RESULT(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    if (description.includeData && !builder_.mergedData.bytes.empty())
    {
        CoffSectionBuild section;
        section.data = builder_.mergedData;
        SWC_RESULT(applySectionRelocations(section));
        sections.push_back(std::move(section));
    }

    if (description.includeData && builder_.mergedBss.bss)
    {
        CoffSectionBuild section;
        section.data = builder_.mergedBss;
        sections.push_back(std::move(section));
    }

    std::vector<DebugInfoFunctionRecord> debugFunctions;
    std::vector<FunctionDebugStorage>    functionDebugStorage;
    functionDebugStorage.reserve(description.functions.size());

    if (description.startup)
    {
        debugFunctions.push_back({
            .symbolName    = description.startup->symbolName,
            .debugName     = description.startup->debugName,
            .returnTypeRef = TypeRef::invalid(),
            .machineCode   = &description.startup->code,
        });
    }

    for (const NativeFunctionInfo* info : description.functions)
    {
        if (!info)
            continue;

        functionDebugStorage.emplace_back();
        FunctionDebugStorage& debugStorage = functionDebugStorage.back();
        const MicroReg        frameBaseReg = info->symbol ? info->symbol->debugStackBaseReg() : MicroReg::invalid();

        if (info->symbol)
        {
            for (const SymbolVariable* symVar : info->symbol->parameters())
            {
                SWC_ASSERT(symVar != nullptr);
                if (!symVar->debugStackSlotSize())
                    continue;
                if (!shouldEmitDebugVariable(builder_.ctx(), *symVar))
                    continue;

                debugStorage.parameters.push_back(makeDebugLocalRecord(Utf8(symVar->name(builder_.ctx())),
                                                                       symVar->getFullScopedName(builder_.ctx()),
                                                                       symVar->typeRef(),
                                                                       symVar->hasExtraFlag(SymbolVariableFlagsE::Let),
                                                                       symVar->debugStackSlotOffset(),
                                                                       frameBaseReg));
            }

            for (const SymbolVariable* symVar : info->symbol->localVariables())
            {
                SWC_ASSERT(symVar != nullptr);
                if (!symVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
                    continue;
                if (!shouldEmitDebugVariable(builder_.ctx(), *symVar))
                    continue;

                debugStorage.locals.push_back(makeDebugLocalRecord(Utf8(symVar->name(builder_.ctx())),
                                                                   symVar->getFullScopedName(builder_.ctx()),
                                                                   symVar->typeRef(),
                                                                   symVar->hasExtraFlag(SymbolVariableFlagsE::Let),
                                                                   symVar->offset(),
                                                                   frameBaseReg));
            }

            collectFunctionDebugConstants(debugStorage.constants, builder_.ctx(), *info->symbol);
        }

        debugFunctions.push_back({
            .symbolName    = info->symbolName,
            .debugName     = info->debugName,
            .returnTypeRef = info->symbol ? info->symbol->returnTypeRef() : TypeRef::invalid(),
            .machineCode   = info->machineCode,
            .frameSize     = info->symbol ? info->symbol->debugStackFrameSize() : 0,
            .frameBaseReg  = frameBaseReg,
            .parameters    = debugStorage.parameters,
            .locals        = debugStorage.locals,
            .constants     = debugStorage.constants,
        });
    }

    std::vector<DebugInfoDataRecord>     debugGlobals;
    std::vector<DebugInfoConstantRecord> debugConstants;
    if (description.includeData)
    {
        debugGlobals.reserve(builder_.regularGlobals.size());
        for (const SymbolVariable* symbol : builder_.regularGlobals)
        {
            SWC_ASSERT(symbol != nullptr);
            if (!symbol->hasGlobalStorage())
                continue;
            if (!shouldEmitDebugVariable(builder_.ctx(), *symbol))
                continue;

            const Utf8 sectionName = dataSectionName(*symbol);
            if (sectionName.empty())
                continue;

            debugGlobals.push_back(makeDebugDataRecord(Utf8(symbol->name(builder_.ctx())),
                                                       symbol->getFullScopedName(builder_.ctx()),
                                                       symbol->typeRef(),
                                                       symbol->hasExtraFlag(SymbolVariableFlagsE::Let),
                                                       debugDataSymbolName(builder_.ctx(), *symbol),
                                                       sectionName,
                                                       symbol->offset(),
                                                       symbol->isPublic()));
        }

        if (const SymbolModule* rootModule = builder_.compiler().symModule())
            collectGlobalDebugConstantsRec(debugConstants, builder_.ctx(), *rootModule);
    }

    DebugInfoObjectResult        debugInfoResult;
    const DebugInfoObjectRequest debugInfoRequest = {
        .ctx          = &builder_.ctx(),
        .targetOs     = builder_.ctx().cmdLine().targetOs,
        .objectPath   = description.objPath,
        .functions    = debugFunctions,
        .globals      = debugGlobals,
        .constants    = debugConstants,
        .emitCodeView = builder_.compiler().buildCfg().backend.debugInfo,
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
        SWC_RESULT(appendCodeRelocations(*description.startup, description.startup->code, textSection, description.allowUnresolvedSymbols));
    for (const NativeFunctionInfo* info : description.functions)
        SWC_RESULT(appendCodeRelocations(*info, *info->machineCode, textSection, description.allowUnresolvedSymbols));

    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    for (const auto& relocation : code.codeRelocations)
        SWC_RESULT(appendSingleCodeRelocation(startup.textOffset, relocation, textSection, allowUnresolvedSymbols));
    return Result::Continue;
}

Result NativeObjFileWriterCoff::appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection, const bool allowUnresolvedSymbols) const
{
    for (const auto& relocation : code.codeRelocations)
        SWC_RESULT(appendSingleCodeRelocation(owner.textOffset, relocation, textSection, allowUnresolvedSymbols));
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

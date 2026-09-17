#include "pch.h"
#include "Backend/Linker/LinkDebugMerge.h"
#include "Backend/Debug/CodeViewLeaf.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CV_SIGNATURE_C13    = 4;
    constexpr uint32_t K_DEBUG_S_SYMBOLS     = 0xF1;
    constexpr uint32_t K_DEBUG_S_LINES       = 0xF2;
    constexpr uint32_t K_DEBUG_S_STRINGTABLE = 0xF3;
    constexpr uint32_t K_DEBUG_S_FILECHKSMS  = 0xF4;

    constexpr uint16_t K_S_END         = 0x0006;
    constexpr uint16_t K_S_FRAMEPROC   = 0x1012;
    constexpr uint16_t K_S_UDT         = 0x1108;
    constexpr uint16_t K_S_LDATA32     = 0x110C;
    constexpr uint16_t K_S_GDATA32     = 0x110D;
    constexpr uint16_t K_S_REGREL32    = 0x1111;
    constexpr uint16_t K_S_LPROC32_ID  = 0x1146;
    constexpr uint16_t K_S_GPROC32_ID  = 0x1147;
    constexpr uint16_t K_S_PROC_ID_END = 0x114F;

    constexpr uint16_t K_LF_MODIFIER  = 0x1001;
    constexpr uint16_t K_LF_POINTER   = 0x1002;
    constexpr uint16_t K_LF_PROCEDURE = 0x1008;
    constexpr uint16_t K_LF_ARGLIST   = 0x1201;
    constexpr uint16_t K_LF_FIELDLIST = 0x1203;
    constexpr uint16_t K_LF_INDEX     = 0x1404;
    constexpr uint16_t K_LF_ARRAY     = 0x1503;
    constexpr uint16_t K_LF_STRUCTURE = 0x1505;
    constexpr uint16_t K_LF_MEMBER    = 0x150D;
    constexpr uint16_t K_LF_FUNC_ID   = 0x1601;
    constexpr uint16_t K_LF_BUILDINFO = 0x1603;
    constexpr uint16_t K_LF_STRING_ID = 0x1605;

    constexpr uint8_t K_LF_PAD0 = 0xF0;

    constexpr uint32_t K_CV_TYPE_SIGNATURE = 4;
    constexpr uint32_t K_FIRST_TYPE_INDEX  = 0x1000;
    constexpr uint32_t K_CV_LINE_MASK      = 0x00FFFFFF;
    constexpr uint16_t K_REL_AMD64_SECREL  = 0x000B;

    // Record layouts, as offsets from the start of a record (its 16-bit length).
    constexpr size_t K_PROC_CODE_SIZE        = 16;
    constexpr size_t K_PROC_TYPE             = 28;
    constexpr size_t K_PROC_OFFSET           = 32;
    constexpr size_t K_PROC_NAME             = 39;
    constexpr size_t K_FRAMEPROC_SIZE        = 30;
    constexpr size_t K_FRAMEPROC_BASE_REG    = 24;
    constexpr size_t K_FRAMEPROC_FLAGS       = 26;
    constexpr size_t K_REGREL_TYPE           = 8;
    constexpr size_t K_REGREL_REGISTER       = 12;
    constexpr size_t K_REGREL_NAME           = 14;
    constexpr size_t K_DATA_OFFSET           = 8;
    constexpr size_t K_DATA_NAME             = 14;
    constexpr size_t K_UDT_NAME              = 8;
    constexpr size_t K_LINES_HEADER_SIZE     = 12;
    constexpr size_t K_LINES_BLOCK_SIZE      = 12;
    constexpr size_t K_LINE_ENTRY_SIZE       = 8;
    constexpr size_t K_CHECKSUM_HEADER_SIZE  = 6;
    constexpr size_t K_SUBSECTION_HEADER     = 8;
    constexpr size_t K_RECORD_HEADER         = 4;
    constexpr size_t K_FIELD_MEMBER_OFFSET   = 8;
    constexpr size_t K_FIELD_INDEX_SIZE      = 8;
    constexpr size_t K_TYPE_FUNC_ID_TYPE     = 8;
    constexpr size_t K_TYPE_ARGLIST_ARGS     = 8;
    constexpr size_t K_TYPE_PROCEDURE_ARGS   = 12;
    constexpr size_t K_TYPE_ARRAY_INDEX      = 8;
    constexpr size_t K_TYPE_STRUCTURE_FIELDS = 8;
    constexpr size_t K_TYPE_STRUCTURE_DERIVE = 12;
    constexpr size_t K_TYPE_STRUCTURE_VSHAPE = 16;

    std::span<const std::byte> asBytes(const std::string& record)
    {
        return {reinterpret_cast<const std::byte*>(record.data()), record.size()};
    }

    uint16_t readU16(const std::span<const std::byte> bytes, const size_t offset)
    {
        SWC_ASSERT(offset + sizeof(uint16_t) <= bytes.size());
        uint16_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    uint32_t readU32(const std::span<const std::byte> bytes, const size_t offset)
    {
        SWC_ASSERT(offset + sizeof(uint32_t) <= bytes.size());
        uint32_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    // Reads a NUL-terminated name; a name the span cuts short ends with the span.
    std::string_view readName(const std::span<const std::byte> bytes, const size_t offset)
    {
        if (offset >= bytes.size())
            return {};
        const auto* begin = reinterpret_cast<const char*>(bytes.data() + offset);
        return {begin, strnlen(begin, bytes.size() - offset)};
    }

    bool isIdRecord(const uint16_t kind)
    {
        return kind == K_LF_FUNC_ID || kind == K_LF_BUILDINFO || kind == K_LF_STRING_ID;
    }

    // Rewrites the member type index stored at offset with the image index it became. A record only
    // names records written before it, so every type it references is already mapped; an id record
    // maps to nothing, and no type record may name one.
    bool remapTypeField(std::string& ioRecord, const size_t offset, const std::vector<uint32_t>& imageIndices)
    {
        if (offset + sizeof(uint32_t) > ioRecord.size())
            return false;

        uint32_t index = readU32(asBytes(ioRecord), offset);
        if (index < K_FIRST_TYPE_INDEX)
            return true;

        const uint32_t memberIndex = index - K_FIRST_TYPE_INDEX;
        if (memberIndex >= imageIndices.size() || !imageIndices[memberIndex])
            return false;

        index = imageIndices[memberIndex];
        std::memcpy(ioRecord.data() + offset, &index, sizeof(index));
        return true;
    }

    // Answers the image index of a type a symbol record names, or no type for one the member did not
    // carry over.
    uint32_t imageTypeIndex(const std::vector<uint32_t>& imageIndices, const uint32_t memberIndex)
    {
        if (memberIndex < K_FIRST_TYPE_INDEX)
            return memberIndex;
        const uint32_t index = memberIndex - K_FIRST_TYPE_INDEX;
        return index < imageIndices.size() ? imageIndices[index] : 0;
    }

    bool remapFieldList(std::string& ioRecord, const std::vector<uint32_t>& imageIndices)
    {
        const std::span<const std::byte> bytes = asBytes(ioRecord);
        size_t                           pos   = K_RECORD_HEADER;
        while (pos < bytes.size())
        {
            if (static_cast<uint8_t>(bytes[pos]) >= K_LF_PAD0)
            {
                ++pos;
                continue;
            }

            if (pos + K_FIELD_INDEX_SIZE > bytes.size())
                return false;

            const uint16_t leaf = readU16(bytes, pos);
            if (!remapTypeField(ioRecord, pos + 4, imageIndices))
                return false;

            if (leaf == K_LF_INDEX)
            {
                pos += K_FIELD_INDEX_SIZE;
                continue;
            }

            if (leaf != K_LF_MEMBER)
                return false;

            const size_t offsetSize = CodeViewLeaf::numericSize(bytes, pos + K_FIELD_MEMBER_OFFSET);
            if (!offsetSize)
                return false;

            pos += K_FIELD_MEMBER_OFFSET + offsetSize;
            pos += readName(bytes, pos).size() + 1;
        }

        return true;
    }

    bool remapTypeRecord(std::string& ioRecord, const uint16_t kind, const std::vector<uint32_t>& imageIndices)
    {
        switch (kind)
        {
            case K_LF_MODIFIER:
            case K_LF_POINTER:
                return remapTypeField(ioRecord, K_RECORD_HEADER, imageIndices);

            case K_LF_PROCEDURE:
                return remapTypeField(ioRecord, K_RECORD_HEADER, imageIndices) &&
                       remapTypeField(ioRecord, K_TYPE_PROCEDURE_ARGS, imageIndices);

            case K_LF_ARRAY:
                return remapTypeField(ioRecord, K_RECORD_HEADER, imageIndices) &&
                       remapTypeField(ioRecord, K_TYPE_ARRAY_INDEX, imageIndices);

            case K_LF_STRUCTURE:
                return remapTypeField(ioRecord, K_TYPE_STRUCTURE_FIELDS, imageIndices) &&
                       remapTypeField(ioRecord, K_TYPE_STRUCTURE_DERIVE, imageIndices) &&
                       remapTypeField(ioRecord, K_TYPE_STRUCTURE_VSHAPE, imageIndices);

            case K_LF_ARGLIST:
            {
                if (ioRecord.size() < K_TYPE_ARGLIST_ARGS)
                    return false;
                const uint32_t count = readU32(asBytes(ioRecord), K_RECORD_HEADER);
                for (uint32_t i = 0; i < count; ++i)
                {
                    if (!remapTypeField(ioRecord, K_TYPE_ARGLIST_ARGS + i * sizeof(uint32_t), imageIndices))
                        return false;
                }
                return true;
            }

            case K_LF_FIELDLIST:
                return remapFieldList(ioRecord, imageIndices);

            default:
                return false;
        }
    }

    struct Subsection
    {
        uint32_t                   kind   = 0;
        uint32_t                   offset = 0; // of the payload, within the section
        std::span<const std::byte> payload;
    };

    // Splits a C13 debug section into its subsections, stopping at the first header that overruns it.
    std::vector<Subsection> readSubsections(const std::span<const std::byte> section)
    {
        std::vector<Subsection> result;
        if (section.size() < sizeof(uint32_t) || readU32(section, 0) != K_CV_SIGNATURE_C13)
            return result;

        size_t pos = sizeof(uint32_t);
        while (pos + K_SUBSECTION_HEADER <= section.size())
        {
            const uint32_t kind    = readU32(section, pos);
            const size_t   length  = readU32(section, pos + 4);
            const size_t   payload = pos + K_SUBSECTION_HEADER;
            if (payload + length > section.size())
                break;

            result.push_back({.kind = kind, .offset = static_cast<uint32_t>(payload), .payload = section.subspan(payload, length)});
            pos = Math::alignUpU64(payload + length, 4);
        }

        return result;
    }

    const CoffInputSection* findSection(const CoffObject& object, const std::string_view name)
    {
        for (const CoffInputSection& section : object.sections)
        {
            if (section.name.view() == name)
                return &section;
        }

        return nullptr;
    }
}

struct LinkDebugMerger::ObjectTypes
{
    std::vector<uint32_t>                  imageIndices;   // member index - 0x1000 -> image TPI index, 0 for an id record
    std::unordered_map<uint32_t, uint32_t> procedureTypes; // member function id -> image procedure type
    std::vector<const std::string*>        addedRecords;   // records new to the image, in index order
};

struct LinkDebugMerger::ObjectSymbols
{
    const CoffInputSection*                      section   = nullptr;
    uint32_t                                     compiland = 0;
    std::span<const std::byte>                   checksums;
    std::span<const std::byte>                   strings;
    std::unordered_map<uint32_t, const Utf8*>    targets;   // section offset -> SECREL relocation target
    std::unordered_map<uint32_t, uint32_t>       files;     // checksum offset -> image file index
    std::unordered_map<std::string_view, size_t> functions; // symbol name -> index in LinkDebugInfo::functions
};

LinkDebugMerger::LinkDebugMerger(LinkDebugInfo& debugInfo) :
    debugInfo_(&debugInfo)
{
    // The image's own records come first; a member record equal to one of them reuses its index.
    const std::span<const std::byte> records   = debugInfo.tpiRecords.span();
    uint32_t                         nextIndex = K_FIRST_TYPE_INDEX;
    for (size_t pos = 0; pos + sizeof(uint16_t) <= records.size();)
    {
        const size_t size = sizeof(uint16_t) + readU16(records, pos);
        typeIndices_.try_emplace(std::string(reinterpret_cast<const char*>(records.data() + pos), size), nextIndex++);
        pos += size;
    }
    SWC_ASSERT(nextIndex == std::max(K_FIRST_TYPE_INDEX, debugInfo.tpiIndexEnd));
    debugInfo.tpiIndexEnd = nextIndex;

    for (uint32_t i = 0; i < debugInfo.files.size(); ++i)
        fileIndices_.try_emplace(debugInfo.files[i].path, i);
    for (const LinkDebugUdt& udt : debugInfo.udts)
        udts_.emplace(udt.name, udt.typeIndex);
}

bool LinkDebugMerger::appendObject(const CoffObject& object, const Utf8& compilandName)
{
    const CoffInputSection* typeSection   = findSection(object, ".debug$T");
    const CoffInputSection* symbolSection = findSection(object, ".debug$S");
    if (!typeSection || !symbolSection)
        return true;

    ObjectTypes types;
    if (!mergeTypes(types, typeSection->bytes.span()))
    {
        for (const std::string* record : types.addedRecords)
            typeIndices_.erase(typeIndices_.find(*record));
        return false;
    }

    commitTypes(types);

    ObjectSymbols symbols;
    symbols.section   = symbolSection;
    symbols.compiland = compilandIndex(compilandName);
    mergeSymbols(symbols, types);
    return true;
}

bool LinkDebugMerger::mergeTypes(ObjectTypes& outTypes, const std::span<const std::byte> section)
{
    if (section.size() < sizeof(uint32_t) || readU32(section, 0) != K_CV_TYPE_SIGNATURE)
        return false;

    uint32_t nextIndex = debugInfo_->tpiIndexEnd;
    size_t   pos       = sizeof(uint32_t);
    while (pos < section.size())
    {
        if (pos + K_RECORD_HEADER > section.size())
            return false;

        const size_t   size = sizeof(uint16_t) + readU16(section, pos);
        const uint16_t kind = readU16(section, pos + sizeof(uint16_t));
        if (pos + size > section.size())
            return false;

        std::string record(reinterpret_cast<const char*>(section.data() + pos), size);
        pos += size;

        const auto memberIndex = static_cast<uint32_t>(K_FIRST_TYPE_INDEX + outTypes.imageIndices.size());
        if (isIdRecord(kind))
        {
            if (kind == K_LF_FUNC_ID)
            {
                if (!remapTypeField(record, K_TYPE_FUNC_ID_TYPE, outTypes.imageIndices))
                    return false;
                outTypes.procedureTypes.emplace(memberIndex, readU32(asBytes(record), K_TYPE_FUNC_ID_TYPE));
            }

            outTypes.imageIndices.push_back(0);
            continue;
        }

        if (!remapTypeRecord(record, kind, outTypes.imageIndices))
            return false;

        const auto [it, inserted] = typeIndices_.try_emplace(std::move(record), nextIndex);
        if (inserted)
        {
            outTypes.addedRecords.push_back(&it->first);
            ++nextIndex;
        }

        outTypes.imageIndices.push_back(it->second);
    }

    return true;
}

void LinkDebugMerger::commitTypes(ObjectTypes& types)
{
    for (const std::string* record : types.addedRecords)
        debugInfo_->tpiRecords.append(std::string_view(*record));
    debugInfo_->tpiIndexEnd += static_cast<uint32_t>(types.addedRecords.size());
    types.addedRecords.clear();
}

void LinkDebugMerger::mergeSymbols(ObjectSymbols& symbols, const ObjectTypes& types)
{
    for (const CoffInputReloc& relocation : symbols.section->relocs)
    {
        if (relocation.type == K_REL_AMD64_SECREL)
            symbols.targets.emplace(relocation.offset, &relocation.symbolName);
    }

    // The file tables come after the line tables that point into them.
    const std::vector<Subsection> subsections = readSubsections(symbols.section->bytes.span());
    for (const Subsection& subsection : subsections)
    {
        if (subsection.kind == K_DEBUG_S_FILECHKSMS)
            symbols.checksums = subsection.payload;
        else if (subsection.kind == K_DEBUG_S_STRINGTABLE)
            symbols.strings = subsection.payload;
    }

    for (const Subsection& subsection : subsections)
    {
        if (subsection.kind == K_DEBUG_S_SYMBOLS)
            mergeSymbolRecords(symbols, types, subsection.payload, subsection.offset);
        else if (subsection.kind == K_DEBUG_S_LINES)
            mergeLines(symbols, subsection.payload, subsection.offset);
    }
}

void LinkDebugMerger::mergeSymbolRecords(ObjectSymbols& symbols, const ObjectTypes& types, const std::span<const std::byte> records, const uint32_t sectionOffset)
{
    std::optional<LinkDebugFunction> function;
    std::string_view                 functionSymbol;
    for (size_t pos = 0; pos + K_RECORD_HEADER <= records.size();)
    {
        const size_t size = sizeof(uint16_t) + readU16(records, pos);
        if (pos + size > records.size())
            return;

        const uint16_t                   kind   = readU16(records, pos + sizeof(uint16_t));
        const std::span<const std::byte> record = records.subspan(pos, size);
        const uint32_t                   offset = sectionOffset + static_cast<uint32_t>(pos);
        pos += size;

        switch (kind)
        {
            case K_S_GPROC32_ID:
            case K_S_LPROC32_ID:
            {
                const auto target = symbols.targets.find(offset + K_PROC_OFFSET);
                if (record.size() < K_PROC_NAME || target == symbols.targets.end())
                    return;

                const auto procedure = types.procedureTypes.find(readU32(record, K_PROC_TYPE));
                function.emplace();
                function->symbolName    = *target->second;
                function->displayName   = Utf8(readName(record, K_PROC_NAME));
                function->objIndex      = symbols.compiland;
                function->codeSize      = readU32(record, K_PROC_CODE_SIZE);
                function->procTypeIndex = procedure == types.procedureTypes.end() ? 0 : procedure->second;
                functionSymbol          = target->second->view();
                break;
            }

            case K_S_FRAMEPROC:
                if (!function || record.size() < K_FRAMEPROC_SIZE)
                    break;
                function->frameSize      = readU32(record, K_RECORD_HEADER);
                function->frameToCodeReg = readU16(record, K_FRAMEPROC_BASE_REG);
                function->frameProcFlags = readU32(record, K_FRAMEPROC_FLAGS);
                break;

            case K_S_REGREL32:
                if (!function || record.size() < K_REGREL_NAME)
                    break;
                function->locals.push_back({.name        = Utf8(readName(record, K_REGREL_NAME)),
                                            .typeIndex   = imageTypeIndex(types.imageIndices, readU32(record, K_REGREL_TYPE)),
                                            .frameOffset = static_cast<int32_t>(readU32(record, K_RECORD_HEADER)),
                                            .cvRegister  = readU16(record, K_REGREL_REGISTER)});
                break;

            case K_S_PROC_ID_END:
            case K_S_END:
                if (!function)
                    break;
                symbols.functions.emplace(functionSymbol, debugInfo_->functions.size());
                debugInfo_->functions.push_back(std::move(*function));
                function.reset();
                break;

            case K_S_GDATA32:
            case K_S_LDATA32:
            {
                const auto target = symbols.targets.find(offset + K_DATA_OFFSET);
                if (record.size() < K_DATA_NAME || target == symbols.targets.end())
                    break;

                LinkDebugGlobal global;
                global.symbolName    = *target->second;
                global.sectionOffset = readU32(record, K_DATA_OFFSET);
                global.displayName   = Utf8(readName(record, K_DATA_NAME));
                global.typeIndex     = imageTypeIndex(types.imageIndices, readU32(record, K_RECORD_HEADER));
                global.isPublic      = kind == K_S_GDATA32;
                debugInfo_->globals.push_back(std::move(global));
                break;
            }

            case K_S_UDT:
            {
                if (record.size() < K_UDT_NAME)
                    break;
                Utf8           name      = Utf8(readName(record, K_UDT_NAME));
                const uint32_t typeIndex = imageTypeIndex(types.imageIndices, readU32(record, K_RECORD_HEADER));
                if (typeIndex && udts_.emplace(name, typeIndex).second)
                    debugInfo_->udts.push_back({.name = std::move(name), .typeIndex = typeIndex});
                break;
            }

            default:
                break;
        }
    }
}

void LinkDebugMerger::mergeLines(ObjectSymbols& symbols, const std::span<const std::byte> lines, const uint32_t sectionOffset)
{
    const auto target = symbols.targets.find(sectionOffset);
    if (lines.size() < K_LINES_HEADER_SIZE || target == symbols.targets.end())
        return;

    const auto owner = symbols.functions.find(target->second->view());
    if (owner == symbols.functions.end())
        return;

    for (size_t pos = K_LINES_HEADER_SIZE; pos + K_LINES_BLOCK_SIZE <= lines.size();)
    {
        const uint32_t checksumOffset = readU32(lines, pos);
        const size_t   count          = readU32(lines, pos + 4);
        const size_t   blockSize      = readU32(lines, pos + 8);
        if (blockSize < K_LINES_BLOCK_SIZE + count * K_LINE_ENTRY_SIZE || pos + blockSize > lines.size())
            return;

        LinkDebugLineBlock block;
        block.fileIndex = imageFileIndex(symbols, checksumOffset);
        block.codeOffsets.reserve(count);
        block.lines.reserve(count);
        for (size_t i = 0; i < count; ++i)
        {
            const size_t entry = pos + K_LINES_BLOCK_SIZE + i * K_LINE_ENTRY_SIZE;
            block.codeOffsets.push_back(readU32(lines, entry));
            block.lines.push_back(readU32(lines, entry + 4) & K_CV_LINE_MASK);
        }

        LinkDebugFunction& function = debugInfo_->functions[owner->second];
        if (function.primaryFileIndex == std::numeric_limits<uint32_t>::max())
            function.primaryFileIndex = block.fileIndex;
        function.lineBlocks.push_back(std::move(block));
        pos += blockSize;
    }
}

uint32_t LinkDebugMerger::imageFileIndex(ObjectSymbols& symbols, const uint32_t checksumOffset)
{
    const auto known = symbols.files.find(checksumOffset);
    if (known != symbols.files.end())
        return known->second;

    LinkDebugFile file;
    if (checksumOffset + K_CHECKSUM_HEADER_SIZE <= symbols.checksums.size())
    {
        const size_t checksumSize = static_cast<uint8_t>(symbols.checksums[checksumOffset + 4]);
        file.path                 = Utf8(readName(symbols.strings, readU32(symbols.checksums, checksumOffset)));
        if (checksumOffset + K_CHECKSUM_HEADER_SIZE + checksumSize <= symbols.checksums.size())
        {
            const auto checksum = symbols.checksums.subspan(checksumOffset + K_CHECKSUM_HEADER_SIZE, checksumSize);
            file.checksumKind   = static_cast<uint8_t>(symbols.checksums[checksumOffset + 5]);
            for (const std::byte value : checksum)
                file.checksum.push_back(static_cast<uint8_t>(value));
        }
    }

    const auto [it, inserted] = fileIndices_.try_emplace(file.path, static_cast<uint32_t>(debugInfo_->files.size()));
    if (inserted)
        debugInfo_->files.push_back(std::move(file));
    symbols.files.emplace(checksumOffset, it->second);
    return it->second;
}

uint32_t LinkDebugMerger::compilandIndex(const Utf8& name)
{
    const auto [it, inserted] = compilands_.try_emplace(name, static_cast<uint32_t>(debugInfo_->objectNames.size()));
    if (inserted)
        debugInfo_->objectNames.push_back(name);
    return it->second;
}

SWC_END_NAMESPACE();

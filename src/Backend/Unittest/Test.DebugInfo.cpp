#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Debug/DebugInfo.h"
#include "Backend/Micro/MachineCode.h"
#include "Compiler/Lexer/Lexer.h"
#include "Main/CompilerInstance.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CV_SIGNATURE_C13    = 4;
    constexpr uint32_t K_CV_TYPE_SIGNATURE   = 4;
    constexpr uint32_t K_CV_FIRST_NONPRIM    = 0x1000;
    constexpr uint32_t K_DEBUG_S_SYMBOLS     = 0xF1;
    constexpr uint32_t K_DEBUG_S_STRINGTABLE = 0xF3;
    constexpr uint32_t K_DEBUG_S_FILECHKSMS  = 0xF4;
    constexpr uint16_t K_S_FRAMEPROC         = 0x1012;
    constexpr uint16_t K_S_OBJNAME           = 0x1101;
    constexpr uint16_t K_S_CONSTANT          = 0x1107;
    constexpr uint16_t K_S_UDT               = 0x1108;
    constexpr uint16_t K_S_LDATA32           = 0x110C;
    constexpr uint16_t K_S_GDATA32           = 0x110D;
    constexpr uint16_t K_S_REGREL32          = 0x1111;
    constexpr uint16_t K_S_GPROC32_ID        = 0x1147;
    constexpr uint16_t K_S_BUILDINFO         = 0x114C;
    constexpr uint16_t K_S_PROC_ID_END       = 0x114F;
    constexpr uint16_t K_LF_MODIFIER         = 0x1001;
    constexpr uint16_t K_LF_PROCEDURE        = 0x1008;
    constexpr uint16_t K_LF_ARGLIST          = 0x1201;
    constexpr uint16_t K_LF_FUNC_ID          = 0x1601;
    constexpr uint16_t K_LF_BUILDINFO        = 0x1603;
    constexpr uint16_t K_LF_STRING_ID        = 0x1605;
    constexpr uint8_t  K_CHKSUM_TYPE_NONE    = 0x00;

    uint32_t alignUp4(const uint32_t value)
    {
        return (value + 3u) & ~3u;
    }

    uint16_t readU16(const ByteSpan bytes, const uint32_t offset)
    {
        SWC_ASSERT(offset + sizeof(uint16_t) <= bytes.size());
        uint16_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    uint32_t readU32(const ByteSpan bytes, const uint32_t offset)
    {
        SWC_ASSERT(offset + sizeof(uint32_t) <= bytes.size());
        uint32_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    const NativeSectionData* findSection(const DebugInfoObjectResult& result, const Utf8& sectionName)
    {
        for (const NativeSectionData& section : result.sections)
        {
            if (section.name == sectionName)
                return &section;
        }

        return nullptr;
    }

    bool bytesContainString(const ByteSpan bytes, const Utf8& value)
    {
        if (value.empty())
            return true;

        const ByteSpan needle = asByteSpan(std::string_view(value.data(), value.size()));
        return std::ranges::search(bytes, needle).begin() != bytes.end();
    }

    bool symbolsSubsectionContainsRecord(const ByteSpan bytes, const uint16_t recordType)
    {
        if (bytes.size() < sizeof(uint32_t))
            return false;
        if (readU32(bytes, 0) != K_CV_SIGNATURE_C13)
            return false;

        uint32_t cursor = sizeof(uint32_t);
        while (cursor + 8 <= bytes.size())
        {
            const uint32_t subsectionType = readU32(bytes, cursor + 0);
            const uint32_t subsectionSize = readU32(bytes, cursor + 4);
            cursor += 8;

            if (cursor + subsectionSize > bytes.size())
                return false;

            if (subsectionType == K_DEBUG_S_SYMBOLS)
            {
                uint32_t       recordCursor = cursor;
                const uint32_t recordEnd    = cursor + subsectionSize;
                while (recordCursor + 4 <= recordEnd)
                {
                    const uint16_t recordSize       = readU16(bytes, recordCursor + 0);
                    const uint32_t nextRecordCursor = recordCursor + sizeof(uint16_t) + recordSize;
                    if (nextRecordCursor > recordEnd)
                        return false;

                    if (readU16(bytes, recordCursor + sizeof(uint16_t)) == recordType)
                        return true;

                    recordCursor = nextRecordCursor;
                }
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return false;
    }

    uint32_t countSymbolsSubsections(const ByteSpan bytes)
    {
        if (bytes.size() < sizeof(uint32_t) || readU32(bytes, 0) != K_CV_SIGNATURE_C13)
            return 0;

        uint32_t count  = 0;
        uint32_t cursor = sizeof(uint32_t);
        while (cursor + 8 <= bytes.size())
        {
            const uint32_t subsectionType = readU32(bytes, cursor + 0);
            const uint32_t subsectionSize = readU32(bytes, cursor + 4);
            cursor += 8;
            if (cursor + subsectionSize > bytes.size())
                return 0;
            if (subsectionType == K_DEBUG_S_SYMBOLS)
                count++;
            cursor = alignUp4(cursor + subsectionSize);
        }

        return count;
    }

    bool typeSectionContainsLeafs(const ByteSpan bytes, const std::span<const uint16_t> expectedKinds)
    {
        if (bytes.size() < sizeof(uint32_t))
            return false;
        if (readU32(bytes, 0) != K_CV_TYPE_SIGNATURE)
            return false;

        uint32_t              cursor            = sizeof(uint32_t);
        uint32_t              expectedTypeIndex = K_CV_FIRST_NONPRIM;
        std::vector<uint16_t> actualKinds;
        while (cursor + 4 <= bytes.size())
        {
            const uint16_t recordLength = readU16(bytes, cursor + 0);
            if (!recordLength)
                return false;

            const uint32_t nextCursor = cursor + sizeof(uint16_t) + recordLength;
            if (nextCursor > bytes.size())
                return false;

            SWC_UNUSED(expectedTypeIndex);
            expectedTypeIndex++;
            actualKinds.push_back(readU16(bytes, cursor + sizeof(uint16_t)));
            cursor = nextCursor;
        }

        if (cursor != bytes.size())
            return false;
        if (actualKinds.size() != expectedKinds.size())
            return false;

        for (size_t i = 0; i < expectedKinds.size(); ++i)
        {
            if (actualKinds[i] != expectedKinds[i])
                return false;
        }

        return true;
    }

    bool typeSectionContainsLeaf(const ByteSpan bytes, const uint16_t expectedKind)
    {
        if (bytes.size() < sizeof(uint32_t))
            return false;
        if (readU32(bytes, 0) != K_CV_TYPE_SIGNATURE)
            return false;

        uint32_t cursor = sizeof(uint32_t);
        while (cursor + 4 <= bytes.size())
        {
            const uint16_t recordLength = readU16(bytes, cursor + 0);
            if (!recordLength)
                return false;

            const uint32_t nextCursor = cursor + sizeof(uint16_t) + recordLength;
            if (nextCursor > bytes.size())
                return false;

            if (readU16(bytes, cursor + sizeof(uint16_t)) == expectedKind)
                return true;

            cursor = nextCursor;
        }

        return cursor == bytes.size();
    }

    bool fileChecksumsSubsectionContainsKind(const ByteSpan bytes, const uint8_t expectedKind, const uint8_t expectedSize)
    {
        if (bytes.size() < sizeof(uint32_t))
            return false;
        if (readU32(bytes, 0) != K_CV_SIGNATURE_C13)
            return false;

        uint32_t cursor = sizeof(uint32_t);
        while (cursor + 8 <= bytes.size())
        {
            const uint32_t subsectionType = readU32(bytes, cursor + 0);
            const uint32_t subsectionSize = readU32(bytes, cursor + 4);
            cursor += 8;

            if (cursor + subsectionSize > bytes.size())
                return false;

            if (subsectionType == K_DEBUG_S_FILECHKSMS)
            {
                uint32_t       entryCursor = cursor;
                const uint32_t entryEnd    = cursor + subsectionSize;
                while (entryCursor + 6 <= entryEnd)
                {
                    const uint8_t  checksumSize    = static_cast<uint8_t>(bytes[entryCursor + 4]);
                    const uint8_t  checksumKind    = static_cast<uint8_t>(bytes[entryCursor + 5]);
                    const uint32_t nextEntryCursor = alignUp4(entryCursor + 6 + checksumSize);
                    if (nextEntryCursor > entryEnd)
                        return false;

                    if (checksumKind == expectedKind && checksumSize == expectedSize)
                        return true;

                    entryCursor = nextEntryCursor;
                }

                return false;
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return false;
    }

    bool subsectionTypeAppearsBefore(const ByteSpan bytes, const uint32_t firstType, const uint32_t secondType)
    {
        if (bytes.size() < sizeof(uint32_t))
            return false;
        if (readU32(bytes, 0) != K_CV_SIGNATURE_C13)
            return false;

        bool     sawFirst = false;
        uint32_t cursor   = sizeof(uint32_t);
        while (cursor + 8 <= bytes.size())
        {
            const uint32_t subsectionType = readU32(bytes, cursor + 0);
            const uint32_t subsectionSize = readU32(bytes, cursor + 4);
            cursor += 8;

            if (cursor + subsectionSize > bytes.size())
                return false;

            if (subsectionType == firstType)
                sawFirst = true;
            if (subsectionType == secondType)
                return sawFirst;

            cursor = alignUp4(cursor + subsectionSize);
        }

        return false;
    }

    DebugInfoLocalRecord makeDebugLocalRecord(const Utf8& name, const TypeRef typeRef, const uint32_t offset, const MicroReg baseReg)
    {
        DebugInfoLocalRecord record;
        record.name    = name;
        record.typeRef = typeRef;
        record.offset  = offset;
        record.baseReg = baseReg;
        return record;
    }

    DebugInfoDataRecord makeDebugDataRecord(const Utf8& name, const TypeRef typeRef, const Utf8& symbolName, const Utf8& sectionName, const uint32_t symbolOffset, const bool isGlobal)
    {
        DebugInfoDataRecord record;
        record.name         = name;
        record.typeRef      = typeRef;
        record.symbolName   = symbolName;
        record.sectionName  = sectionName;
        record.symbolOffset = symbolOffset;
        record.isGlobal     = isGlobal;
        return record;
    }

    DebugInfoConstantRecord makeDebugConstantRecord(const Utf8& name, const TypeRef typeRef, const ConstantRef valueRef)
    {
        DebugInfoConstantRecord record;
        record.name     = name;
        record.typeRef  = typeRef;
        record.isConst  = true;
        record.valueRef = valueRef;
        return record;
    }
}

SWC_TEST_BEGIN(DebugInfo_EmitsWindowsSymbolAndTypeRecords)
{
    MachineCode code;
    code.bytes.push_back(std::byte{0xC3});

    static constexpr std::string_view OBJECT_NAME = "C:\\swc\\debug-info-test.obj";
    static constexpr std::string_view DEBUG_NAME  = "debug::proc";

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_test_proc",
        .debugName   = DEBUG_NAME,
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path(OBJECT_NAME),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT_VERIFY(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;
    if (debugSection->relocations.size() != 2)
        return Result::Error;

    const ByteSpan debugBytes = asByteSpan(debugSection->bytes);
    if (countSymbolsSubsections(debugBytes) != 3)
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_OBJNAME))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_GPROC32_ID))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_BUILDINFO))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_FRAMEPROC))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_PROC_ID_END))
        return Result::Error;
    if (!bytesContainString(debugBytes, Utf8(OBJECT_NAME)))
        return Result::Error;
    if (!bytesContainString(debugBytes, Utf8(DEBUG_NAME)))
        return Result::Error;

    const NativeSectionData* typeSection = findSection(debugInfo, ".debug$T");
    if (!typeSection)
        return Result::Error;
    const ByteSpan              typeBytes      = asByteSpan(typeSection->bytes);
    static constexpr std::array EXPECTED_LEAFS = {
        K_LF_ARGLIST,
        K_LF_PROCEDURE,
        K_LF_FUNC_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_BUILDINFO,
    };
    if (!typeSectionContainsLeafs(typeBytes, EXPECTED_LEAFS))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_EmitsWindowsVariableAndConstantRecords)
{
    MachineCode code;
    code.bytes.push_back(std::byte{0xC3});

    const ConstantRef constantRef = ctx.cstMgr().addS32(ctx, 42);

    const DebugInfoLocalRecord    parameter        = makeDebugLocalRecord("arg0", ctx.typeMgr().typeS32(), 32, MicroReg::intReg(4));
    const DebugInfoLocalRecord    local            = makeDebugLocalRecord("local0", ctx.typeMgr().typeS32(), 0, MicroReg::intReg(4));
    const DebugInfoConstantRecord functionConstant = makeDebugConstantRecord("kLocal", ctx.typeMgr().typeS32(), constantRef);

    const std::array parameters = {parameter};
    const std::array locals     = {local};
    const std::array fnConsts   = {functionConstant};

    const DebugInfoFunctionRecord function = {
        .symbolName    = "__swc_debug_info_vars_proc",
        .debugName     = "debug::vars",
        .returnTypeRef = ctx.typeMgr().typeS32(),
        .machineCode   = &code,
        .frameSize     = 32,
        .frameBaseReg  = MicroReg::intReg(4),
        .parameters    = parameters,
        .locals        = locals,
        .constants     = fnConsts,
    };

    const DebugInfoDataRecord     global         = makeDebugDataRecord("gValue", ctx.typeMgr().typeS32(), "__swc_dbg_data_test_global", ".data", 16, true);
    const DebugInfoConstantRecord globalConstant = makeDebugConstantRecord("kGlobal", ctx.typeMgr().typeS32(), constantRef);

    const std::array functions = {function};
    const std::array globals   = {global};
    const std::array constants = {globalConstant};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-vars.obj"),
        .functions    = functions,
        .globals      = globals,
        .constants    = constants,
        .emitCodeView = true,
    };

    SWC_RESULT_VERIFY(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;
    if (debugSection->relocations.size() != 4)
        return Result::Error;

    const ByteSpan debugBytes = asByteSpan(debugSection->bytes);
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_REGREL32))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_GDATA32) && !symbolsSubsectionContainsRecord(debugBytes, K_S_LDATA32))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_CONSTANT))
        return Result::Error;

    const NativeSectionData* typeSection = findSection(debugInfo, ".debug$T");
    if (!typeSection)
        return Result::Error;
    const ByteSpan typeBytes = asByteSpan(typeSection->bytes);
    if (!typeSectionContainsLeaf(typeBytes, K_LF_MODIFIER))
        return Result::Error;

    bool sawDebugGlobal = false;
    for (const DebugInfoDefinedSymbol& symbol : debugInfo.symbols)
    {
        if (symbol.name != "__swc_dbg_data_test_global")
            continue;

        sawDebugGlobal = symbol.sectionName == ".data" && symbol.value == 16;
        break;
    }

    if (!sawDebugGlobal)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_EmitsWindowsSourceChecksums)
{
    const uint32_t uniqueId   = ctx.compiler().atomicId().fetch_add(1, std::memory_order_relaxed);
    const fs::path sourcePath = fs::temp_directory_path() / std::format("swc_debug_info_checksum_{:08x}.swg", uniqueId);

    {
        std::ofstream output(sourcePath, std::ios::binary);
        output << "token\n";
    }

    SourceFile& sourceFile = ctx.compiler().addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT_VERIFY(sourceFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().tokens().empty())
        return Result::Error;

    MachineCode code;
    code.bytes.push_back(std::byte{0xC3});
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .sourceCodeRef   = {.srcViewRef = sourceFile.ast().srcView().ref(), .tokRef = TokenRef(0)},
    });

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_checksum_proc",
        .debugName   = "debug::checksum",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-checksum.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT_VERIFY(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    const ByteSpan debugBytes = asByteSpan(debugSection->bytes);
    if (!bytesContainString(debugBytes, Utf8(sourcePath.string())))
        return Result::Error;
    if (!fileChecksumsSubsectionContainsKind(debugBytes, K_CHKSUM_TYPE_NONE, 0))
        return Result::Error;
    if (!subsectionTypeAppearsBefore(debugBytes, K_DEBUG_S_FILECHKSMS, K_DEBUG_S_STRINGTABLE))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_BUILDINFO))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

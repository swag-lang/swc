#include "pch.h"
#include "Support/Report/Assert.h"

#if SWC_HAS_UNITTEST

#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugRecordCollector.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Lexer/Lexer.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Core/ByteArray.h"
#include "Support/Math/Sha256.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CV_SIGNATURE_C13    = 4;
    constexpr uint32_t K_CV_TYPE_SIGNATURE   = 4;
    constexpr uint32_t K_CV_FIRST_NONPRIM    = 0x1000;
    constexpr uint32_t K_CV_LINE_NUMBER_MASK = 0x00FFFFFFu;
    constexpr uint32_t K_DEBUG_S_SYMBOLS     = 0xF1;
    constexpr uint32_t K_DEBUG_S_LINES       = 0xF2;
    constexpr uint32_t K_DEBUG_S_STRINGTABLE = 0xF3;
    constexpr uint32_t K_DEBUG_S_FILECHKSMS  = 0xF4;
    constexpr uint16_t K_S_FRAMEPROC         = 0x1012;
    constexpr uint16_t K_S_OBJNAME           = 0x1101;
    constexpr uint16_t K_S_CONSTANT          = 0x1107;
    constexpr uint16_t K_S_LDATA32           = 0x110C;
    constexpr uint16_t K_S_GDATA32           = 0x110D;
    constexpr uint16_t K_S_REGREL32          = 0x1111;
    constexpr uint16_t K_S_GPROC32_ID        = 0x1147;
    constexpr uint16_t K_S_BUILDINFO         = 0x114C;
    constexpr uint16_t K_S_PROC_ID_END       = 0x114F;
    constexpr uint16_t K_CV_REG_RBX          = 329;
    constexpr uint16_t K_CV_REG_RSP          = 335;
    constexpr uint16_t K_LF_MODIFIER         = 0x1001;
    constexpr uint16_t K_LF_PROCEDURE        = 0x1008;
    constexpr uint16_t K_LF_ARGLIST          = 0x1201;
    constexpr uint16_t K_LF_FUNC_ID          = 0x1601;
    constexpr uint16_t K_LF_BUILDINFO        = 0x1603;
    constexpr uint16_t K_LF_STRING_ID        = 0x1605;
    constexpr uint8_t  K_CHKSUM_TYPE_SHA256  = 0x03;

    uint32_t alignUp4(const uint32_t value)
    {
        return (value + 3u) & ~3u;
    }

    uint16_t readU16(const std::span<const std::byte> bytes, const uint32_t offset)
    {
        SWC_ASSERT(offset + sizeof(uint16_t) <= bytes.size());
        uint16_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    uint32_t readU32(const std::span<const std::byte> bytes, const uint32_t offset)
    {
        SWC_ASSERT(offset + sizeof(uint32_t) <= bytes.size());
        uint32_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    void appendU32(ByteArray& bytes, const uint32_t value)
    {
        const auto* src = reinterpret_cast<const std::byte*>(&value);
        bytes.insert(bytes.end(), src, src + sizeof(value));
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

    bool bytesContainString(const std::span<const std::byte> bytes, const Utf8& value)
    {
        const std::span<const std::byte> needle{reinterpret_cast<const std::byte*>(value.data()), value.size()};
        if (needle.empty())
            return true;
        if (needle.size() > bytes.size())
            return false;
        return std::ranges::search(bytes, needle).begin() != bytes.end();
    }

    bool countSymbolsSubsectionRecords(const std::span<const std::byte> bytes, const uint16_t recordType, uint32_t& outCount)
    {
        outCount = 0;
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
                        outCount++;

                    recordCursor = nextRecordCursor;
                }
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return true;
    }

    bool tryFindRegRelativeSymbol(const std::span<const std::byte> bytes, const Utf8& expectedName, uint16_t& outRegister, uint32_t& outOffset)
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

                    if (readU16(bytes, recordCursor + sizeof(uint16_t)) == K_S_REGREL32)
                    {
                        const uint32_t nameOffset = recordCursor + 14;
                        const uint32_t nameEnd    = nextRecordCursor;
                        uint32_t       cursorName = nameOffset;
                        while (cursorName < nameEnd && bytes[cursorName] != std::byte{0})
                            cursorName++;
                        if (cursorName >= nameEnd)
                            return false;

                        const Utf8 name{std::string_view(reinterpret_cast<const char*>(bytes.data() + nameOffset), cursorName - nameOffset)};
                        if (name == expectedName)
                        {
                            outOffset   = readU32(bytes, recordCursor + 4);
                            outRegister = readU16(bytes, recordCursor + 12);
                            return true;
                        }
                    }

                    recordCursor = nextRecordCursor;
                }
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return false;
    }

    uint32_t countSymbolsSubsections(const std::span<const std::byte> bytes)
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

    bool typeSectionContainsLeafs(const std::span<const std::byte> bytes, const std::span<const uint16_t> expectedKinds)
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

    bool typeSectionContainsLeaf(const std::span<const std::byte> bytes, const uint16_t expectedKind)
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

    bool fileChecksumsSubsectionContainsKind(const std::span<const std::byte> bytes, const uint8_t expectedKind, const uint8_t expectedSize)
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

    bool subsectionTypeAppearsBefore(const std::span<const std::byte> bytes, const uint32_t firstType, const uint32_t secondType)
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

    bool tryReadFirstLineBlockLines(const std::span<const std::byte> bytes, std::vector<uint32_t>& outLines)
    {
        outLines.clear();
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

            if (subsectionType == K_DEBUG_S_LINES)
            {
                if (subsectionSize < 24)
                    return false;

                const uint32_t blockOffset = cursor + 12;
                const uint32_t lineCount   = readU32(bytes, blockOffset + 4);
                const uint32_t blockSize   = readU32(bytes, blockOffset + 8);
                if (blockSize < 12)
                    return false;

                const uint32_t entriesOffset = blockOffset + 12;
                const uint32_t entriesSize   = lineCount * 8;
                if (entriesOffset + entriesSize > cursor + subsectionSize)
                    return false;

                outLines.reserve(lineCount);
                for (uint32_t i = 0; i < lineCount; ++i)
                {
                    const uint32_t lineInfo = readU32(bytes, entriesOffset + i * 8 + 4);
                    outLines.push_back(lineInfo & K_CV_LINE_NUMBER_MASK);
                }

                return true;
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return false;
    }

    bool tryReadFirstLineBlockFirstCodeOffset(const std::span<const std::byte> bytes, uint32_t& outCodeOffset)
    {
        outCodeOffset = 0;
        if (bytes.size() < sizeof(uint32_t) || readU32(bytes, 0) != K_CV_SIGNATURE_C13)
            return false;

        uint32_t cursor = sizeof(uint32_t);
        while (cursor + 8 <= bytes.size())
        {
            const uint32_t subsectionType = readU32(bytes, cursor + 0);
            const uint32_t subsectionSize = readU32(bytes, cursor + 4);
            cursor += 8;

            if (cursor + subsectionSize > bytes.size())
                return false;

            if (subsectionType == K_DEBUG_S_LINES)
            {
                if (subsectionSize < 24)
                    return false;
                const uint32_t blockOffset   = cursor + 12;
                const uint32_t lineCount     = readU32(bytes, blockOffset + 4);
                const uint32_t entriesOffset = blockOffset + 12;
                if (lineCount == 0 || entriesOffset + 8 > cursor + subsectionSize)
                    return false;
                outCodeOffset = readU32(bytes, entriesOffset + 0);
                return true;
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return true;
    }

    bool symbolsSubsectionContainsRecord(const std::span<const std::byte> bytes, const uint16_t recordType)
    {
        uint32_t count = 0;
        return countSymbolsSubsectionRecords(bytes, recordType, count) && count != 0;
    }

    bool countLineRecords(const std::span<const std::byte> bytes, const uint32_t expectedLine, uint32_t& outCount)
    {
        outCount = 0;
        if (bytes.size() < sizeof(uint32_t) || readU32(bytes, 0) != K_CV_SIGNATURE_C13)
            return false;

        uint32_t cursor = sizeof(uint32_t);
        while (cursor + 8 <= bytes.size())
        {
            const uint32_t subsectionType = readU32(bytes, cursor + 0);
            const uint32_t subsectionSize = readU32(bytes, cursor + 4);
            cursor += 8;

            if (cursor + subsectionSize > bytes.size())
                return false;

            if (subsectionType == K_DEBUG_S_LINES)
            {
                if (subsectionSize < 12)
                    return false;

                uint32_t blockOffset = cursor + 12;
                while (blockOffset + 12 <= cursor + subsectionSize)
                {
                    const uint32_t lineCount = readU32(bytes, blockOffset + 4);
                    const uint32_t blockSize = readU32(bytes, blockOffset + 8);
                    if (blockSize < 12)
                        return false;

                    const uint32_t entriesOffset = blockOffset + 12;
                    const uint32_t entriesSize   = lineCount * 8;
                    if (entriesOffset + entriesSize > cursor + subsectionSize)
                        return false;

                    for (uint32_t i = 0; i < lineCount; ++i)
                    {
                        const uint32_t lineInfo = readU32(bytes, entriesOffset + i * 8 + 4);
                        if ((lineInfo & K_CV_LINE_NUMBER_MASK) == expectedLine)
                            outCount++;
                    }

                    blockOffset += blockSize;
                }
            }

            cursor = alignUp4(cursor + subsectionSize);
        }

        return true;
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

    Utf8 debugDataSectionName(const SymbolVariable& symbol)
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
}

SWC_TEST_BEGIN(DebugInfo_EmitsWindowsSymbolAndTypeRecords)
{
    MachineCode code;
    code.bytes.pushBack(std::byte{0xC3});

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

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;
    if (debugSection->relocations.size() != 2)
        return Result::Error;

    const std::span<const std::byte> debugBytes = debugSection->bytes.span();
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
    const std::span<const std::byte>              typeBytes      = typeSection->bytes.span();
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

SWC_TEST_BEGIN(DebugInfo_PdbInfoEmitsWindowsBuildInfo)
{
    MachineCode code;
    code.bytes.pushBack(std::byte{0xC3});

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_pdb_proc",
        .debugName   = "debug::pdb",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoPdbResult           pdbInfo;
    const DebugInfoObjectRequest request = {
        .ctx        = &ctx,
        .targetOs   = Runtime::TargetOs::Windows,
        .objectPath = fs::path("C:\\swc\\debug-info-pdb.obj"),
        .functions  = functions,
    };

    DebugInfo::buildPdbInfo(request, pdbInfo);

    if (pdbInfo.buildInfoIndex != K_CV_FIRST_NONPRIM + 5)
        return Result::Error;
    if (pdbInfo.ipiIndexEnd != K_CV_FIRST_NONPRIM + 6)
        return Result::Error;

    ByteArray idBytes;
    appendU32(idBytes, K_CV_TYPE_SIGNATURE);
    idBytes.insert(idBytes.end(), pdbInfo.ipiRecords.begin(), pdbInfo.ipiRecords.end());

    static constexpr std::array EXPECTED_ID_LEAFS = {
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_STRING_ID,
        K_LF_BUILDINFO,
    };
    if (!typeSectionContainsLeafs(idBytes.span(), EXPECTED_ID_LEAFS))
        return Result::Error;
    if (!bytesContainString(idBytes.span(), Utf8("debug-info-pdb.pdb")))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_EmitsWindowsVariableAndConstantRecords)
{
    MachineCode code;
    code.bytes.pushBack(std::byte{0xC3});

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

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;
    if (debugSection->relocations.size() != 4)
        return Result::Error;

    const std::span<const std::byte> debugBytes = debugSection->bytes.span();
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_REGREL32))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_GDATA32) && !symbolsSubsectionContainsRecord(debugBytes, K_S_LDATA32))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_CONSTANT))
        return Result::Error;

    const NativeSectionData* typeSection = findSection(debugInfo, ".debug$T");
    if (!typeSection)
        return Result::Error;
    const std::span<const std::byte> typeBytes = typeSection->bytes.span();
    if (!typeSectionContainsLeaf(typeBytes, K_LF_MODIFIER))
        return Result::Error;

    const Utf8 expectedDataBaseSymbol = nativeScopedSectionBaseSymbol(ctx.compiler(), K_DATA_BASE_SYMBOL);
    bool       sawDataBaseRelocation  = false;
    for (const NativeSectionRelocation& relocation : debugSection->relocations)
    {
        if (relocation.symbolName != expectedDataBaseSymbol)
            continue;

        if (relocation.type != IMAGE_REL_AMD64_SECREL)
            continue;
        if (relocation.addend != 16)
            return Result::Error;

        sawDataBaseRelocation = true;
        break;
    }

    for (const DebugInfoDefinedSymbol& symbol : debugInfo.symbols)
    {
        if (symbol.name == "__swc_dbg_data_test_global")
            return Result::Error;
    }

    if (!sawDataBaseRelocation)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_UsesPerVariableBaseRegistersForRegRelativeSymbols)
{
    MachineCode code;
    code.bytes.pushBack(std::byte{0xC3});

    const DebugInfoLocalRecord parameter = makeDebugLocalRecord("arg0", ctx.typeMgr().typeS32(), 32, MicroReg::intReg(4));
    const DebugInfoLocalRecord local     = makeDebugLocalRecord("local0", ctx.typeMgr().typeS32(), 16, MicroReg::intReg(1));

    const std::array parameters = {parameter};
    const std::array locals     = {local};

    const DebugInfoFunctionRecord function = {
        .symbolName    = "__swc_debug_info_regrel_proc",
        .debugName     = "debug::regrel",
        .returnTypeRef = ctx.typeMgr().typeS32(),
        .machineCode   = &code,
        .frameSize     = 64,
        .frameBaseReg  = MicroReg::intReg(4),
        .parameters    = parameters,
        .locals        = locals,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-regrel.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    const std::span<const std::byte> debugBytes    = debugSection->bytes.span();
    uint16_t       paramRegister = 0;
    uint16_t       localRegister = 0;
    uint32_t       paramOffset   = 0;
    uint32_t       localOffset   = 0;
    if (!tryFindRegRelativeSymbol(debugBytes, "arg0", paramRegister, paramOffset))
        return Result::Error;
    if (!tryFindRegRelativeSymbol(debugBytes, "local0", localRegister, localOffset))
        return Result::Error;
    if (paramRegister != K_CV_REG_RSP || paramOffset != 32)
        return Result::Error;
    if (localRegister != K_CV_REG_RBX || localOffset != 16)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_CollapsesConsecutiveSameLineEntries)
{
    SourceFile& sourceFile = Unittest::addTestSource(ctx, "DebugInfo", "CollapsesConsecutiveSameLineEntries", "alpha beta\n"
                                                                                                              "gamma\n");
    SWC_RESULT(sourceFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, sourceFile.ast().srcView(), LexerFlagsE::Default);

    const SourceView& srcView = sourceFile.ast().srcView();
    TokenRef          line1Tok0;
    TokenRef          line1Tok1;
    TokenRef          line2Tok0;
    for (uint32_t i = 0; i < srcView.tokens().size(); ++i)
    {
        const TokenRef        tokRef(i);
        const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, tokRef);
        if (!codeRange.line)
            continue;

        if (codeRange.line == 1)
        {
            if (!line1Tok0.isValid())
                line1Tok0 = tokRef;
            else if (!line1Tok1.isValid())
                line1Tok1 = tokRef;
        }
        else if (codeRange.line == 2 && !line2Tok0.isValid())
        {
            line2Tok0 = tokRef;
        }
    }

    if (!line1Tok0.isValid() || !line1Tok1.isValid() || !line2Tok0.isValid())
        return Result::Error;

    MachineCode code;
    code.bytes = {std::byte{0x90}, std::byte{0x90}, std::byte{0xC3}};
    code.debugSourceRanges.push_back({.codeStartOffset = 0, .codeEndOffset = 1, .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line1Tok0}}});
    code.debugSourceRanges.push_back({.codeStartOffset = 1, .codeEndOffset = 2, .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line1Tok1}}});
    code.debugSourceRanges.push_back({.codeStartOffset = 2, .codeEndOffset = 3, .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line2Tok0}}});

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_lines_proc",
        .debugName   = "debug::lines",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-lines.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    std::vector<uint32_t> lines;
    if (!tryReadFirstLineBlockLines(debugSection->bytes.span(), lines))
        return Result::Error;
    if (lines.size() != 2)
        return Result::Error;
    if (lines[0] != 1 || lines[1] != 2)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_SkipsNoStepLineEntries)
{
    SourceFile& sourceFile = Unittest::addTestSource(ctx, "DebugInfo", "SkipsNoStepLineEntries", "alpha\n"
                                                                                                 "beta\n"
                                                                                                 "gamma\n");
    SWC_RESULT(sourceFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, sourceFile.ast().srcView(), LexerFlagsE::Default);

    const SourceView& srcView = sourceFile.ast().srcView();
    TokenRef          line1Tok;
    TokenRef          line2Tok;
    TokenRef          line3Tok;
    for (uint32_t i = 0; i < srcView.tokens().size(); ++i)
    {
        const TokenRef        tokRef(i);
        const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, tokRef);
        if (!codeRange.line)
            continue;

        if (codeRange.line == 1 && !line1Tok.isValid())
            line1Tok = tokRef;
        else if (codeRange.line == 2 && !line2Tok.isValid())
            line2Tok = tokRef;
        else if (codeRange.line == 3 && !line3Tok.isValid())
            line3Tok = tokRef;
    }

    if (!line1Tok.isValid() || !line2Tok.isValid() || !line3Tok.isValid())
        return Result::Error;

    MachineCode code;
    code.bytes = {std::byte{0x90}, std::byte{0x90}, std::byte{0xC3}};
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line1Tok}},
    });
    code.debugSourceRanges.push_back({
        .codeStartOffset = 1,
        .codeEndOffset   = 2,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line2Tok}, .debugNoStep = true},
    });
    code.debugSourceRanges.push_back({
        .codeStartOffset = 2,
        .codeEndOffset   = 3,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line3Tok}},
    });

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_nostep_proc",
        .debugName   = "debug::nostep",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-nostep.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    std::vector<uint32_t> lines;
    if (!tryReadFirstLineBlockLines(debugSection->bytes.span(), lines))
        return Result::Error;
    if (lines.size() != 2)
        return Result::Error;
    if (lines[0] != 1 || lines[1] != 3)
        return Result::Error;
}
SWC_TEST_END()

// The prologue is non-step-visible, so its source range is dropped from the line table. The first
// emitted line record must still cover code offset 0, otherwise the function entry and prologue have
// no source mapping (breakpoints at entry / samples in the prologue resolve to nothing).
SWC_TEST_BEGIN(DebugInfo_FirstLineCoversEntry)
{
    SourceFile& sourceFile = Unittest::addTestSource(ctx, "DebugInfo", "FirstLineCoversEntry", "alpha\n"
                                                                                               "beta\n");
    SWC_RESULT(sourceFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, sourceFile.ast().srcView(), LexerFlagsE::Default);

    const SourceView& srcView = sourceFile.ast().srcView();
    TokenRef          line1Tok;
    TokenRef          line2Tok;
    for (uint32_t i = 0; i < srcView.tokens().size(); ++i)
    {
        const TokenRef        tokRef(i);
        const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, tokRef);
        if (!codeRange.line)
            continue;
        if (codeRange.line == 1 && !line1Tok.isValid())
            line1Tok = tokRef;
        else if (codeRange.line == 2 && !line2Tok.isValid())
            line2Tok = tokRef;
    }

    if (!line1Tok.isValid() || !line2Tok.isValid())
        return Result::Error;

    MachineCode code;
    code.bytes = {std::byte{0x90}, std::byte{0x90}, std::byte{0xC3}};
    // Prologue range at offset 0 is non-step-visible (dropped from the line table)...
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line1Tok}, .debugNoStep = true},
    });
    // ...the first step-visible range starts past the entry, at offset 1.
    code.debugSourceRanges.push_back({
        .codeStartOffset = 1,
        .codeEndOffset   = 3,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = line2Tok}},
    });

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_entry_proc",
        .debugName   = "debug::entry",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-entry.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    // Only the step-visible body line (2) is emitted, but its record must start at offset 0.
    std::vector<uint32_t> lines;
    if (!tryReadFirstLineBlockLines(debugSection->bytes.span(), lines))
        return Result::Error;
    if (lines.size() != 1 || lines[0] != 2)
        return Result::Error;

    uint32_t firstCodeOffset = 0xFFFFFFFF;
    if (!tryReadFirstLineBlockFirstCodeOffset(debugSection->bytes.span(), firstCodeOffset))
        return Result::Error;
    if (firstCodeOffset != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_ResolvesNoStepBackendSourceInfo)
{
    SourceFile& sourceFile = Unittest::addTestSource(ctx, "DebugInfo", "ResolvesNoStepBackendSourceInfo", "alpha\n");
    SWC_RESULT(sourceFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, sourceFile.ast().srcView(), LexerFlagsE::Default);

    const SourceView& srcView = sourceFile.ast().srcView();
    TokenRef          tokenRef;
    for (uint32_t i = 0; i < srcView.tokens().size(); ++i)
    {
        const TokenRef        candidate(i);
        const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, candidate);
        if (!codeRange.line)
            continue;

        tokenRef = candidate;
        break;
    }

    if (!tokenRef.isValid())
        return Result::Error;

    const DebugSourceInfo debugSourceInfo = {
        .sourceCodeRef = {.srcViewRef = srcView.ref(), .tokRef = tokenRef},
        .debugNoStep   = true,
    };

    ResolvedDebugSourceInfo resolvedInfo;
    if (!tryResolveDebugSourceInfo(ctx, resolvedInfo, debugSourceInfo))
        return Result::Error;
    if (resolvedInfo.sourceFile != &sourceFile)
        return Result::Error;
    if (resolvedInfo.codeRange.line != 1)
        return Result::Error;

    MachineCode code;
    code.bytes = {std::byte{0x90}};
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .debugSourceInfo = debugSourceInfo,
    });

    MachineCode::ResolvedDebugSourceRange resolvedRange;
    if (!code.tryResolveDebugSourceRangeAtOffset(ctx, resolvedRange, 0))
        return Result::Error;
    if (resolvedRange.debugRange != &code.debugSourceRanges.front())
        return Result::Error;
    if (resolvedRange.source.sourceFile != &sourceFile)
        return Result::Error;
    if (resolvedRange.source.codeRange.line != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_UsesOwnerSourceFileForGeneratedViews)
{
    const fs::path ownerPath     = Unittest::makeTestSourcePath("DebugInfo", "UsesOwnerSourceFileForGeneratedViews");
    const fs::path generatedPath = Unittest::makeTestSourcePath("DebugInfo", "UsesOwnerSourceFileForGeneratedViews.generated");

    SourceFile& ownerFile = Unittest::addTestSource(ctx, ownerPath, "ownerToken\n");
    SWC_RESULT(ownerFile.loadContent(ctx));
    SourceFile& generatedFile = Unittest::addTestSource(ctx, generatedPath, "generatedToken\n");
    SWC_RESULT(generatedFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, ownerFile.ast().srcView(), LexerFlagsE::Default);
    lexer.tokenize(ctx, generatedFile.ast().srcView(), LexerFlagsE::Default);

    SourceView& generatedView = generatedFile.ast().srcView();
    generatedView.setOwnerFileRef(ownerFile.ref());
    if (ctx.compiler().sourceViewFile(generatedView.ref()) != &generatedFile)
        return Result::Error;
    if (ctx.compiler().owningSourceFile(generatedView) != &ownerFile)
        return Result::Error;

    TokenRef tokenRef;
    for (uint32_t i = 0; i < generatedView.tokens().size(); ++i)
    {
        const TokenRef        candidate(i);
        const SourceCodeRange codeRange = generatedView.tokenCodeRange(ctx, candidate);
        if (!codeRange.line)
            continue;

        tokenRef = candidate;
        break;
    }

    if (!tokenRef.isValid())
        return Result::Error;

    const DebugSourceInfo debugSourceInfo = {
        .sourceCodeRef = {.srcViewRef = generatedView.ref(), .tokRef = tokenRef},
    };

    ResolvedDebugSourceInfo resolvedInfo;
    if (!tryResolveDebugSourceInfo(ctx, resolvedInfo, debugSourceInfo))
        return Result::Error;
    if (resolvedInfo.sourceFile != &ownerFile)
        return Result::Error;
    if (resolvedInfo.codeRange.srcView != &generatedView)
        return Result::Error;
    if (resolvedInfo.codeRange.line != 1)
        return Result::Error;

    MachineCode code;
    code.bytes.pushBack(std::byte{0xC3});
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .debugSourceInfo = debugSourceInfo,
    });

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_owner_source_proc",
        .debugName   = "debug::ownerSource",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-owner-source.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    const std::span<const std::byte> debugBytes = debugSection->bytes.span();
    if (!bytesContainString(debugBytes, Utf8(ownerPath.string())))
        return Result::Error;
    if (bytesContainString(debugBytes, Utf8(generatedPath.string())))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_UsesDebugSourceCodeRefForGeneratedViewLines)
{
    const fs::path ownerPath = Unittest::makeTestSourcePath("DebugInfo", "UsesDebugSourceCodeRefForGeneratedViewLines");

    std::string ownerSource;
    std::string generatedSource;
    for (uint32_t i = 1; i <= 160; ++i)
    {
        ownerSource += std::format("ownerLine{}\n", i);
        generatedSource += std::format("generatedLine{}\n", i);
    }

    SourceFile& ownerFile = Unittest::addTestSource(ctx, ownerPath, ownerSource);
    SWC_RESULT(ownerFile.loadContent(ctx));

    Lexer       lexer;
    SourceView& ownerView = ownerFile.ast().srcView();
    lexer.tokenize(ctx, ownerView, LexerFlagsE::Default);

    SourceView& generatedView = ctx.compiler().addBufferedSourceView(ownerFile.ref(), generatedSource);
    lexer.tokenize(ctx, generatedView, LexerFlagsE::Default);

    const auto findTokenAtLine = [&](const SourceView& srcView, const uint32_t expectedLine) {
        for (uint32_t i = 0; i < srcView.tokens().size(); ++i)
        {
            const TokenRef        tokRef(i);
            const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, tokRef);
            if (codeRange.line == expectedLine)
                return tokRef;
        }

        return TokenRef::invalid();
    };

    const TokenRef ownerLine45Tok      = findTokenAtLine(ownerView, 45);
    const TokenRef ownerLine144Tok     = findTokenAtLine(ownerView, 144);
    const TokenRef generatedLine144Tok = findTokenAtLine(generatedView, 144);
    if (!ownerLine45Tok.isValid() || !ownerLine144Tok.isValid() || !generatedLine144Tok.isValid())
        return Result::Error;

    generatedView.setDebugSourceCodeRef({.srcViewRef = ownerView.ref(), .tokRef = ownerLine45Tok});

    const DebugSourceInfo generatedDebugSourceInfo = {
        .sourceCodeRef = {.srcViewRef = generatedView.ref(), .tokRef = generatedLine144Tok},
    };

    ResolvedDebugSourceInfo generatedResolvedInfo;
    if (!tryResolveDebugSourceInfo(ctx, generatedResolvedInfo, generatedDebugSourceInfo))
        return Result::Error;
    if (generatedResolvedInfo.sourceFile != &ownerFile)
        return Result::Error;
    if (generatedResolvedInfo.codeRange.srcView != &ownerView)
        return Result::Error;
    if (generatedResolvedInfo.codeRange.line != 45)
        return Result::Error;

    MachineCode code;
    code.bytes = {std::byte{0x90}, std::byte{0xC3}};
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .debugSourceInfo = generatedDebugSourceInfo,
    });
    code.debugSourceRanges.push_back({
        .codeStartOffset = 1,
        .codeEndOffset   = 2,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = ownerView.ref(), .tokRef = ownerLine144Tok}},
    });

    const DebugInfoFunctionRecord function = {
        .symbolName  = "__swc_debug_info_generated_line_proc",
        .debugName   = "debug::generatedLine",
        .machineCode = &code,
    };

    const std::array functions = {function};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &ctx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-generated-line.obj"),
        .functions    = functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    const std::span<const std::byte> debugBytes = debugSection->bytes.span();
    uint32_t       line45Count;
    uint32_t       line144Count;
    if (!countLineRecords(debugBytes, 45, line45Count))
        return Result::Error;
    if (!countLineRecords(debugBytes, 144, line144Count))
        return Result::Error;
    if (line45Count != 1 || line144Count != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_CompilerTestFunctionsPreserveStackDebugMetadata)
{
    static constexpr std::string_view SOURCE     = R"(#test
{
    var acc: s32 = 0
    acc += 1
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("DebugInfo", "CompilerTestFunctionsPreserveStackDebugMetadata");

    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::SharedLibrary;
    cmdLine.name        = "compiler_test_debug";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const auto& nativeTests = compiler.nativeTestFunctions();
    if (nativeTests.size() != 1)
        return Result::Error;

    const SymbolFunction* testFn = nativeTests.front();
    if (!testFn)
        return Result::Error;
    if (testFn->debugStackFrameSize() == 0)
        return Result::Error;
    if (!testFn->debugStackBaseReg().isValid())
        return Result::Error;
    // The base must be resolved to a physical register after register allocation. CodeView's
    // S_REGREL32 can only name a physical frame register, so a leftover virtual one would make
    // every local silently undecodable and invisible in the debugger.
    if (testFn->debugStackBaseReg().isVirtual() || !testFn->debugStackBaseReg().isInt())
        return Result::Error;

    const TaskContext compilerCtx(compiler);
    bool              sawAcc = false;
    for (const SymbolVariable* local : testFn->localVariables())
    {
        if (!local)
            continue;
        if (local->name(compilerCtx) != "acc")
            continue;

        sawAcc = true;
        if (!local->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return Result::Error;
        break;
    }

    if (!sawAcc)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_RuntimeStorageLocalsStayOutOfCodeView)
{
    static constexpr std::string_view SOURCE     = R"(struct DebugInfoRuntimeStoragePair { left: s32; right: s32 }

func debugInfoRuntimeStorageRead(value: const &DebugInfoRuntimeStoragePair)->s32
{
    return value.left + value.right
}

#test
{
    var visible: DebugInfoRuntimeStoragePair = {left: 1, right: 2}
    @assert(debugInfoRuntimeStorageRead({left: 3, right: 4}) == 7)
    @assert(visible.left == 1)
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("DebugInfo", "RuntimeStorageLocalsStayOutOfCodeView");

    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::SharedLibrary;
    cmdLine.name        = "compiler_runtime_storage_debug";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const auto& nativeTests = compiler.nativeTestFunctions();
    if (nativeTests.size() != 1)
        return Result::Error;

    const SymbolFunction* testFn = nativeTests.front();
    if (!testFn)
        return Result::Error;

    const NativeFunctionInfo* functionInfo = nativeBuilder.tryFindFunctionInfo(*testFn);
    if (!functionInfo)
        return Result::Error;

    TaskContext compilerCtx(compiler);
    uint32_t    expectedParameterRecords = 0;
    for (const SymbolVariable* parameter : testFn->parameters())
    {
        if (!parameter)
            continue;
        if (!parameter->debugStackSlotSize())
            continue;
        if (!parameter->idRef().isValid() || parameter->typeRef().isInvalid() || parameter->name(compilerCtx).empty())
            continue;
        expectedParameterRecords++;
    }

    uint32_t expectedLocalRecords      = 0;
    uint32_t runtimeStorageStackLocals = 0;
    for (const SymbolVariable* local : testFn->localVariables())
    {
        if (!local)
            continue;
        if (!local->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            continue;

        if (local->hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage))
        {
            runtimeStorageStackLocals++;
            continue;
        }

        if (!local->idRef().isValid() || local->typeRef().isInvalid() || local->name(compilerCtx).empty())
            continue;
        expectedLocalRecords++;
    }

    if (!runtimeStorageStackLocals || !expectedLocalRecords)
        return Result::Error;

    const std::array      functions = {functionInfo};
    CollectedDebugRecords debugRecords;
    collectDebugRecords(nativeBuilder, std::span(functions.data(), functions.size()), nullptr, false, debugRecords);
    if (debugRecords.functions.size() != 1 || debugRecords.functionStorage.size() != 1)
        return Result::Error;
    if (debugRecords.functions.front().parameters.size() != expectedParameterRecords)
        return Result::Error;
    if (debugRecords.functions.front().locals.size() != expectedLocalRecords)
        return Result::Error;

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &compilerCtx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-runtime-storage.obj"),
        .functions    = debugRecords.functions,
        .emitCodeView = true,
    };

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    uint32_t regRelativeRecords = 0;
    if (!countSymbolsSubsectionRecords(debugSection->bytes.span(), K_S_REGREL32, regRelativeRecords))
        return Result::Error;
    if (regRelativeRecords != expectedParameterRecords + expectedLocalRecords)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_CompilerFilePrivateGlobalsReachCodeViewDataSymbols)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
var GValue: s32 = 7
#test
{
    @assert(GValue == 7)
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("DebugInfo", "CompilerFilePrivateGlobalsReachCodeViewDataSymbols");

    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.buildCfg    = "debug";
    cmdLine.backendKind = Runtime::BuildCfgBackendKind::SharedLibrary;
    cmdLine.name        = "compiler_fileprivate_global_debug";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    NativeBackendBuilder nativeBuilder(compiler, false);
    if (nativeBuilder.prepare() != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    TaskContext           compilerCtx(compiler);
    const SymbolVariable* globalVar = nullptr;
    for (const SymbolVariable* symbol : nativeBuilder.regularGlobals)
    {
        if (!symbol)
            continue;
        if (symbol->name(compilerCtx) != "GValue")
            continue;

        globalVar = symbol;
        break;
    }

    if (!globalVar || !globalVar->hasGlobalStorage())
        return Result::Error;

    const Utf8 sectionName = debugDataSectionName(*globalVar);
    if (sectionName.empty())
        return Result::Error;

    const DebugInfoDataRecord global = makeDebugDataRecord("GValue", globalVar->typeRef(), "__swc_dbg_fileprivate_global", sectionName, globalVar->offset(), globalVar->isPublic());

    const std::array globals = {global};

    DebugInfoObjectResult        debugInfo;
    const DebugInfoObjectRequest request = {
        .ctx          = &compilerCtx,
        .targetOs     = Runtime::TargetOs::Windows,
        .objectPath   = fs::path("C:\\swc\\debug-info-fileprivate-global.obj"),
        .globals      = globals,
        .emitCodeView = true,
    };

    if (DebugInfo::buildObject(request, debugInfo) != Result::Continue)
        return Result::Error;

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    const std::span<const std::byte> debugBytes = debugSection->bytes.span();
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_LDATA32))
        return Result::Error;
    if (!bytesContainString(debugBytes, "GValue"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DebugInfo_EmitsWindowsSourceChecksums)
{
    const fs::path sourcePath = Unittest::makeTestSourcePath("DebugInfo", "EmitsWindowsSourceChecksums");
    SourceFile&    sourceFile = Unittest::addTestSource(ctx, sourcePath, "token\n");
    SWC_RESULT(sourceFile.loadContent(ctx));

    Lexer lexer;
    lexer.tokenize(ctx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().tokens().empty())
        return Result::Error;

    MachineCode code;
    code.bytes.pushBack(std::byte{0xC3});
    code.debugSourceRanges.push_back({
        .codeStartOffset = 0,
        .codeEndOffset   = 1,
        .debugSourceInfo = {.sourceCodeRef = {.srcViewRef = sourceFile.ast().srcView().ref(), .tokRef = TokenRef(0)}},
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

    SWC_RESULT(DebugInfo::buildObject(request, debugInfo));

    const NativeSectionData* debugSection = findSection(debugInfo, ".debug$S");
    if (!debugSection)
        return Result::Error;

    const std::span<const std::byte> debugBytes = debugSection->bytes.span();
    if (!bytesContainString(debugBytes, Utf8(sourcePath.string())))
        return Result::Error;
    // Modern Visual Studio refuses to show source without a SHA-256 checksum it can verify; the file
    // checksum must carry the real digest of the source content (kind 3, 32 bytes), not a None placeholder.
    if (!fileChecksumsSubsectionContainsKind(debugBytes, K_CHKSUM_TYPE_SHA256, 32))
        return Result::Error;
    const std::string_view sourceView = sourceFile.sourceView();
    const std::array<uint8_t, 32> expectedHash = sha256(std::span<const std::byte>{reinterpret_cast<const std::byte*>(sourceView.data()), sourceView.size()});
    if (!bytesContainString(debugBytes, Utf8(std::string_view(reinterpret_cast<const char*>(expectedHash.data()), expectedHash.size()))))
        return Result::Error;
    if (!subsectionTypeAppearsBefore(debugBytes, K_DEBUG_S_FILECHKSMS, K_DEBUG_S_STRINGTABLE))
        return Result::Error;
    if (!symbolsSubsectionContainsRecord(debugBytes, K_S_BUILDINFO))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

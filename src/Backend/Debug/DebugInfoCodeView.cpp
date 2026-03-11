#include "pch.h"
#include "Backend/Debug/DebugInfoCodeView.h"
#include "Backend/Runtime.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/Version.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

// ReSharper disable IdentifierTypo
// ReSharper disable StringLiteralTypo

namespace
{
    constexpr uint32_t K_CV_SIGNATURE_C13        = 4;
    constexpr uint32_t K_DEBUG_S_SYMBOLS         = 0xF1;
    constexpr uint32_t K_DEBUG_S_LINES           = 0xF2;
    constexpr uint32_t K_DEBUG_S_STRINGTABLE     = 0xF3;
    constexpr uint32_t K_DEBUG_S_FILECHKSMS      = 0xF4;
    constexpr uint16_t K_S_CONSTANT              = 0x1107;
    constexpr uint16_t K_S_UDT                   = 0x1108;
    constexpr uint16_t K_S_LDATA32               = 0x110C;
    constexpr uint16_t K_S_GDATA32               = 0x110D;
    constexpr uint16_t K_S_REGREL32              = 0x1111;
    constexpr uint16_t K_S_FRAMEPROC             = 0x1012;
    constexpr uint16_t K_S_OBJNAME               = 0x1101;
    constexpr uint16_t K_S_GPROC32_ID            = 0x1147;
    constexpr uint16_t K_S_BUILDINFO             = 0x114C;
    constexpr uint16_t K_S_PROC_ID_END           = 0x114F;
    constexpr uint16_t K_S_COMPILE3              = 0x113C;
    constexpr uint16_t K_LF_MODIFIER             = 0x1001;
    constexpr uint16_t K_LF_POINTER              = 0x1002;
    constexpr uint16_t K_LF_ARRAY                = 0x1503;
    constexpr uint16_t K_LF_STRUCTURE            = 0x1505;
    constexpr uint16_t K_LF_PROCEDURE            = 0x1008;
    constexpr uint16_t K_LF_ARGLIST              = 0x1201;
    constexpr uint16_t K_LF_FIELDLIST            = 0x1203;
    constexpr uint16_t K_LF_FUNC_ID              = 0x1601;
    constexpr uint16_t K_LF_BUILDINFO            = 0x1603;
    constexpr uint16_t K_LF_STRING_ID            = 0x1605;
    constexpr uint16_t K_LF_MEMBER               = 0x150D;
    constexpr uint32_t K_CV_CFL_CXX              = 0x01;
    constexpr uint16_t K_CV_CFL_AMD64            = 0x00D0;
    constexpr uint32_t K_CV_TYPE_SIGNATURE       = 4;
    constexpr uint32_t K_CV_FIRST_NONPRIM        = 0x1000;
    constexpr uint32_t K_T_VOID                  = 0x0003;
    constexpr uint32_t K_T_PVOID64               = 0x0603;
    constexpr uint32_t K_T_BOOL08                = 0x0030;
    constexpr uint32_t K_T_SHORT                 = 0x0011;
    constexpr uint32_t K_T_USHORT                = 0x0021;
    constexpr uint32_t K_T_CHAR                  = 0x0070;
    constexpr uint32_t K_T_UCHAR                 = 0x0020;
    constexpr uint32_t K_T_INT4                  = 0x0074;
    constexpr uint32_t K_T_UINT4                 = 0x0075;
    constexpr uint32_t K_T_INT8                  = 0x0013;
    constexpr uint32_t K_T_UINT8                 = 0x0023;
    constexpr uint32_t K_T_REAL32                = 0x0040;
    constexpr uint32_t K_T_REAL64                = 0x0041;
    constexpr uint8_t  K_CV_CALL_NEAR_C          = 0x00;
    constexpr uint16_t K_CV_TYPE_MOD_CONST       = 0x0001;
    constexpr uint16_t K_CV_MEMBER_ACCESS_PUBLIC = 0x0003;
    constexpr uint32_t K_CV_PTR_ATTR_NEAR64      = 0x0000000C;
    constexpr uint32_t K_CV_FRAMEPROC_FLAGS      = 0x00114200;
    constexpr uint16_t K_CHKSUM_TYPE_NONE        = 0x00;
    constexpr uint32_t K_CV_LINE_STATEMENT_BIT   = 0x80000000u;
    constexpr uint16_t K_CV_ENCODED_FRAME_NONE   = 0x0000;
    constexpr uint16_t K_CV_ENCODED_FRAME_RSP    = 0x0001;
    constexpr uint16_t K_CV_ENCODED_FRAME_RBP    = 0x0002;
    constexpr uint16_t K_CV_NUMERIC_LEAF         = 0x8000;
    constexpr uint16_t K_LF_CHAR_NUMERIC         = 0x8000;
    constexpr uint16_t K_LF_SHORT_NUMERIC        = 0x8001;
    constexpr uint16_t K_LF_USHORT_NUMERIC       = 0x8002;
    constexpr uint16_t K_LF_LONG_NUMERIC         = 0x8003;
    constexpr uint16_t K_LF_ULONG_NUMERIC        = 0x8004;
    constexpr uint16_t K_LF_QUADWORD_NUMERIC     = 0x8009;
    constexpr uint16_t K_LF_UQUADWORD_NUMERIC    = 0x800A;
    constexpr uint16_t K_CV_REG_RAX              = 328;
    constexpr uint16_t K_CV_REG_RBX              = 329;
    constexpr uint16_t K_CV_REG_RCX              = 330;
    constexpr uint16_t K_CV_REG_RDX              = 331;
    constexpr uint16_t K_CV_REG_RSI              = 332;
    constexpr uint16_t K_CV_REG_RDI              = 333;
    constexpr uint16_t K_CV_REG_RBP              = 334;
    constexpr uint16_t K_CV_REG_RSP              = 335;
    constexpr uint16_t K_CV_REG_R8               = 336;
    constexpr uint16_t K_CV_REG_R9               = 337;
    constexpr uint16_t K_CV_REG_R10              = 338;
    constexpr uint16_t K_CV_REG_R11              = 339;
    constexpr uint16_t K_CV_REG_R12              = 340;
    constexpr uint16_t K_CV_REG_R13              = 341;
    constexpr uint16_t K_CV_REG_R14              = 342;
    constexpr uint16_t K_CV_REG_R15              = 343;

    struct LineEntry
    {
        uint32_t codeOffset = 0;
        uint32_t line       = 0;
    };

    struct LineBlock
    {
        Utf8                   fileName;
        std::vector<LineEntry> entries;
    };

    struct FunctionLines
    {
        std::vector<LineBlock> blocks;
    };

    struct StringTableBuilder
    {
        uint32_t insert(const Utf8& value)
        {
            if (value.empty())
                return 0;

            const auto it = offsets.find(value);
            if (it != offsets.end())
                return it->second;

            const uint32_t offset = size;
            offsets.emplace(value, offset);
            entries.push_back(value);
            size += static_cast<uint32_t>(value.size()) + 1;
            return offset;
        }

        void commit(std::vector<std::byte>& outBytes) const
        {
            outBytes.push_back(std::byte{0});
            for (const Utf8& entry : entries)
            {
                outBytes.insert(outBytes.end(), reinterpret_cast<const std::byte*>(entry.data()), reinterpret_cast<const std::byte*>(entry.data() + entry.size()));
                outBytes.push_back(std::byte{0});
            }
        }

        uint32_t                           size = 1;
        std::unordered_map<Utf8, uint32_t> offsets;
        std::vector<Utf8>                  entries;
    };

    struct FileChecksumBuilder
    {
        uint32_t insert(const Utf8& fileName, const uint32_t stringOffset)
        {
            const auto it = offsets.find(fileName);
            if (it != offsets.end())
                return it->second;

            const uint32_t entryOffset = size;
            Entry          entry;
            entry.stringOffset = stringOffset;
            computeChecksum(entry, fileName);
            entries.push_back(entry);
            offsets.emplace(fileName, entryOffset);
            size += Math::alignUpU32(6 + entry.checksumSize, 4);
            return entryOffset;
        }

        void commit(std::vector<std::byte>& outBytes) const
        {
            for (const Entry& entry : entries)
            {
                const uint32_t stringOffset = entry.stringOffset;
                outBytes.insert(outBytes.end(), reinterpret_cast<const std::byte*>(&stringOffset), reinterpret_cast<const std::byte*>(&stringOffset) + sizeof(stringOffset));
                outBytes.push_back(static_cast<std::byte>(entry.checksumSize));
                outBytes.push_back(static_cast<std::byte>(entry.checksumKind));
                outBytes.insert(outBytes.end(), entry.checksum.begin(), entry.checksum.begin() + entry.checksumSize);

                const uint32_t recordSize = 6 + entry.checksumSize;
                const uint32_t padBytes   = Math::alignUpU32(recordSize, 4) - recordSize;
                for (uint32_t i = 0; i < padBytes; ++i)
                    outBytes.push_back(std::byte{0});
            }
        }

        struct Entry
        {
            uint32_t                  stringOffset = 0;
            uint8_t                   checksumKind = K_CHKSUM_TYPE_NONE;
            uint8_t                   checksumSize = 0;
            std::array<std::byte, 32> checksum{};
        };

        static void computeChecksum(Entry& outEntry, const Utf8& fileName)
        {
            if (fileName.empty())
                return;
        }

        uint32_t                           size = 0;
        std::unordered_map<Utf8, uint32_t> offsets;
        std::vector<Entry>                 entries;
    };

    Utf8 codeViewPathString(const fs::path& path)
    {
        fs::path normalized = path.lexically_normal();
        normalized.make_preferred();
        return {normalized.string()};
    }

    void writeU16(std::vector<std::byte>& bytes, uint16_t value)
    {
        const auto* src = reinterpret_cast<const std::byte*>(&value);
        bytes.insert(bytes.end(), src, src + sizeof(value));
    }

    void writeU32(std::vector<std::byte>& bytes, uint32_t value)
    {
        const auto* src = reinterpret_cast<const std::byte*>(&value);
        bytes.insert(bytes.end(), src, src + sizeof(value));
    }

    void writeU64(std::vector<std::byte>& bytes, uint64_t value)
    {
        const auto* src = reinterpret_cast<const std::byte*>(&value);
        bytes.insert(bytes.end(), src, src + sizeof(value));
    }

    void writeBytes(std::vector<std::byte>& outBytes, const ByteSpan bytes)
    {
        outBytes.insert(outBytes.end(), bytes.begin(), bytes.end());
    }

    void writeCString(std::vector<std::byte>& bytes, const Utf8& value)
    {
        bytes.insert(bytes.end(), reinterpret_cast<const std::byte*>(value.data()), reinterpret_cast<const std::byte*>(value.data() + value.size()));
        bytes.push_back(std::byte{0});
    }

    void writeEncodedUnsigned(std::vector<std::byte>& bytes, const uint64_t value)
    {
        if (value < K_CV_NUMERIC_LEAF)
        {
            writeU16(bytes, static_cast<uint16_t>(value));
            return;
        }

        if (value <= std::numeric_limits<uint16_t>::max())
        {
            writeU16(bytes, K_LF_USHORT_NUMERIC);
            writeU16(bytes, static_cast<uint16_t>(value));
            return;
        }

        if (value <= std::numeric_limits<uint32_t>::max())
        {
            writeU16(bytes, K_LF_ULONG_NUMERIC);
            writeU32(bytes, static_cast<uint32_t>(value));
            return;
        }

        writeU16(bytes, K_LF_UQUADWORD_NUMERIC);
        writeU64(bytes, value);
    }

    void writeEncodedSigned(std::vector<std::byte>& bytes, const int64_t value)
    {
        if (value >= 0 && std::cmp_less(value, K_CV_NUMERIC_LEAF))
        {
            writeU16(bytes, static_cast<uint16_t>(value));
            return;
        }

        if (value >= std::numeric_limits<int8_t>::min() && value <= std::numeric_limits<int8_t>::max())
        {
            writeU16(bytes, K_LF_CHAR_NUMERIC);
            bytes.push_back(static_cast<std::byte>(static_cast<uint8_t>(value)));
            return;
        }

        if (value >= std::numeric_limits<int16_t>::min() && value <= std::numeric_limits<int16_t>::max())
        {
            writeU16(bytes, K_LF_SHORT_NUMERIC);
            writeU16(bytes, static_cast<uint16_t>(static_cast<int16_t>(value)));
            return;
        }

        if (value >= std::numeric_limits<int32_t>::min() && value <= std::numeric_limits<int32_t>::max())
        {
            writeU16(bytes, K_LF_LONG_NUMERIC);
            writeU32(bytes, static_cast<uint32_t>(static_cast<int32_t>(value)));
            return;
        }

        writeU16(bytes, K_LF_QUADWORD_NUMERIC);
        writeU64(bytes, static_cast<uint64_t>(value));
    }

    void patchU16(std::vector<std::byte>& bytes, const uint32_t offset, const uint16_t value)
    {
        SWC_ASSERT(offset + sizeof(value) <= bytes.size());
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }

    void patchU32(std::vector<std::byte>& bytes, const uint32_t offset, const uint32_t value)
    {
        SWC_ASSERT(offset + sizeof(value) <= bytes.size());
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }

    void alignBytes(std::vector<std::byte>& bytes, const uint32_t alignment)
    {
        const uint32_t alignedSize = Math::alignUpU32(static_cast<uint32_t>(bytes.size()), alignment);
        if (alignedSize > bytes.size())
            bytes.resize(alignedSize, std::byte{0});
    }

    uint32_t beginRecord(std::vector<std::byte>& bytes, const uint16_t type)
    {
        const uint32_t offset = static_cast<uint32_t>(bytes.size());
        writeU16(bytes, 0);
        writeU16(bytes, type);
        return offset;
    }

    void endRecord(std::vector<std::byte>& bytes, const uint32_t recordOffset)
    {
        const uint16_t recordLength = static_cast<uint16_t>(bytes.size() - recordOffset - sizeof(uint16_t));
        patchU16(bytes, recordOffset, recordLength);
    }

    uint32_t beginTypeRecord(std::vector<std::byte>& bytes, const uint16_t kind)
    {
        const uint32_t offset = static_cast<uint32_t>(bytes.size());
        writeU16(bytes, 0);
        writeU16(bytes, kind);
        return offset;
    }

    void endTypeRecord(std::vector<std::byte>& bytes, const uint32_t recordOffset)
    {
        const uint32_t rawRecordSize = static_cast<uint32_t>(bytes.size()) - recordOffset;
        const uint32_t padBytes      = Math::alignUpU32(rawRecordSize, 4) - rawRecordSize;
        for (uint32_t i = padBytes; i > 0; --i)
            bytes.push_back(static_cast<std::byte>(0xF0u + i));

        const uint16_t recordLength = static_cast<uint16_t>(bytes.size() - recordOffset - sizeof(uint16_t));
        patchU16(bytes, recordOffset, recordLength);
    }

    uint32_t beginSubsection(std::vector<std::byte>& bytes, const uint32_t type)
    {
        writeU32(bytes, type);
        const uint32_t lenOffset = static_cast<uint32_t>(bytes.size());
        writeU32(bytes, 0);
        return lenOffset;
    }

    void endSubsection(std::vector<std::byte>& bytes, const uint32_t lenOffset)
    {
        const uint32_t payloadOffset = lenOffset + sizeof(uint32_t);
        const uint32_t payloadSize   = static_cast<uint32_t>(bytes.size()) - payloadOffset;
        patchU32(bytes, lenOffset, payloadSize);
        alignBytes(bytes, 4);
    }

    uint16_t codeViewRegister(const MicroReg reg)
    {
        if (!reg.isValid() || !reg.isInt())
            return 0;

        switch (reg.index())
        {
            case 0:
                return K_CV_REG_RAX;
            case 1:
                return K_CV_REG_RBX;
            case 2:
                return K_CV_REG_RCX;
            case 3:
                return K_CV_REG_RDX;
            case 4:
                return K_CV_REG_RSP;
            case 5:
                return K_CV_REG_RBP;
            case 6:
                return K_CV_REG_RSI;
            case 7:
                return K_CV_REG_RDI;
            case 8:
                return K_CV_REG_R8;
            case 9:
                return K_CV_REG_R9;
            case 10:
                return K_CV_REG_R10;
            case 11:
                return K_CV_REG_R11;
            case 12:
                return K_CV_REG_R12;
            case 13:
                return K_CV_REG_R13;
            case 14:
                return K_CV_REG_R14;
            case 15:
                return K_CV_REG_R15;
            default:
                return 0;
        }
    }

    uint16_t frameProcBaseRegEncoding(const MicroReg reg)
    {
        if (!reg.isValid())
            return K_CV_ENCODED_FRAME_NONE;
        if (reg == MicroReg::intReg(4))
            return K_CV_ENCODED_FRAME_RSP;
        if (reg == MicroReg::intReg(5))
            return K_CV_ENCODED_FRAME_RBP;
        return K_CV_ENCODED_FRAME_NONE;
    }

    uint32_t compileFlags(const Runtime::BuildCfgBackend& backend)
    {
        uint32_t value = K_CV_CFL_CXX;
        if (!backend.debugInfo)
            value |= 1u << 9;
        return value;
    }

    Utf8 compilerVersionString()
    {
        return std::format("swc {}.{}.{}", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM);
    }

    Utf8 primarySourcePath(const std::vector<FunctionLines>& functionLines)
    {
        for (const FunctionLines& functionLine : functionLines)
        {
            for (const LineBlock& block : functionLine.blocks)
            {
                if (!block.fileName.empty())
                    return block.fileName;
            }
        }

        return {};
    }

    Utf8 buildInfoCurrentDirectory(const DebugInfoObjectRequest& request, const Utf8& primarySource)
    {
        if (!primarySource.empty())
            return codeViewPathString(fs::path(primarySource.c_str()).parent_path());

        if (!request.objectPath.empty())
            return codeViewPathString(request.objectPath.parent_path());

        std::error_code ec;
        const fs::path  currentPath = fs::current_path(ec);
        if (ec)
            return {};

        return codeViewPathString(currentPath);
    }

    Utf8 buildInfoSourceFileName(const Utf8& primarySource)
    {
        if (primarySource.empty())
            return {};

        return {fs::path(primarySource.c_str()).filename().string()};
    }

    std::string_view buildInfoBackendKindName(const Runtime::BuildCfgBackendKind backendKind)
    {
        switch (backendKind)
        {
            case Runtime::BuildCfgBackendKind::Executable:
                return "exe";
            case Runtime::BuildCfgBackendKind::Library:
                return "dll";
            case Runtime::BuildCfgBackendKind::Export:
                return "lib";
            case Runtime::BuildCfgBackendKind::None:
                return "none";
        }

        SWC_UNREACHABLE();
    }

    Utf8 buildInfoCommandLine(const TaskContext& ctx)
    {
        return std::format("{} --cfg {} --backend-kind {} --target-arch {}",
                           codeViewPathString(Os::getExeFullName()),
                           ctx.cmdLine().buildCfg,
                           buildInfoBackendKindName(ctx.compiler().buildCfg().backendKind),
                           ctx.cmdLine().targetArchName);
    }

    FunctionLines collectFunctionLines(TaskContext& ctx, const MachineCode& code)
    {
        FunctionLines                    result;
        std::unordered_map<Utf8, size_t> blockIndices;

        for (const auto& range : code.debugSourceRanges)
        {
            if (!range.sourceCodeRef.isValid())
                continue;

            const SourceView& srcView = ctx.compiler().srcView(range.sourceCodeRef.srcViewRef);
            const SourceFile* file    = srcView.file();
            if (!file)
                continue;

            const SourceCodeRange codeRange = srcView.tokenCodeRange(ctx, range.sourceCodeRef.tokRef);
            if (!codeRange.srcView || !codeRange.line)
                continue;

            const auto codeViewFileName = codeViewPathString(file->path());

            size_t     blockIndex = 0;
            const auto blockIt    = blockIndices.find(codeViewFileName);
            if (blockIt == blockIndices.end())
            {
                blockIndex = result.blocks.size();
                result.blocks.push_back({.fileName = codeViewFileName, .entries = {}});
                blockIndices.emplace(codeViewFileName, blockIndex);
            }
            else
            {
                blockIndex = blockIt->second;
            }

            result.blocks[blockIndex].entries.push_back({
                .codeOffset = range.codeStartOffset,
                .line       = std::min<uint32_t>(codeRange.line, 0x00FFFFFFu),
            });
        }

        return result;
    }

    void appendCompileRecord(std::vector<std::byte>& bytes, const Runtime::BuildCfgBackend& backend)
    {
        const Utf8         version      = compilerVersionString();
        constexpr uint16_t majorVersion = std::max<uint16_t>(1, SWC_VERSION);
        constexpr uint16_t minorVersion = SWC_REVISION;
        constexpr uint16_t buildVersion = SWC_BUILD_NUM;
        const uint32_t     recordOffset = beginRecord(bytes, K_S_COMPILE3);
        writeU32(bytes, compileFlags(backend));
        writeU16(bytes, K_CV_CFL_AMD64);
        writeU16(bytes, majorVersion);
        writeU16(bytes, minorVersion);
        writeU16(bytes, buildVersion);
        writeU16(bytes, 0);
        writeU16(bytes, majorVersion);
        writeU16(bytes, minorVersion);
        writeU16(bytes, buildVersion);
        writeU16(bytes, 0);
        writeCString(bytes, version);
        endRecord(bytes, recordOffset);
    }

    void appendObjNameRecord(std::vector<std::byte>& bytes, const fs::path& objectPath)
    {
        const auto     objectName   = codeViewPathString(objectPath);
        const uint32_t recordOffset = beginRecord(bytes, K_S_OBJNAME);
        writeU32(bytes, 0);
        writeCString(bytes, objectName);
        endRecord(bytes, recordOffset);
    }

    void appendBuildInfoRecord(std::vector<std::byte>& bytes, const uint32_t buildInfoTypeIndex)
    {
        const uint32_t recordOffset = beginRecord(bytes, K_S_BUILDINFO);
        writeU32(bytes, buildInfoTypeIndex);
        endRecord(bytes, recordOffset);
    }

    bool appendConstantValueBytes(std::vector<std::byte>& bytes, const TaskContext& ctx, const ConstantValue& value)
    {
        switch (value.kind())
        {
            case ConstantKind::Bool:
                writeEncodedUnsigned(bytes, value.getBool() ? 1 : 0);
                return true;

            case ConstantKind::Char:
                writeEncodedUnsigned(bytes, value.getChar());
                return true;

            case ConstantKind::Rune:
                writeEncodedUnsigned(bytes, value.getRune());
                return true;

            case ConstantKind::Int:
            {
                const ApsInt& intValue = value.getInt();
                if (!intValue.fits64())
                    return false;

                if (intValue.isUnsigned())
                    writeEncodedUnsigned(bytes, intValue.as64());
                else
                    writeEncodedSigned(bytes, intValue.asI64());
                return true;
            }

            case ConstantKind::Float:
            {
                const ApFloat& floatValue = value.getFloat();
                if (floatValue.bitWidth() <= 32)
                {
                    writeEncodedUnsigned(bytes, std::bit_cast<uint32_t>(floatValue.asFloat()));
                    return true;
                }

                if (floatValue.bitWidth() <= 64)
                {
                    writeEncodedUnsigned(bytes, std::bit_cast<uint64_t>(floatValue.asDouble()));
                    return true;
                }

                return false;
            }

            case ConstantKind::ValuePointer:
                writeEncodedUnsigned(bytes, value.getValuePointer());
                return true;

            case ConstantKind::BlockPointer:
                writeEncodedUnsigned(bytes, value.getBlockPointer());
                return true;

            case ConstantKind::Null:
                writeEncodedUnsigned(bytes, 0);
                return true;

            case ConstantKind::EnumValue:
                return appendConstantValueBytes(bytes, ctx, ctx.cstMgr().get(value.getEnumValue()));

            default:
                return false;
        }
    }

    void appendRegRelativeSymbol(std::vector<std::byte>& bytes, const DebugInfoLocalRecord& local, const uint32_t typeIndex)
    {
        const uint16_t cvReg = codeViewRegister(local.baseReg);
        if (!cvReg)
            return;

        SWC_ASSERT(local.offset <= static_cast<uint32_t>(std::numeric_limits<int32_t>::max()));
        const uint32_t recordOffset = beginRecord(bytes, K_S_REGREL32);
        writeU32(bytes, static_cast<uint32_t>(static_cast<int32_t>(local.offset)));
        writeU32(bytes, typeIndex);
        writeU16(bytes, cvReg);
        writeCString(bytes, local.name);
        endRecord(bytes, recordOffset);
    }

    void appendDataSymbol(std::vector<std::byte>& bytes, NativeSectionData& debugSection, const DebugInfoDataRecord& data, const uint32_t typeIndex)
    {
        const uint32_t recordOffset = beginRecord(bytes, data.isGlobal ? K_S_GDATA32 : K_S_LDATA32);
        writeU32(bytes, typeIndex);

        const uint32_t offRelocOffset = static_cast<uint32_t>(bytes.size());
        writeU32(bytes, 0);
        const uint32_t segRelocOffset = static_cast<uint32_t>(bytes.size());
        writeU16(bytes, 0);
        writeCString(bytes, data.name.empty() ? data.symbolName : data.name);

        debugSection.relocations.push_back({
            .offset     = offRelocOffset,
            .symbolName = data.symbolName,
            .addend     = 0,
            .type       = IMAGE_REL_AMD64_SECREL,
        });
        debugSection.relocations.push_back({
            .offset     = segRelocOffset,
            .symbolName = data.symbolName,
            .addend     = 0,
            .type       = IMAGE_REL_AMD64_SECTION,
        });
        endRecord(bytes, recordOffset);
    }

    bool appendConstantSymbol(std::vector<std::byte>& bytes, const TaskContext& ctx, const DebugInfoConstantRecord& constant, const uint32_t typeIndex)
    {
        if (!constant.valueRef.isValid())
            return false;

        const size_t         savedSize    = bytes.size();
        const uint32_t       recordOffset = beginRecord(bytes, K_S_CONSTANT);
        const ConstantValue& value        = ctx.cstMgr().get(constant.valueRef);
        writeU32(bytes, typeIndex);
        if (!appendConstantValueBytes(bytes, ctx, value))
        {
            bytes.resize(savedSize);
            return false;
        }

        writeCString(bytes, constant.name);
        endRecord(bytes, recordOffset);
        return true;
    }

    void appendUdtSymbol(std::vector<std::byte>& bytes, const uint32_t typeIndex, const Utf8& typeName)
    {
        if (typeName.empty())
            return;

        const uint32_t recordOffset = beginRecord(bytes, K_S_UDT);
        writeU32(bytes, typeIndex);
        writeCString(bytes, typeName);
        endRecord(bytes, recordOffset);
    }

    void appendProcSymbols(std::vector<std::byte>&         bytes,
                           NativeSectionData&              debugSection,
                           const TaskContext&              ctx,
                           const DebugInfoFunctionRecord&  function,
                           const uint32_t                  typeIndex,
                           const std::span<const uint32_t> parameterTypeIndices,
                           const std::span<const uint32_t> localTypeIndices,
                           const std::span<const uint32_t> constantTypeIndices)
    {
        SWC_ASSERT(function.machineCode != nullptr);
        SWC_ASSERT(function.parameters.size() == parameterTypeIndices.size());
        SWC_ASSERT(function.locals.size() == localTypeIndices.size());
        SWC_ASSERT(function.constants.size() == constantTypeIndices.size());

        const uint32_t codeSize = static_cast<uint32_t>(function.machineCode->bytes.size());

        const uint32_t procOffset = beginRecord(bytes, K_S_GPROC32_ID);
        writeU32(bytes, 0);
        writeU32(bytes, 0);
        writeU32(bytes, 0);
        writeU32(bytes, codeSize);
        writeU32(bytes, 0);
        writeU32(bytes, codeSize ? codeSize - 1 : 0);
        writeU32(bytes, typeIndex);

        const uint32_t offRelocOffset = static_cast<uint32_t>(bytes.size());
        writeU32(bytes, 0);
        const uint32_t segRelocOffset = static_cast<uint32_t>(bytes.size());
        writeU16(bytes, 0);
        bytes.push_back(std::byte{0});
        writeCString(bytes, function.debugName.empty() ? function.symbolName : function.debugName);

        debugSection.relocations.push_back({
            .offset     = offRelocOffset,
            .symbolName = function.symbolName,
            .addend     = 0,
            .type       = IMAGE_REL_AMD64_SECREL,
        });
        debugSection.relocations.push_back({
            .offset     = segRelocOffset,
            .symbolName = function.symbolName,
            .addend     = 0,
            .type       = IMAGE_REL_AMD64_SECTION,
        });
        endRecord(bytes, procOffset);

        const uint32_t frameOffset = beginRecord(bytes, K_S_FRAMEPROC);
        writeU32(bytes, function.frameSize);
        writeU32(bytes, 0);
        writeU32(bytes, 0);
        writeU32(bytes, 0);
        writeU32(bytes, 0);
        writeU16(bytes, frameProcBaseRegEncoding(function.frameBaseReg));
        writeU32(bytes, K_CV_FRAMEPROC_FLAGS);
        endRecord(bytes, frameOffset);

        for (size_t i = 0; i < function.parameters.size(); ++i)
            appendRegRelativeSymbol(bytes, function.parameters[i], parameterTypeIndices[i]);

        for (size_t i = 0; i < function.locals.size(); ++i)
            appendRegRelativeSymbol(bytes, function.locals[i], localTypeIndices[i]);

        for (size_t i = 0; i < function.constants.size(); ++i)
            appendConstantSymbol(bytes, ctx, function.constants[i], constantTypeIndices[i]);

        const uint32_t endOffset = beginRecord(bytes, K_S_PROC_ID_END);
        SWC_UNUSED(endOffset);
        endRecord(bytes, endOffset);
    }

    struct TypeTableBuilder
    {
        struct FieldDesc
        {
            Utf8     name;
            uint32_t typeIndex = K_T_VOID;
            uint64_t offset    = 0;
        };

        explicit TypeTableBuilder(TaskContext* ctx) :
            ctx(ctx)
        {
            SWC_ASSERT(ctx != nullptr);
        }

        void begin()
        {
            writeU32(bytes, K_CV_TYPE_SIGNATURE);
        }

        uint32_t appendArgList(const std::span<const uint32_t> arguments)
        {
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_ARGLIST);
            writeU32(bytes, static_cast<uint32_t>(arguments.size()));
            for (const uint32_t argType : arguments)
                writeU32(bytes, argType);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        uint32_t appendProcedureType(const uint32_t returnType, const std::span<const uint32_t> arguments)
        {
            const uint32_t argListType  = appendArgList(arguments);
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_PROCEDURE);
            writeU32(bytes, returnType);
            bytes.push_back(static_cast<std::byte>(K_CV_CALL_NEAR_C));
            bytes.push_back(std::byte{0});
            writeU16(bytes, static_cast<uint16_t>(arguments.size()));
            writeU32(bytes, argListType);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        uint32_t appendFunctionId(const Utf8& functionName, const uint32_t procedureType)
        {
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_FUNC_ID);
            writeU32(bytes, 0);
            writeU32(bytes, procedureType);
            writeCString(bytes, functionName);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        uint32_t appendStringId(const Utf8& value)
        {
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_STRING_ID);
            writeU32(bytes, 0);
            writeCString(bytes, value);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        uint32_t appendModifierType(const uint32_t baseTypeIndex, const uint16_t modifiers)
        {
            const uint64_t cacheKey = (static_cast<uint64_t>(baseTypeIndex) << 16) | modifiers;
            const auto     cacheIt  = modifierTypes.find(cacheKey);
            if (cacheIt != modifierTypes.end())
                return cacheIt->second;

            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_MODIFIER);
            writeU32(bytes, baseTypeIndex);
            writeU16(bytes, modifiers);
            endTypeRecord(bytes, recordOffset);
            modifierTypes.emplace(cacheKey, typeIndex);
            return typeIndex;
        }

        uint32_t appendPointerType(const uint32_t pointeeTypeIndex)
        {
            const auto cacheIt = pointerTypes.find(pointeeTypeIndex);
            if (cacheIt != pointerTypes.end())
                return cacheIt->second;

            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_POINTER);
            writeU32(bytes, pointeeTypeIndex);
            writeU32(bytes, K_CV_PTR_ATTR_NEAR64);
            endTypeRecord(bytes, recordOffset);
            pointerTypes.emplace(pointeeTypeIndex, typeIndex);
            return typeIndex;
        }

        uint32_t appendArrayType(const uint32_t elementTypeIndex, const uint64_t sizeOf)
        {
            const uint64_t cacheKey = (static_cast<uint64_t>(elementTypeIndex) << 32) ^ sizeOf;
            const auto     cacheIt  = arrayTypes.find(cacheKey);
            if (cacheIt != arrayTypes.end())
                return cacheIt->second;

            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_ARRAY);
            writeU32(bytes, elementTypeIndex);
            writeU32(bytes, K_T_UINT8);
            writeEncodedUnsigned(bytes, sizeOf);
            writeCString(bytes, {});
            endTypeRecord(bytes, recordOffset);
            arrayTypes.emplace(cacheKey, typeIndex);
            return typeIndex;
        }

        uint32_t appendFieldList(const std::span<const FieldDesc> fields)
        {
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_FIELDLIST);
            for (const FieldDesc& field : fields)
            {
                writeU16(bytes, K_LF_MEMBER);
                writeU16(bytes, K_CV_MEMBER_ACCESS_PUBLIC);
                writeU32(bytes, field.typeIndex);
                writeEncodedUnsigned(bytes, field.offset);
                writeCString(bytes, field.name);
            }

            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        uint32_t appendStructRecord(const Utf8& typeName, const uint32_t fieldListType, const uint16_t memberCount, const uint64_t sizeOf, const uint16_t properties)
        {
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_STRUCTURE);
            writeU16(bytes, memberCount);
            writeU16(bytes, properties);
            writeU32(bytes, fieldListType);
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeEncodedUnsigned(bytes, sizeOf);
            writeCString(bytes, typeName);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        uint32_t appendForwardStructRecord(const Utf8& typeName)
        {
            const uint32_t typeIndex    = nextTypeIndex++;
            const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_STRUCTURE);
            writeU16(bytes, 0);
            writeU16(bytes, 0x0080);
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeEncodedUnsigned(bytes, 0);
            writeCString(bytes, typeName);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        static uint32_t primitiveTypeIndex(const TypeInfo& typeInfo)
        {
            if (typeInfo.isVoid() || typeInfo.isNull() || typeInfo.isUndefined())
                return K_T_VOID;
            if (typeInfo.isBool())
                return K_T_BOOL08;
            if (typeInfo.isChar())
                return K_T_CHAR;
            if (typeInfo.isRune())
                return K_T_UINT4;
            if (typeInfo.isFloat())
                return typeInfo.payloadFloatBits() <= 32 ? K_T_REAL32 : K_T_REAL64;
            if (typeInfo.isInt())
            {
                const uint32_t bits = typeInfo.payloadIntBits();
                if (bits <= 8)
                    return typeInfo.isIntUnsigned() ? K_T_UCHAR : K_T_CHAR;
                if (bits <= 16)
                    return typeInfo.isIntUnsigned() ? K_T_USHORT : K_T_SHORT;
                if (bits <= 32)
                    return typeInfo.isIntUnsigned() ? K_T_UINT4 : K_T_INT4;
                return typeInfo.isIntUnsigned() ? K_T_UINT8 : K_T_INT8;
            }

            return 0;
        }

        uint32_t appendSyntheticStructType(const TypeRef typeRef, const Utf8& typeName, const std::span<const FieldDesc> fields, const uint64_t sizeOf, const bool isConst)
        {
            const uint64_t cacheKey = (static_cast<uint64_t>(typeRef.get()) << 1) | static_cast<uint64_t>(isConst);
            const auto     cacheIt  = builtTypes.find(cacheKey);
            if (cacheIt != builtTypes.end())
                return cacheIt->second;

            const uint32_t fieldListType = fields.empty() ? 0 : appendFieldList(fields);
            const uint32_t baseTypeIndex = appendStructRecord(typeName, fieldListType, static_cast<uint16_t>(fields.size()), sizeOf, 0);
            const uint32_t typeIndex     = isConst ? appendModifierType(baseTypeIndex, K_CV_TYPE_MOD_CONST) : baseTypeIndex;
            builtTypes.emplace(cacheKey, typeIndex);
            udtNames.emplace(baseTypeIndex, typeName);
            return typeIndex;
        }

        uint32_t typeIndexFor(TypeRef typeRef, bool isConst = false)
        {
            if (typeRef.isInvalid())
                return K_T_VOID;

            const TypeInfo& originalType = ctx->typeMgr().get(typeRef);
            isConst                      = isConst || originalType.isConst();

            if (originalType.isAlias())
            {
                const TypeRef unwrapped = originalType.unwrap(*ctx, typeRef, TypeExpandE::Alias);
                if (unwrapped.isValid() && unwrapped != typeRef)
                    return typeIndexFor(unwrapped, isConst);
            }

            if (originalType.isEnum())
                return typeIndexFor(originalType.payloadSymEnum().underlyingTypeRef(), isConst);

            const uint64_t cacheKey = (static_cast<uint64_t>(typeRef.get()) << 1) | static_cast<uint64_t>(isConst);
            const auto     cacheIt  = builtTypes.find(cacheKey);
            if (cacheIt != builtTypes.end())
                return cacheIt->second;

            if (const uint32_t primitive = primitiveTypeIndex(originalType))
                return isConst ? appendModifierType(primitive, K_CV_TYPE_MOD_CONST) : primitive;

            if (originalType.isString())
            {
                const std::array fields = {
                    FieldDesc{.name = "ptr", .typeIndex = appendPointerType(K_T_CHAR), .offset = offsetof(Runtime::String, ptr)},
                    FieldDesc{.name = "length", .typeIndex = K_T_UINT8, .offset = offsetof(Runtime::String, length)},
                };
                return appendSyntheticStructType(typeRef, "string", fields, sizeof(Runtime::String), isConst);
            }

            if (originalType.isSlice())
            {
                const uint32_t   elemPtrType = appendPointerType(typeIndexFor(originalType.payloadTypeRef()));
                const std::array fields      = {
                    FieldDesc{.name = "ptr", .typeIndex = elemPtrType, .offset = offsetof(Runtime::Slice<std::byte>, ptr)},
                    FieldDesc{.name = "count", .typeIndex = K_T_UINT8, .offset = offsetof(Runtime::Slice<std::byte>, count)},
                };
                return appendSyntheticStructType(typeRef, originalType.toName(*ctx), fields, sizeof(Runtime::Slice<std::byte>), isConst);
            }

            if (originalType.isAny())
            {
                const std::array fields = {
                    FieldDesc{.name = "value", .typeIndex = K_T_PVOID64, .offset = offsetof(Runtime::Any, value)},
                    FieldDesc{.name = "type", .typeIndex = K_T_PVOID64, .offset = offsetof(Runtime::Any, type)},
                };
                return appendSyntheticStructType(typeRef, "any", fields, sizeof(Runtime::Any), isConst);
            }

            if (originalType.isInterface())
            {
                const std::array fields = {
                    FieldDesc{.name = "obj", .typeIndex = K_T_PVOID64, .offset = offsetof(Runtime::Interface, obj)},
                    FieldDesc{.name = "itable", .typeIndex = appendPointerType(K_T_PVOID64), .offset = offsetof(Runtime::Interface, itable)},
                };
                return appendSyntheticStructType(typeRef, "interface", fields, sizeof(Runtime::Interface), isConst);
            }

            if (originalType.isCString())
            {
                const uint32_t baseType = appendPointerType(K_T_CHAR);
                return isConst ? appendModifierType(baseType, K_CV_TYPE_MOD_CONST) : baseType;
            }

            if (originalType.isValuePointer() || originalType.isBlockPointer() || originalType.isReference() || originalType.isFunction() || originalType.isTypeInfo() || originalType.isTypeValue())
            {
                const TypeRef  pointeeTypeRef = originalType.isFunction() || originalType.isTypeInfo() || originalType.isTypeValue() ? TypeRef::invalid() : originalType.payloadTypeRef();
                const uint32_t pointeeType    = pointeeTypeRef.isValid() ? typeIndexFor(pointeeTypeRef) : K_T_VOID;
                const uint32_t pointerType    = appendPointerType(pointeeType ? pointeeType : K_T_VOID);
                return isConst ? appendModifierType(pointerType, K_CV_TYPE_MOD_CONST) : pointerType;
            }

            if (originalType.isArray())
            {
                uint32_t    currentType = typeIndexFor(originalType.payloadArrayElemTypeRef());
                uint64_t    currentSize = ctx->typeMgr().get(originalType.payloadArrayElemTypeRef()).sizeOf(*ctx);
                const auto& dims        = originalType.payloadArrayDims();
                for (size_t i = dims.size(); i-- > 0;)
                {
                    currentSize *= dims[i];
                    currentType = appendArrayType(currentType, currentSize);
                }

                const uint32_t typeIndex = isConst ? appendModifierType(currentType, K_CV_TYPE_MOD_CONST) : currentType;
                builtTypes.emplace(cacheKey, typeIndex);
                return typeIndex;
            }

            if (originalType.isAggregate())
            {
                std::vector<FieldDesc> fields;
                const auto&            aggregate = originalType.payloadAggregate();
                fields.reserve(aggregate.types.size());
                uint64_t offset = 0;
                for (size_t i = 0; i < aggregate.types.size(); ++i)
                {
                    const TypeRef   fieldTypeRef = aggregate.types[i];
                    const TypeInfo& fieldType    = ctx->typeMgr().get(fieldTypeRef);
                    const uint32_t  alignment    = fieldType.alignOf(*ctx);
                    if (alignment)
                        offset = Math::alignUpU64(offset, alignment);

                    Utf8 fieldName;
                    if (i < aggregate.names.size() && aggregate.names[i].isValid())
                        fieldName = Utf8(ctx->idMgr().get(aggregate.names[i]).name);
                    if (fieldName.empty())
                        fieldName = std::format("_{}", i);

                    fields.push_back({
                        .name      = fieldName,
                        .typeIndex = typeIndexFor(fieldTypeRef),
                        .offset    = offset,
                    });
                    offset += fieldType.sizeOf(*ctx);
                }

                return appendSyntheticStructType(typeRef, originalType.toName(*ctx), fields, originalType.sizeOf(*ctx), isConst);
            }

            if (originalType.isStruct())
            {
                const uint32_t typeKey = typeRef.get();
                if (buildingStructs.contains(typeKey))
                {
                    const auto itForward = forwardStructTypes.find(typeKey);
                    SWC_ASSERT(itForward != forwardStructTypes.end());
                    return itForward->second;
                }

                const Utf8     typeName    = originalType.toName(*ctx);
                const uint32_t forwardType = appendForwardStructRecord(typeName);
                forwardStructTypes.emplace(typeKey, forwardType);
                buildingStructs.insert(typeKey);

                std::vector<FieldDesc> fields;
                for (const SymbolVariable* field : originalType.payloadSymStruct().fields())
                {
                    if (!field || field->typeRef().isInvalid() || !field->idRef().isValid())
                        continue;

                    fields.push_back({
                        .name      = Utf8(field->name(*ctx)),
                        .typeIndex = typeIndexFor(field->typeRef(), field->hasExtraFlag(SymbolVariableFlagsE::Let)),
                        .offset    = field->offset(),
                    });
                }

                const uint32_t fieldListType = fields.empty() ? 0 : appendFieldList(fields);
                const uint32_t baseTypeIndex = appendStructRecord(typeName, fieldListType, static_cast<uint16_t>(fields.size()), originalType.sizeOf(*ctx), 0);
                buildingStructs.erase(typeKey);
                const uint32_t typeIndex = isConst ? appendModifierType(baseTypeIndex, K_CV_TYPE_MOD_CONST) : baseTypeIndex;
                builtTypes.emplace(cacheKey, typeIndex);
                udtNames.emplace(baseTypeIndex, typeName);
                return typeIndex;
            }

            const uint32_t fallbackType = isConst ? appendModifierType(K_T_PVOID64, K_CV_TYPE_MOD_CONST) : K_T_PVOID64;
            builtTypes.emplace(cacheKey, fallbackType);
            return fallbackType;
        }

        uint32_t appendBuildInfo(const std::array<uint32_t, 5>& items)
        {
            const uint32_t     typeIndex    = nextTypeIndex++;
            const uint32_t     recordOffset = beginTypeRecord(bytes, K_LF_BUILDINFO);
            constexpr uint16_t size         = items.size();
            writeU16(bytes, size);
            for (const uint32_t item : items)
                writeU32(bytes, item);
            endTypeRecord(bytes, recordOffset);
            return typeIndex;
        }

        TaskContext*                           ctx = nullptr;
        std::vector<std::byte>                 bytes;
        uint32_t                               nextTypeIndex = K_CV_FIRST_NONPRIM;
        std::unordered_map<uint64_t, uint32_t> builtTypes;
        std::unordered_map<uint64_t, uint32_t> modifierTypes;
        std::unordered_map<uint32_t, uint32_t> pointerTypes;
        std::unordered_map<uint64_t, uint32_t> arrayTypes;
        std::unordered_map<uint32_t, uint32_t> forwardStructTypes;
        std::unordered_set<uint32_t>           buildingStructs;
        std::map<uint32_t, Utf8>               udtNames;
    };

    void appendLinesSubsection(std::vector<std::byte>& bytes, NativeSectionData& debugSection, const DebugInfoFunctionRecord& function, const FunctionLines& functionLines, const FileChecksumBuilder& checksums)
    {
        if (functionLines.blocks.empty())
            return;

        const uint32_t subsectionLenOffset = beginSubsection(bytes, K_DEBUG_S_LINES);
        const uint32_t offRelocOffset      = static_cast<uint32_t>(bytes.size());
        writeU32(bytes, 0);
        const uint32_t segRelocOffset = static_cast<uint32_t>(bytes.size());
        writeU16(bytes, 0);
        writeU16(bytes, 0);
        writeU32(bytes, static_cast<uint32_t>(function.machineCode->bytes.size()));

        debugSection.relocations.push_back({
            .offset     = offRelocOffset,
            .symbolName = function.symbolName,
            .addend     = 0,
            .type       = IMAGE_REL_AMD64_SECREL,
        });
        debugSection.relocations.push_back({
            .offset     = segRelocOffset,
            .symbolName = function.symbolName,
            .addend     = 0,
            .type       = IMAGE_REL_AMD64_SECTION,
        });

        for (const auto& block : functionLines.blocks)
        {
            const auto checksumIt = checksums.offsets.find(block.fileName);
            if (checksumIt == checksums.offsets.end())
                continue;

            writeU32(bytes, checksumIt->second);
            writeU32(bytes, static_cast<uint32_t>(block.entries.size()));
            writeU32(bytes, static_cast<uint32_t>(12 + block.entries.size() * 8));

            for (const LineEntry& entry : block.entries)
            {
                writeU32(bytes, entry.codeOffset);
                writeU32(bytes, K_CV_LINE_STATEMENT_BIT | entry.line);
            }
        }

        endSubsection(bytes, subsectionLenOffset);
    }

    Result appendCodeViewSection(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult)
    {
        if (!request.emitCodeView)
            return Result::Continue;
        if (!request.ctx)
            return Result::Continue;
        if (request.functions.empty() && request.globals.empty() && request.constants.empty())
            return Result::Continue;

        NativeSectionData debugSection;
        debugSection.name            = ".debug$S";
        debugSection.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_DISCARDABLE | IMAGE_SCN_ALIGN_1BYTES | IMAGE_SCN_MEM_READ;

        writeU32(debugSection.bytes, K_CV_SIGNATURE_C13);

        struct FunctionSymbolTypes
        {
            uint32_t              functionTypeIndex = 0;
            std::vector<uint32_t> parameterTypes;
            std::vector<uint32_t> localTypes;
            std::vector<uint32_t> constantTypes;
        };

        std::vector<FunctionLines> functionLines;
        functionLines.reserve(request.functions.size());

        std::vector<FunctionSymbolTypes> functionSymbolTypes;
        functionSymbolTypes.resize(request.functions.size());

        StringTableBuilder  strings;
        FileChecksumBuilder checksums;
        TypeTableBuilder    types(request.ctx);
        types.begin();

        std::vector<uint32_t> globalTypeIndices;
        globalTypeIndices.reserve(request.globals.size());
        for (const DebugInfoDataRecord& data : request.globals)
            globalTypeIndices.push_back(types.typeIndexFor(data.typeRef, data.isConst));

        std::vector<uint32_t> globalConstantTypeIndices;
        globalConstantTypeIndices.reserve(request.constants.size());
        for (const DebugInfoConstantRecord& constant : request.constants)
            globalConstantTypeIndices.push_back(types.typeIndexFor(constant.typeRef, constant.isConst));

        for (size_t i = 0; i < request.functions.size(); ++i)
        {
            const DebugInfoFunctionRecord& function = request.functions[i];
            const FunctionLines            lines    = function.machineCode ? collectFunctionLines(*request.ctx, *function.machineCode) : FunctionLines{};
            for (const auto& block : lines.blocks)
            {
                const uint32_t stringOffset = strings.insert(block.fileName);
                checksums.insert(block.fileName, stringOffset);
            }

            functionLines.push_back(lines);

            FunctionSymbolTypes& symbolTypes = functionSymbolTypes[i];
            symbolTypes.parameterTypes.reserve(function.parameters.size());
            symbolTypes.localTypes.reserve(function.locals.size());
            symbolTypes.constantTypes.reserve(function.constants.size());

            for (const DebugInfoLocalRecord& parameter : function.parameters)
                symbolTypes.parameterTypes.push_back(types.typeIndexFor(parameter.typeRef, parameter.isConst));
            for (const DebugInfoLocalRecord& local : function.locals)
                symbolTypes.localTypes.push_back(types.typeIndexFor(local.typeRef, local.isConst));
            for (const DebugInfoConstantRecord& constant : function.constants)
                symbolTypes.constantTypes.push_back(types.typeIndexFor(constant.typeRef, constant.isConst));

            const uint32_t returnTypeIndex = function.returnTypeRef.isValid() ? types.typeIndexFor(function.returnTypeRef) : K_T_VOID;
            const uint32_t procTypeIndex   = types.appendProcedureType(returnTypeIndex, symbolTypes.parameterTypes);
            symbolTypes.functionTypeIndex  = types.appendFunctionId(function.debugName.empty() ? function.symbolName : function.debugName, procTypeIndex);
        }

        const Utf8 primarySource       = primarySourcePath(functionLines);
        const Utf8 buildCurrentDir     = buildInfoCurrentDirectory(request, primarySource);
        const Utf8 buildTool           = codeViewPathString(Os::getExeFullName());
        const Utf8 buildSourceFileName = buildInfoSourceFileName(primarySource);
        fs::path   buildPdbPath        = request.objectPath;
        buildPdbPath.replace_extension(".pdb");
        const Utf8     buildPdbPathString = codeViewPathString(buildPdbPath);
        const Utf8     buildCommandLine   = buildInfoCommandLine(*request.ctx);
        const uint32_t currentDirId       = types.appendStringId(buildCurrentDir);
        const uint32_t buildToolId        = types.appendStringId(buildTool);
        const uint32_t sourceFileId       = types.appendStringId(buildSourceFileName);
        const uint32_t pdbFileId          = types.appendStringId(buildPdbPathString);
        const uint32_t commandLineId      = types.appendStringId(buildCommandLine);
        const uint32_t buildInfoId        = types.appendBuildInfo({currentDirId, buildToolId, sourceFileId, pdbFileId, commandLineId});

        uint32_t symbolsLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_SYMBOLS);
        appendObjNameRecord(debugSection.bytes, request.objectPath);
        appendCompileRecord(debugSection.bytes, request.ctx->compiler().buildCfg().backend);
        endSubsection(debugSection.bytes, symbolsLenOffset);

        for (size_t i = 0; i < request.functions.size(); ++i)
        {
            const DebugInfoFunctionRecord& function = request.functions[i];
            if (function.machineCode)
            {
                symbolsLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_SYMBOLS);
                appendProcSymbols(debugSection.bytes,
                                  debugSection,
                                  *request.ctx,
                                  function,
                                  functionSymbolTypes[i].functionTypeIndex,
                                  functionSymbolTypes[i].parameterTypes,
                                  functionSymbolTypes[i].localTypes,
                                  functionSymbolTypes[i].constantTypes);
                endSubsection(debugSection.bytes, symbolsLenOffset);
            }

            appendLinesSubsection(debugSection.bytes, debugSection, request.functions[i], functionLines[i], checksums);
        }

        if (!request.globals.empty() || !request.constants.empty() || !types.udtNames.empty())
        {
            symbolsLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_SYMBOLS);

            for (size_t i = 0; i < request.globals.size(); ++i)
            {
                const DebugInfoDataRecord& data = request.globals[i];
                outResult.symbols.push_back({
                    .name        = data.symbolName,
                    .sectionName = data.sectionName,
                    .value       = data.symbolOffset,
                });
                appendDataSymbol(debugSection.bytes, debugSection, data, globalTypeIndices[i]);
            }

            for (size_t i = 0; i < request.constants.size(); ++i)
                appendConstantSymbol(debugSection.bytes, *request.ctx, request.constants[i], globalConstantTypeIndices[i]);

            for (const auto& [typeIndex, typeName] : types.udtNames)
                appendUdtSymbol(debugSection.bytes, typeIndex, typeName);

            endSubsection(debugSection.bytes, symbolsLenOffset);
        }

        if (!checksums.entries.empty())
        {
            const uint32_t checksumLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_FILECHKSMS);
            checksums.commit(debugSection.bytes);
            endSubsection(debugSection.bytes, checksumLenOffset);

            const uint32_t stringLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_STRINGTABLE);
            strings.commit(debugSection.bytes);
            endSubsection(debugSection.bytes, stringLenOffset);
        }

        symbolsLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_SYMBOLS);
        appendBuildInfoRecord(debugSection.bytes, buildInfoId);
        endSubsection(debugSection.bytes, symbolsLenOffset);

        outResult.sections.push_back(std::move(debugSection));

        NativeSectionData typeSection;
        typeSection.name            = ".debug$T";
        typeSection.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_DISCARDABLE | IMAGE_SCN_ALIGN_1BYTES | IMAGE_SCN_MEM_READ;
        typeSection.bytes           = std::move(types.bytes);
        outResult.sections.push_back(std::move(typeSection));
        return Result::Continue;
    }

    void writeAddend(std::vector<std::byte>& bytes, const uint32_t offset, const uint32_t value)
    {
        SWC_ASSERT(offset + sizeof(value) <= bytes.size());
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }

    Result appendUnwindSections(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult)
    {
        NativeSectionData xdataSection;
        xdataSection.name            = ".xdata";
        xdataSection.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_ALIGN_4BYTES | IMAGE_SCN_MEM_READ;

        NativeSectionData pdataSection;
        pdataSection.name            = ".pdata";
        pdataSection.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_ALIGN_4BYTES | IMAGE_SCN_MEM_READ;

        uint32_t unwindIndex = 0;
        for (const DebugInfoFunctionRecord& function : request.functions)
        {
            if (!function.machineCode || function.machineCode->unwindInfo.empty())
                continue;

            alignBytes(xdataSection.bytes, 4);
            const uint32_t unwindOffset = static_cast<uint32_t>(xdataSection.bytes.size());
            writeBytes(xdataSection.bytes, ByteSpan{function.machineCode->unwindInfo.data(), function.machineCode->unwindInfo.size()});

            const Utf8 unwindSymbolName = std::format("__swc_unwind_{:04}", unwindIndex++);
            outResult.symbols.push_back({
                .name         = unwindSymbolName,
                .sectionName  = xdataSection.name,
                .value        = unwindOffset,
                .type         = 0,
                .storageClass = IMAGE_SYM_CLASS_STATIC,
            });

            alignBytes(pdataSection.bytes, 4);
            const uint32_t pdataOffset = static_cast<uint32_t>(pdataSection.bytes.size());
            pdataSection.bytes.resize(pdataOffset + 12, std::byte{0});

            pdataSection.relocations.push_back({
                .offset     = pdataOffset + 0,
                .symbolName = function.symbolName,
                .addend     = 0,
                .type       = IMAGE_REL_AMD64_ADDR32NB,
            });
            pdataSection.relocations.push_back({
                .offset     = pdataOffset + 4,
                .symbolName = function.symbolName,
                .addend     = function.machineCode->bytes.size(),
                .type       = IMAGE_REL_AMD64_ADDR32NB,
            });
            pdataSection.relocations.push_back({
                .offset     = pdataOffset + 8,
                .symbolName = unwindSymbolName,
                .addend     = 0,
                .type       = IMAGE_REL_AMD64_ADDR32NB,
            });

            writeAddend(pdataSection.bytes, pdataOffset + 4, static_cast<uint32_t>(function.machineCode->bytes.size()));
        }

        if (!xdataSection.bytes.empty())
            outResult.sections.push_back(std::move(xdataSection));
        if (!pdataSection.bytes.empty())
            outResult.sections.push_back(std::move(pdataSection));
        return Result::Continue;
    }

}

Result DebugInfoCodeView::buildObject(DebugInfoObjectResult& outResult, const DebugInfoObjectRequest& request)
{
    outResult.sections.clear();
    outResult.symbols.clear();

    SWC_RESULT_VERIFY(appendCodeViewSection(request, outResult));
    SWC_RESULT_VERIFY(appendUnwindSections(request, outResult));
    return Result::Continue;
}

SWC_END_NAMESPACE();

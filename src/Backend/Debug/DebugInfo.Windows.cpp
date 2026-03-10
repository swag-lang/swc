#include "pch.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/FileSystem.h"
#include "Main/Version.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace DebugInfoPrivate
{
    namespace
    {
        constexpr uint32_t K_CV_SIGNATURE_C13      = 4;
        constexpr uint32_t K_DEBUG_S_SYMBOLS       = 0xF1;
        constexpr uint32_t K_DEBUG_S_LINES         = 0xF2;
        constexpr uint32_t K_DEBUG_S_STRINGTABLE   = 0xF3;
        constexpr uint32_t K_DEBUG_S_FILECHKSMS    = 0xF4;
        constexpr uint16_t K_S_FRAMEPROC           = 0x1012;
        constexpr uint16_t K_S_OBJNAME             = 0x1101;
        constexpr uint16_t K_S_GPROC32_ID          = 0x1147;
        constexpr uint16_t K_S_PROC_ID_END         = 0x114F;
        constexpr uint16_t K_S_COMPILE3            = 0x113C;
        constexpr uint16_t K_LF_PROCEDURE          = 0x1008;
        constexpr uint16_t K_LF_ARGLIST            = 0x1201;
        constexpr uint16_t K_LF_FUNC_ID            = 0x1601;
        constexpr uint32_t K_CV_CFL_CXX            = 0x01;
        constexpr uint16_t K_CV_CFL_AMD64          = 0x00D0;
        constexpr uint32_t K_CV_TYPE_SIGNATURE     = 4;
        constexpr uint32_t K_CV_FIRST_NONPRIM      = 0x1000;
        constexpr uint32_t K_T_VOID                = 0x0003;
        constexpr uint8_t  K_CV_CALL_NEAR_C        = 0x00;
        constexpr uint32_t K_CV_FRAMEPROC_FLAGS    = 0x00114200;
        constexpr uint16_t K_CHKSUM_TYPE_NONE      = 0x00;
        constexpr uint32_t K_CV_LINE_STATEMENT_BIT = 0x80000000u;

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
                entries.push_back(stringOffset);
                offsets.emplace(fileName, entryOffset);
                size += 8;
                return entryOffset;
            }

            void commit(std::vector<std::byte>& outBytes) const
            {
                for (const uint32_t stringOffset : entries)
                {
                    outBytes.insert(outBytes.end(), reinterpret_cast<const std::byte*>(&stringOffset), reinterpret_cast<const std::byte*>(&stringOffset) + sizeof(stringOffset));
                    outBytes.push_back(static_cast<std::byte>(0));
                    outBytes.push_back(static_cast<std::byte>(K_CHKSUM_TYPE_NONE));
                    outBytes.push_back(std::byte{0});
                    outBytes.push_back(std::byte{0});
                }
            }

            uint32_t                           size = 0;
            std::unordered_map<Utf8, uint32_t> offsets;
            std::vector<uint32_t>              entries;
        };

        void writeU16(std::vector<std::byte>& bytes, const uint16_t value)
        {
            const auto* src = reinterpret_cast<const std::byte*>(&value);
            bytes.insert(bytes.end(), src, src + sizeof(value));
        }

        void writeU32(std::vector<std::byte>& bytes, const uint32_t value)
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

                const auto fileName = Utf8(file->path().string());

                size_t     blockIndex = 0;
                const auto blockIt    = blockIndices.find(fileName);
                if (blockIt == blockIndices.end())
                {
                    blockIndex = result.blocks.size();
                    result.blocks.push_back({.fileName = fileName});
                    blockIndices.emplace(fileName, blockIndex);
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
            const auto     objectName   = Utf8(objectPath.string());
            const uint32_t recordOffset = beginRecord(bytes, K_S_OBJNAME);
            writeU32(bytes, 0);
            writeCString(bytes, objectName);
            endRecord(bytes, recordOffset);
        }

        void appendProcSymbols(std::vector<std::byte>& bytes, NativeSectionData& debugSection, const DebugInfoFunctionRecord& function, const uint32_t typeIndex)
        {
            SWC_ASSERT(function.machineCode != nullptr);

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
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeU32(bytes, 0);
            writeU16(bytes, 0);
            writeU32(bytes, K_CV_FRAMEPROC_FLAGS);
            endRecord(bytes, frameOffset);

            const uint32_t endOffset = beginRecord(bytes, K_S_PROC_ID_END);
            SWC_UNUSED(endOffset);
            endRecord(bytes, endOffset);
        }

        struct TypeTableBuilder
        {
            void begin()
            {
                writeU32(bytes, K_CV_TYPE_SIGNATURE);
            }

            uint32_t appendEmptyArgList()
            {
                const uint32_t typeIndex    = nextTypeIndex++;
                const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_ARGLIST);
                writeU32(bytes, 0);
                endTypeRecord(bytes, recordOffset);
                return typeIndex;
            }

            uint32_t appendProcedureType(const uint32_t argListType)
            {
                const uint32_t typeIndex    = nextTypeIndex++;
                const uint32_t recordOffset = beginTypeRecord(bytes, K_LF_PROCEDURE);
                writeU32(bytes, K_T_VOID);
                bytes.push_back(static_cast<std::byte>(K_CV_CALL_NEAR_C));
                bytes.push_back(std::byte{0});
                writeU16(bytes, 0);
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

            std::vector<std::byte> bytes;
            uint32_t               nextTypeIndex = K_CV_FIRST_NONPRIM;
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
            if (!request.ctx || request.functions.empty())
                return Result::Continue;

            NativeSectionData debugSection;
            debugSection.name            = ".debug$S";
            debugSection.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_DISCARDABLE | IMAGE_SCN_ALIGN_1BYTES | IMAGE_SCN_MEM_READ;

            writeU32(debugSection.bytes, K_CV_SIGNATURE_C13);

            std::vector<FunctionLines> functionLines;
            functionLines.reserve(request.functions.size());

            StringTableBuilder  strings;
            FileChecksumBuilder checksums;
            TypeTableBuilder    types;
            types.begin();
            const uint32_t        argListType = types.appendEmptyArgList();
            const uint32_t        procType    = types.appendProcedureType(argListType);
            std::vector<uint32_t> functionTypeIndices;
            functionTypeIndices.reserve(request.functions.size());
            for (const DebugInfoFunctionRecord& function : request.functions)
            {
                const FunctionLines lines = function.machineCode ? collectFunctionLines(*request.ctx, *function.machineCode) : FunctionLines{};
                for (const auto& block : lines.blocks)
                {
                    const uint32_t stringOffset = strings.insert(block.fileName);
                    checksums.insert(block.fileName, stringOffset);
                }

                functionLines.push_back(lines);
                functionTypeIndices.push_back(types.appendFunctionId(function.debugName.empty() ? function.symbolName : function.debugName, procType));
            }

            if (!checksums.entries.empty())
            {
                const uint32_t stringLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_STRINGTABLE);
                strings.commit(debugSection.bytes);
                endSubsection(debugSection.bytes, stringLenOffset);

                const uint32_t checksumLenOffset = beginSubsection(debugSection.bytes, K_DEBUG_S_FILECHKSMS);
                checksums.commit(debugSection.bytes);
                endSubsection(debugSection.bytes, checksumLenOffset);
            }

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
                    appendProcSymbols(debugSection.bytes, debugSection, function, functionTypeIndices[i]);
                    endSubsection(debugSection.bytes, symbolsLenOffset);
                }

                appendLinesSubsection(debugSection.bytes, debugSection, request.functions[i], functionLines[i], checksums);
            }

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

        bool parseImageLayout(const fs::path& imagePath, uint32_t& outTextRva, uint32_t& outImageSize)
        {
            outTextRva   = 0;
            outImageSize = 0;

            std::ifstream file(imagePath, std::ios::binary);
            if (!file.is_open())
                return false;

            IMAGE_DOS_HEADER dosHeader{};
            file.read(reinterpret_cast<char*>(&dosHeader), sizeof(dosHeader));
            if (!file.good() || dosHeader.e_magic != IMAGE_DOS_SIGNATURE)
                return false;

            file.seekg(dosHeader.e_lfanew, std::ios::beg);
            DWORD signature = 0;
            file.read(reinterpret_cast<char*>(&signature), sizeof(signature));
            if (!file.good() || signature != IMAGE_NT_SIGNATURE)
                return false;

            IMAGE_FILE_HEADER fileHeader{};
            file.read(reinterpret_cast<char*>(&fileHeader), sizeof(fileHeader));
            if (!file.good())
                return false;

            IMAGE_OPTIONAL_HEADER64 optionalHeader{};
            file.read(reinterpret_cast<char*>(&optionalHeader), sizeof(optionalHeader));
            if (!file.good() || optionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC)
                return false;

            outImageSize = optionalHeader.SizeOfImage;

            for (uint16_t i = 0; i < fileHeader.NumberOfSections; ++i)
            {
                IMAGE_SECTION_HEADER section{};
                file.read(reinterpret_cast<char*>(&section), sizeof(section));
                if (!file.good())
                    return false;

                if ((section.Characteristics & IMAGE_SCN_CNT_CODE) == 0)
                    continue;

                outTextRva = section.VirtualAddress;
                return outTextRva != 0;
            }

            return false;
        }

        fs::path defaultJitDebugRoot()
        {
            return Os::getTemporaryPath() / "swc_jit_debug";
        }
    }

    Result buildWindowsObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult)
    {
        outResult.sections.clear();
        outResult.symbols.clear();

        SWC_RESULT_VERIFY(appendCodeViewSection(request, outResult));
        SWC_RESULT_VERIFY(appendUnwindSections(request, outResult));
        return Result::Continue;
    }

    bool emitWindowsJitArtifact(const JitDebugRequest& request, JitDebugArtifact& outArtifact)
    {
        outArtifact = {};
        if (!request.ctx || !request.function || !request.machineCode || !request.codeAddress)
            return false;
        if (!request.ctx->compiler().buildCfg().backend.debugInfo)
            return false;
        if (!Os::isDebuggerAttached())
            return false;

        Os::WindowsToolchainPaths toolchain;
        if (Os::discoverWindowsToolchainPaths(toolchain) != Os::WindowsToolchainDiscoveryResult::Ok)
            return false;

        fs::path workDir = request.workDir;
        if (workDir.empty())
            workDir = defaultJitDebugRoot();

        const uint32_t uniqueId    = request.ctx->compiler().atomicId().fetch_add(1, std::memory_order_relaxed);
        const Utf8     baseNameRaw = request.debugName.empty() ? request.symbolName : request.debugName;
        const Utf8     baseName    = FileSystem::sanitizeFileName(baseNameRaw.empty() ? Utf8("jit") : baseNameRaw);
        const Utf8     uniqueName  = std::format("{}_{:08x}", baseName, uniqueId);
        const Utf8     symbolName  = std::format("__swc_jit_fn_{}", uniqueName);

        std::error_code ec;
        fs::create_directories(workDir, ec);
        if (ec)
            return false;

        const fs::path objPath   = workDir / std::format("{}.obj", uniqueName);
        const fs::path imagePath = workDir / std::format("{}.dll", uniqueName);
        const fs::path pdbPath   = workDir / std::format("{}.pdb", uniqueName);

        NativeBackendBuilder tempBuilder(request.ctx->compiler(), false);
        tempBuilder.functionInfos.push_back({
            .symbol      = const_cast<SymbolFunction*>(request.function),
            .machineCode = request.machineCode,
            .sortKey     = uniqueName,
            .symbolName  = symbolName,
            .debugName   = request.debugName.empty() ? uniqueName : request.debugName,
        });
        tempBuilder.functionBySymbol.emplace(const_cast<SymbolFunction*>(request.function), &tempBuilder.functionInfos.back());

        NativeObjDescription description;
        description.index                  = 0;
        description.objPath                = objPath;
        description.includeData            = false;
        description.allowUnresolvedSymbols = true;
        description.functions.push_back(&tempBuilder.functionInfos.back());

        const auto writer = NativeObjFileWriter::create(tempBuilder);
        if (!writer)
            return false;
        if (writer->writeObjectFile(description) != Result::Continue)
            return false;

        std::vector<Utf8> args;
        args.emplace_back("/NOLOGO");
        args.emplace_back("/NODEFAULTLIB");
        args.emplace_back("/INCREMENTAL:NO");
        args.emplace_back("/MACHINE:X64");
        args.emplace_back("/DLL");
        args.emplace_back("/NOENTRY");
        args.emplace_back("/DEBUG:FULL");
        args.emplace_back("/OPT:NOREF");
        args.emplace_back("/FORCE:UNRESOLVED");
        args.emplace_back(std::format("/OUT:{}", Utf8(imagePath)));
        args.emplace_back(std::format("/PDB:{}", Utf8(pdbPath)));
        args.emplace_back(objPath);

        uint32_t   exitCode  = 0;
        const auto runResult = Os::runProcess(exitCode, toolchain.linkExe, args, workDir);
        if (runResult != Os::ProcessRunResult::Ok)
            return false;
        if (!fs::exists(imagePath) || !fs::exists(pdbPath))
            return false;

        uint32_t textRva   = 0;
        uint32_t imageSize = 0;
        if (!parseImageLayout(imagePath, textRva, imageSize))
            return false;

        outArtifact.imagePath  = imagePath;
        outArtifact.pdbPath    = pdbPath;
        outArtifact.imageSize  = imageSize;
        outArtifact.moduleName = uniqueName;
        outArtifact.imageBase  = reinterpret_cast<uint64_t>(request.codeAddress) - textRva;
        return outArtifact.imageBase != 0;
    }
}

SWC_END_NAMESPACE();

#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/SymbolTable.ELF.h"
#include "Backend/Linker/LinkImage.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t TABLE_OFFSET = 144;

    ByteArray makeSymbolImage(const uint64_t base)
    {
        const std::array entries = {
            SymbolTable::Entry{.symbolName = Utf8("first"), .name = Utf8("First"), .file = Utf8("first.swg"), .line = 7, .size = 16},
            SymbolTable::Entry{.symbolName = Utf8("second"), .name = Utf8("Second"), .file = Utf8("second.swg"), .line = 9, .size = 24}};
        ByteArray bytes(TABLE_OFFSET);
        LinkImage objects;
        for (size_t index = 0; index < entries.size(); ++index)
        {
            ELFSymbolTable::appendObject(objects, std::span(&entries[index], 1));
            auto& contribution = objects.sections.back();
            contribution.bytes.writeLe64(contribution.relocs.front().offset, base + 128 + index * 32);
            bytes.align(8);
            bytes.append(contribution.bytes);
        }
        const size_t tableSize = bytes.size() - TABLE_OFFSET;
        bytes.align(8);
        const size_t headers = bytes.size();
        bytes.resize(headers + 3 * 64);
        bytes.writeLe32(0, 0x464c457f);
        bytes[4] = std::byte{2};
        bytes[5] = std::byte{1};
        bytes[6] = std::byte{1};
        bytes.writeLe16(16, base ? 2 : 3);
        bytes.writeLe16(18, 62);
        bytes.writeLe32(20, 1);
        bytes.writeLe64(32, 64);
        bytes.writeLe64(40, headers);
        bytes.writeLe16(52, 64);
        bytes.writeLe16(54, 56);
        bytes.writeLe16(56, 1);
        bytes.writeLe16(58, 64);
        bytes.writeLe16(60, 3);
        bytes.writeLe16(62, 1);
        bytes.writeLe32(64, 1);
        bytes.writeLe32(68, 5);
        bytes.writeLe64(80, base);
        bytes.writeLe64(96, TABLE_OFFSET);
        bytes.writeLe64(104, 4096);
        bytes.writeLe64(112, 4096);
        constexpr char names[] = "\0.shstrtab\0.swagdbg";
        std::memcpy(bytes.data() + 120, names, sizeof(names));
        bytes.writeLe32(headers + 64, 1);
        bytes.writeLe32(headers + 68, 3);
        bytes.writeLe64(headers + 88, 120);
        bytes.writeLe64(headers + 96, sizeof(names));
        bytes.writeLe32(headers + 128, 11);
        bytes.writeLe32(headers + 132, 1);
        bytes.writeLe64(headers + 152, TABLE_OFFSET);
        bytes.writeLe64(headers + 160, tableSize);
        return bytes;
    }
}

SWC_TEST_BEGIN(ElfSymbolTable_MergesExecutableAndSharedContributions)
{
    for (const uint64_t base : {uint64_t{0}, uint64_t{0x400000}})
    {
        ByteArray       bytes            = makeSymbolImage(base);
        const size_t    headers          = bytes.readLe64(40);
        const size_t    originalSize     = bytes.readLe64(headers + 160);
        const size_t    originalFileSize = bytes.size();
        const ByteArray loadedBytes(bytes.begin() + 64, bytes.begin() + TABLE_OFFSET);
        Utf8            error;
        if (!ELFSymbolTable::finalizeImage(bytes, error) || !error.empty())
            return Result::Error;
        if (bytes.readLe32(TABLE_OFFSET + 4) != SymbolTable::VERSION_PLAIN || bytes.readLe32(TABLE_OFFSET + 8) != 2 ||
            bytes.readLe32(TABLE_OFFSET + 16) != 128 || bytes.readLe32(TABLE_OFFSET + 36) != 160 ||
            bytes.readLe32(TABLE_OFFSET + 20) != 16 || bytes.readLe32(TABLE_OFFSET + 40) != 24 ||
            bytes.readLe32(TABLE_OFFSET + 32) != 7 || bytes.readLe32(TABLE_OFFSET + 52) != 9)
            return Result::Error;
        const auto name = reinterpret_cast<const char*>(bytes.data() + TABLE_OFFSET + bytes.readLe32(TABLE_OFFSET + 24));
        const auto file = reinterpret_cast<const char*>(bytes.data() + TABLE_OFFSET + bytes.readLe32(TABLE_OFFSET + 48));
        if (std::string_view(name) != "First" || std::string_view(file) != "second.swg")
            return Result::Error;
        const size_t finalSize = bytes.readLe64(bytes.readLe64(40) + 160);
        if (finalSize >= originalSize || bytes.size() >= originalFileSize ||
            !std::ranges::equal(loadedBytes.span(), bytes.span().subspan(64, TABLE_OFFSET - 64)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfSymbolTable_OmitsRuntimeSymbolsAndCompactsFile)
{
    ByteArray bytes = makeSymbolImage(0x400000);
    Utf8      error;
    const size_t originalSize = bytes.size();
    if (!ELFSymbolTable::finalizeImage(bytes, error, false) || !error.empty() || bytes.size() >= originalSize)
        return Result::Error;
    const uint64_t headers = bytes.readLe64(40);
    const uint64_t table   = headers + 2 * 64;
    if (bytes.readLe32(table) != 0 || bytes.readLe32(table + 4) != 0 || bytes.readLe64(table + 32) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfSymbolTable_CompactionPreservesFollowingSectionAlignment)
{
    for (const bool includeRuntimeSymbols : {true, false})
    {
        ByteArray       bytes      = makeSymbolImage(0x400000);
        const uint64_t  oldHeaders = bytes.readLe64(40);
        const ByteArray headers(bytes.begin() + oldHeaders, bytes.end());
        bytes.resize(oldHeaders);
        bytes.align(16);
        const uint64_t             trailer = bytes.size();
        constexpr std::string_view marker  = "unaltered trailer";
        bytes.append(marker);
        bytes.align(8);
        const uint64_t newHeaders = bytes.size();
        bytes.append(headers);
        bytes.resize(bytes.size() + 64);
        bytes.writeLe64(40, newHeaders);
        bytes.writeLe16(60, 4);
        bytes.writeLe32(newHeaders + 3 * 64 + 4, 1);
        bytes.writeLe64(newHeaders + 3 * 64 + 24, trailer);
        bytes.writeLe64(newHeaders + 3 * 64 + 32, marker.size());
        bytes.writeLe64(newHeaders + 3 * 64 + 48, 16);
        const size_t originalSize = bytes.size();
        Utf8         error;
        if (!ELFSymbolTable::finalizeImage(bytes, error, includeRuntimeSymbols) || !error.empty() || bytes.size() >= originalSize || (originalSize - bytes.size()) % 16)
            return Result::Error;
        const uint64_t finalHeaders = bytes.readLe64(40);
        const uint64_t offset       = bytes.readLe64(finalHeaders + 3 * 64 + 24);
        if (offset % 16 || offset >= trailer || !std::ranges::equal(bytes.span().subspan(offset, marker.size()), std::as_bytes(std::span(marker))))
            return Result::Error;
        if (!includeRuntimeSymbols)
        {
            const uint64_t table = finalHeaders + 2 * 64;
            if (bytes.readLe32(table) || bytes.readLe32(table + 4) || bytes.readLe64(table + 32))
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfSymbolTable_KeepsMappedFileRangesInPlace)
{
    ByteArray      bytes   = makeSymbolImage(0x400000);
    const uint64_t headers = bytes.readLe64(40);
    // Some external layouts include non-allocated metadata in a file-backed segment.
    bytes.writeLe64(96, headers);
    const size_t originalSize = bytes.size();
    Utf8         error;
    if (!ELFSymbolTable::finalizeImage(bytes, error) || !error.empty() || bytes.size() != originalSize || bytes.readLe64(40) != headers || bytes.readLe64(96) != headers)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfSymbolTable_UsesTargetPageAlignment)
{
    ByteArray bytes = makeSymbolImage(0x400000);
    // The first load starts within its page and requests less than page alignment.
    bytes.writeLe64(72, 128);
    bytes.writeLe64(80, 0x400080);
    bytes.writeLe64(96, 16);
    bytes.writeLe64(112, 128);
    Utf8 error;
    if (!ELFSymbolTable::finalizeImage(bytes, error) || !error.empty() || bytes.readLe32(TABLE_OFFSET + 16) != 128)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfSymbolTable_RejectsMalformedInputWithoutMutation)
{
    for (uint32_t fault = 0; fault < 11; ++fault)
    {
        ByteArray    bytes   = makeSymbolImage(0x400000);
        const size_t headers = bytes.readLe64(40);
        switch (fault)
        {
            case 0: bytes.writeLe64(40, UINT64_MAX); break;
            case 1: bytes.writeLe64(headers + 152, UINT64_MAX); break;
            case 2: bytes.writeLe64(headers + 160, UINT64_MAX); break;
            case 3: bytes.writeLe32(TABLE_OFFSET + 4, 99); break;
            case 4: bytes.writeLe32(TABLE_OFFSET + 8, UINT32_MAX); break;
            case 5: bytes.writeLe64(TABLE_OFFSET + 16, UINT64_MAX); break;
            case 6: bytes.writeLe32(TABLE_OFFSET + 36, 1); break;
            case 7: bytes.writeLe64(TABLE_OFFSET + 24, 0); break;
            case 8: bytes.writeLe64(TABLE_OFFSET + 24, uint64_t{0x400000} + UINT32_MAX); break;
            case 9: bytes.writeLe64(112, 3); break;
            case 10:
                bytes[131] = std::byte{'x'};
                bytes[139] = std::byte{'x'};
                break;
        }
        const ByteArray original = bytes;
        Utf8            error;
        if (ELFSymbolTable::finalizeImage(bytes, error) || error.empty() || bytes != original)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfSymbolTable_AllowsMissingSymbols)
{
    for (uint32_t mode = 0; mode < 3; ++mode)
    {
        ByteArray bytes = makeSymbolImage(0);
        if (mode == 1)
        {
            bytes.writeLe64(40, 0);
            bytes.writeLe16(60, 0);
        }
        else if (mode == 2)
            bytes.writeLe16(62, 0);
        else
            bytes[131] = std::byte{'x'};
        const ByteArray original = bytes;
        Utf8            error;
        if (!ELFSymbolTable::finalizeImage(bytes, error) || !error.empty() || bytes != original)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif

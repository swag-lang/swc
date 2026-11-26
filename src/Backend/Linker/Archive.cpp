#include "pch.h"
#include "Backend/Linker/Archive.h"
#include "Main/FileSystem.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const char* archiveNameEnd(const char* cursor, const char* end)
    {
        constexpr uint64_t lowBits  = 0x0101010101010101ull;
        constexpr uint64_t highBits = 0x8080808080808080ull;
        while (static_cast<size_t>(end - cursor) >= sizeof(uint64_t))
        {
            uint64_t word;
            std::memcpy(&word, cursor, sizeof(word));
            // Check every byte for zero, then find the first match in file order.
            if ((word - lowBits) & ~word & highBits)
                break;
            cursor += sizeof(word);
        }
        while (cursor != end && *cursor)
            ++cursor;
        return cursor != end ? cursor : nullptr;
    }

    constexpr std::string_view ARCHIVE_MAGIC      = "!<arch>\n";
    constexpr size_t           MEMBER_HEADER_SIZE = 60;

    // Member sizes are stored as a right-padded decimal ASCII string.
    bool parseMemberSize(uint32_t& outSize, const ByteView bytes, size_t headerOffset)
    {
        if (!bytes.containsRange(headerOffset, MEMBER_HEADER_SIZE))
            return false;

        outSize = 0;
        for (size_t i = 48; i < 58; ++i)
        {
            const char c = static_cast<char>(bytes.data()[headerOffset + i]);
            if (c == ' ')
                break;
            if (c < '0' || c > '9')
                return false;
            const uint32_t digit = static_cast<uint32_t>(c - '0');
            if (outSize > (UINT32_MAX - digit) / 10)
                return false;
            outSize = outSize * 10 + digit;
        }

        return true;
    }

}

Archive::Archive(Archive&& other) noexcept :
    ownedBytes_(std::move(other.ownedBytes_)),
    mapping_(std::move(other.mapping_)),
    bytes_(std::exchange(other.bytes_, ByteView{})),
    symbolToMember_(std::move(other.symbolToMember_)),
    sourcePath_(std::move(other.sourcePath_))
{
}

Archive& Archive::operator=(Archive&& other) noexcept
{
    if (this != &other)
    {
        symbolToMember_ = std::move(other.symbolToMember_);
        ownedBytes_     = std::move(other.ownedBytes_);
        mapping_        = std::move(other.mapping_);
        bytes_          = std::exchange(other.bytes_, ByteView{});
        sourcePath_     = std::move(other.sourcePath_);
    }
    return *this;
}

bool Archive::load(Diagnostic& outDiag, ByteArray bytes)
{
    symbolToMember_.clear();
    mapping_.reset();
    ownedBytes_ = std::move(bytes);
    bytes_      = ByteView(ownedBytes_.span());
    return decode(outDiag);
}

bool Archive::loadFile(Diagnostic& outDiag, const fs::path& path)
{
    auto mapping = std::make_unique<Os::ReadOnlyFileMapping>();
    if (!mapping->open(path, std::numeric_limits<size_t>::max()))
    {
        FileSystem::IoErrorInfo ioError;
        ByteArray               bytes;
        if (FileSystem::readBinaryFile(path, bytes, ioError) != Result::Continue)
            return false;
        return load(outDiag, std::move(bytes));
    }

    symbolToMember_.clear();
    ownedBytes_ = ByteArray{};
    mapping_    = std::move(mapping);
    bytes_      = ByteView(mapping_->bytes());
    return decode(outDiag);
}

bool Archive::decode(Diagnostic& outDiag)
{
    if (!bytes_.containsRange(0, ARCHIVE_MAGIC.size()) || std::memcmp(bytes_.data(), ARCHIVE_MAGIC.data(), ARCHIVE_MAGIC.size()) != 0)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_magic);
        return false;
    }

    // The first member is the linker member: a big-endian symbol -> member-offset directory.
    constexpr size_t firstHeader = ARCHIVE_MAGIC.size();
    if (!bytes_.containsRange(firstHeader, MEMBER_HEADER_SIZE))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_truncated);
        return false;
    }

    if (std::memcmp(bytes_.data() + firstHeader, "/SYM64/", 7) == 0)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_symbol_index);
        return false;
    }

    uint32_t memberSize = 0;
    if (!parseMemberSize(memberSize, bytes_, firstHeader))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_member);
        return false;
    }

    constexpr size_t dataOffset = firstHeader + MEMBER_HEADER_SIZE;
    if (!bytes_.containsRange(dataOffset, memberSize) || memberSize < 4)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_truncated_linker_member);
        return false;
    }

    const uint32_t   symbolCount = bytes_.readBe32(dataOffset);
    constexpr size_t offsetsAt   = dataOffset + 4;
    const size_t     namesAt     = offsetsAt + static_cast<size_t>(symbolCount) * 4;
    if (namesAt > dataOffset + memberSize)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_symbol_index);
        return false;
    }

    symbolToMember_.reserve(symbolCount);
    size_t       nameCursor = namesAt;
    const size_t memberEnd  = dataOffset + memberSize;
    for (uint32_t i = 0; i < symbolCount; ++i)
    {
        if (nameCursor >= memberEnd)
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_symbol_names);
            return false;
        }

        const auto* nameStart  = reinterpret_cast<const char*>(bytes_.data() + nameCursor);
        const auto* terminator = archiveNameEnd(nameStart, nameStart + (memberEnd - nameCursor));
        if (!terminator)
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_symbol_names);
            return false;
        }

        const uint32_t         memberOffset = bytes_.readBe32(offsetsAt + static_cast<size_t>(i) * 4);
        const std::string_view name{nameStart, terminator};
        symbolToMember_.try_emplace(name, Math::hash(name), memberOffset);
        nameCursor += name.size() + 1;
    }

    return true;
}

uint32_t Archive::memberOffsetForSymbol(const std::string_view symbol) const
{
    const uint32_t* memberOffset = symbolToMember_.find(symbol, Math::hash(symbol));
    return memberOffset ? *memberOffset : 0;
}

std::vector<uint32_t> Archive::memberOffsetsForSymbol(const std::string_view symbol) const
{
    std::vector<uint32_t> result;
    uint32_t              size = 0;
    constexpr size_t      data = ARCHIVE_MAGIC.size() + MEMBER_HEADER_SIZE;
    if (!parseMemberSize(size, bytes_, ARCHIVE_MAGIC.size()) || size < 4 || !bytes_.containsRange(data, size))
        return result;
    const uint32_t count = bytes_.readBe32(data);
    if (count > (size - 4) / 4)
        return result;
    size_t       cursor = data + 4 + size_t{count} * 4;
    const size_t end    = data + size;
    for (uint32_t index = 0; index < count && cursor < end; ++index)
    {
        const char* begin      = reinterpret_cast<const char*>(bytes_.data() + cursor);
        const auto* terminator = static_cast<const char*>(std::memchr(begin, 0, end - cursor));
        if (!terminator)
            return {};
        if (std::string_view(begin, terminator) == symbol)
        {
            const uint32_t offset = bytes_.readBe32(data + 4 + size_t{index} * 4);
            if (std::ranges::find(result, offset) == result.end())
                result.push_back(offset);
        }
        cursor += terminator - begin + 1;
    }
    return result;
}

std::span<const std::byte> Archive::memberData(Diagnostic& outDiag, uint32_t headerOffset) const
{
    if (!bytes_.containsRange(headerOffset, MEMBER_HEADER_SIZE))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_member_out_of_range);
        return {};
    }

    uint32_t memberSize = 0;
    if (!parseMemberSize(memberSize, bytes_, headerOffset))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_member);
        return {};
    }

    const size_t dataOffset = headerOffset + MEMBER_HEADER_SIZE;
    if (!bytes_.containsRange(dataOffset, memberSize))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_truncated_member);
        return {};
    }

    return {bytes_.data() + dataOffset, memberSize};
}

SWC_END_NAMESPACE();

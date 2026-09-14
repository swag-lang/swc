#include "pch.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/CoffReader.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include <charconv>

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view ARCHIVE_MAGIC        = "!<arch>\n";
    constexpr size_t           MEMBER_HEADER_SIZE   = 60;
    constexpr size_t           IMPORT_HEADER_SIZE   = 20;
    constexpr uint16_t         IMPORT_SIG2          = 0xFFFF;
    constexpr uint16_t         IMPORT_MACHINE_AMD64 = 0x8664;

    // Member sizes are stored as a right-padded decimal ASCII string.
    bool parseMemberSize(uint32_t& outSize, const ByteArray& bytes, size_t headerOffset)
    {
        if (!bytes.containsRange(headerOffset, MEMBER_HEADER_SIZE))
            return false;

        outSize = 0;
        for (size_t i = 48; i < 58; ++i)
        {
            const char c = static_cast<char>(bytes[headerOffset + i]);
            if (c == ' ')
                break;
            if (c < '0' || c > '9')
                return false;
            outSize = outSize * 10 + static_cast<uint32_t>(c - '0');
        }
        return true;
    }

    uint16_t readLe16(const std::span<const std::byte> bytes, const size_t offset) noexcept
    {
        SWC_ASSERT(offset <= bytes.size() && sizeof(uint16_t) <= bytes.size() - offset);
        return static_cast<uint16_t>(std::to_integer<uint16_t>(bytes[offset + 0]) | (std::to_integer<uint16_t>(bytes[offset + 1]) << 8));
    }

    size_t archiveAlignedSize(size_t size)
    {
        return Math::alignUpU64(size, 2);
    }
}

bool Archive::load(Diagnostic& outDiag, ByteArray bytes)
{
    symbolToMember_.clear();
    bytes_ = std::move(bytes);

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
        const auto* nameStart = reinterpret_cast<const char*>(bytes_.data() + nameCursor);
        size_t      nameLen   = 0;
        while (nameCursor + nameLen < memberEnd && nameStart[nameLen] != '\0')
            ++nameLen;

        const uint32_t memberOffset = bytes_.readBe32(offsetsAt + static_cast<size_t>(i) * 4);
        symbolToMember_.emplace(std::string_view{nameStart, nameLen}, memberOffset);
        nameCursor += nameLen + 1;
    }

    return true;
}

uint32_t Archive::memberOffsetForSymbol(const Utf8& symbol) const
{
    const auto it = symbolToMember_.find(symbol.view());
    return it == symbolToMember_.end() ? 0 : it->second;
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

bool Archive::tryReadImport(ArchiveImport& outImport, Diagnostic& outDiag, uint32_t headerOffset) const
{
    const std::span<const std::byte> data = memberData(outDiag, headerOffset);
    if (data.empty())
        return false;
    if (data.size() < IMPORT_HEADER_SIZE)
        return false;
    if (readLe16(data, 0) != 0 || readLe16(data, 2) != IMPORT_SIG2)
        return false; // a regular COFF member, not a short import

    const uint16_t ordinalOrHint = readLe16(data, 16);
    const uint16_t flags         = readLe16(data, 18);
    const uint16_t type          = flags & 0x3;
    const uint16_t nameType      = (flags >> 2) & 0x7;

    // Strings follow the header: importName\0 dllName\0.
    const auto*  strings = reinterpret_cast<const char*>(data.data() + IMPORT_HEADER_SIZE);
    const size_t maxLen  = data.size() - IMPORT_HEADER_SIZE;
    size_t       nameLen = 0;
    while (nameLen < maxLen && strings[nameLen] != '\0')
        ++nameLen;
    const std::string_view importName{strings, nameLen};
    const size_t           dllStart = nameLen + 1;
    size_t                 dllLen   = 0;
    while (dllStart + dllLen < maxLen && strings[dllStart + dllLen] != '\0')
        ++dllLen;
    const std::string_view dllName{strings + dllStart, dllLen};

    outImport.importName = Utf8{importName};
    outImport.dll        = Utf8{dllName};
    outImport.isData     = type == 1;     // IMPORT_OBJECT_DATA
    outImport.byOrdinal  = nameType == 0; // IMPORT_OBJECT_ORDINAL
    outImport.ordinal    = ordinalOrHint;
    return true;
}

namespace
{
    void appendHeaderField(const std::span<char> outHeader, std::string_view value, size_t offset, size_t width)
    {
        std::memcpy(outHeader.data() + offset, value.data(), std::min(value.size(), width));
    }

    // Writes a 60-byte archive member header. Numeric fields are left-justified, space-padded.
    void appendMemberHeader(ByteArray& out, std::string_view name, uint32_t dataSize)
    {
        std::array<char, MEMBER_HEADER_SIZE> header;
        header.fill(' ');
        appendHeaderField(header, name, 0, 16);
        appendHeaderField(header, "0", 16, 12); // date
        appendHeaderField(header, "0", 28, 6);  // uid
        appendHeaderField(header, "0", 34, 6);  // gid
        appendHeaderField(header, "0", 40, 8);  // mode
        const auto result = std::to_chars(header.data() + 48, header.data() + 58, dataSize);
        SWC_ASSERT(result.ec == std::errc{});
        header[58] = '\x60';
        header[59] = '\n';
        out.append(std::string_view{header.data(), header.size()});
    }

    void appendArchiveMember(ByteArray& outBytes, std::string_view name, std::span<const std::byte> data)
    {
        appendMemberHeader(outBytes, name, static_cast<uint32_t>(data.size()));
        outBytes.append(data);
        if (data.size() & 1)
            outBytes.pushBack(static_cast<std::byte>('\n'));
    }

    struct ArchiveMemberBuild
    {
        Utf8                       name;
        std::span<const std::byte> data;
        std::vector<Utf8>          symbols;
        uint32_t                   headerOffset = 0;
    };

    // Assembles a COFF archive from prepared members: the linker symbol directory, an optional
    // long-names member, then the member contents.
    void emitArchive(ByteArray& outBytes, std::vector<ArchiveMemberBuild>& members)
    {
        // Long member names (>15 chars do not fit the inline "name/" form) live in a "//" member; an
        // affected member references them with "/<decimal-offset>".
        ByteArray         longNames;
        std::vector<Utf8> nameField(members.size());
        for (size_t i = 0; i < members.size(); ++i)
        {
            const Utf8& name = members[i].name;
            if (name.size() <= 15)
            {
                nameField[i] = name;
                nameField[i] += "/";
            }
            else
            {
                nameField[i] = std::format("/{}", longNames.size());
                longNames.append(name.view());
                longNames.pushBack(static_cast<std::byte>('\n'));
            }
        }

        uint32_t symbolCount     = 0;
        size_t   symbolNamesSize = 0;
        for (const ArchiveMemberBuild& member : members)
        {
            symbolCount += static_cast<uint32_t>(member.symbols.size());
            for (const Utf8& symbol : member.symbols)
                symbolNamesSize += symbol.size() + 1;
        }

        const size_t linkerDataSize = 4 + static_cast<size_t>(symbolCount) * 4 + symbolNamesSize;

        // Compute each member header's file offset now that the leading members' sizes are known.
        size_t cursor = 8; // after "!<arch>\n"
        cursor += MEMBER_HEADER_SIZE + archiveAlignedSize(linkerDataSize);
        const bool hasLongNames = !longNames.empty();
        if (hasLongNames)
            cursor += MEMBER_HEADER_SIZE + archiveAlignedSize(longNames.size());
        for (ArchiveMemberBuild& member : members)
        {
            member.headerOffset = static_cast<uint32_t>(cursor);
            cursor += MEMBER_HEADER_SIZE + archiveAlignedSize(member.data.size());
        }

        outBytes.clear();
        outBytes.reserve(cursor);
        outBytes.append(ARCHIVE_MAGIC);

        // Emit the linker directory directly into the final archive buffer.
        appendMemberHeader(outBytes, "/", static_cast<uint32_t>(linkerDataSize));
        outBytes.appendBe32(symbolCount);
        for (const ArchiveMemberBuild& member : members)
            for (size_t s = 0; s < member.symbols.size(); ++s)
                outBytes.appendBe32(member.headerOffset);
        for (const ArchiveMemberBuild& member : members)
        {
            for (const Utf8& symbol : member.symbols)
                outBytes.appendCString(symbol.view());
        }
        if (linkerDataSize & 1)
            outBytes.pushBack(static_cast<std::byte>('\n'));

        if (hasLongNames)
            appendArchiveMember(outBytes, "//", longNames.span());
        for (size_t i = 0; i < members.size(); ++i)
            appendArchiveMember(outBytes, nameField[i].view(), members[i].data);
    }
}

bool buildCoffStaticArchive(ByteArray& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& inputMembers)
{
    ByteArray aliasedMemberBytes;
    std::vector<ArchiveMemberBuild> members;
    members.reserve(inputMembers.size());

    std::vector<CoffInputSymbol> symbols;
    for (const LinkArchiveMember& inputMember : inputMembers)
    {
        if (!readCoffDefinedSymbols(symbols, outDiag, inputMember.bytes.span()))
            return false;

        ArchiveMemberBuild member;
        member.name = inputMember.name;
        member.data = inputMember.bytes.span();
        if (&outBytes == &inputMember.bytes)
        {
            // Emission replaces the output buffer; retain only the input member it would overwrite.
            aliasedMemberBytes = inputMember.bytes;
            member.data        = aliasedMemberBytes.span();
        }
        member.symbols.reserve(symbols.size());
        for (CoffInputSymbol& symbol : symbols)
            member.symbols.push_back(std::move(symbol.name));
        members.push_back(std::move(member));
    }

    emitArchive(outBytes, members);
    return true;
}

void buildCoffImportLibrary(ByteArray& outBytes, std::string_view dllFileName, const std::vector<Utf8>& exportNames)
{
    // Reserve the complete buffer before borrowing spans so later records cannot invalidate them.
    size_t recordsSize = 0;
    for (const Utf8& name : exportNames)
        recordsSize += IMPORT_HEADER_SIZE + name.size() + 1 + dllFileName.size() + 1;
    ByteArray importRecords;
    importRecords.reserve(recordsSize);
    std::vector<ArchiveMemberBuild> members;
    members.reserve(exportNames.size());

    for (const Utf8& name : exportNames)
    {
        // A short-import record: IMPORT_OBJECT_HEADER followed by importName\0 dllName\0.
        const size_t recordOffset = importRecords.size();
        importRecords.appendLe16(0); // Sig1
        importRecords.appendLe16(IMPORT_SIG2);
        importRecords.appendLe16(0); // Version
        importRecords.appendLe16(IMPORT_MACHINE_AMD64);
        importRecords.appendLe32(0);                                                               // TimeDateStamp
        importRecords.appendLe32(static_cast<uint32_t>(name.size() + 1 + dllFileName.size() + 1)); // SizeOfData
        importRecords.appendLe16(0);                                                               // OrdinalOrHint
        importRecords.appendLe16(1 << 2);                                                          // NameType=NAME(1), Type=CODE(0)
        importRecords.appendCString(name.view());
        importRecords.appendCString(dllFileName);

        ArchiveMemberBuild member;
        member.name = Utf8(dllFileName);
        member.data = importRecords.span().subspan(recordOffset);
        member.symbols.push_back(name);               // the thunk symbol
        member.symbols.emplace_back("__imp_" + name); // the IAT symbol
        members.push_back(std::move(member));
    }

    emitArchive(outBytes, members);
}

SWC_END_NAMESPACE();

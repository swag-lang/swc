#include "pch.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/CoffReader.h"
#include "Main/FileSystem.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view ARCHIVE_MAGIC        = "!<arch>\n";
    constexpr size_t           MEMBER_HEADER_SIZE   = 60;
    constexpr size_t           IMPORT_HEADER_SIZE   = 20;
    constexpr uint16_t         IMPORT_SIG2          = 0xFFFF;
    constexpr uint16_t         IMPORT_MACHINE_AMD64 = 0x8664;

    // Member sizes are stored as a right-padded decimal ASCII string.
    bool parseMemberSize(uint32_t& outSize, ByteSpan bytes, size_t headerOffset)
    {
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

    size_t archiveAlignedSize(size_t size)
    {
        return Math::alignUpU64(size, 2);
    }
}

bool Archive::load(Diagnostic& outDiag, std::vector<std::byte> bytes)
{
    bytes_ = std::move(bytes);
    symbolToMember_.clear();

    const ByteSpan span = asByteSpan(bytes_);
    if (span.size() < ARCHIVE_MAGIC.size() || asStringView(span.subspan(0, ARCHIVE_MAGIC.size())) != ARCHIVE_MAGIC)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_magic);
        return false;
    }

    // The first member is the linker member: a big-endian symbol -> member-offset directory.
    constexpr size_t firstHeader = ARCHIVE_MAGIC.size();
    if (firstHeader + MEMBER_HEADER_SIZE > span.size())
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_truncated);
        return false;
    }

    uint32_t memberSize = 0;
    if (!parseMemberSize(memberSize, span, firstHeader))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_member);
        return false;
    }

    constexpr size_t dataOffset = firstHeader + MEMBER_HEADER_SIZE;
    if (dataOffset + memberSize > span.size() || memberSize < 4)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_truncated_linker_member);
        return false;
    }

    const uint32_t   symbolCount = ByteUtils::readBE32(span, dataOffset);
    constexpr size_t offsetsAt   = dataOffset + 4;
    const size_t     namesAt     = offsetsAt + static_cast<size_t>(symbolCount) * 4;
    if (namesAt > dataOffset + memberSize)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_symbol_index);
        return false;
    }

    size_t       nameCursor = namesAt;
    const size_t memberEnd  = dataOffset + memberSize;
    for (uint32_t i = 0; i < symbolCount; ++i)
    {
        if (nameCursor >= memberEnd)
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_symbol_names);
            return false;
        }
        const auto* nameStart = reinterpret_cast<const char*>(span.data() + nameCursor);
        size_t      nameLen   = 0;
        while (nameCursor + nameLen < memberEnd && nameStart[nameLen] != '\0')
            ++nameLen;

        const uint32_t memberOffset = ByteUtils::readBE32(span, offsetsAt + static_cast<size_t>(i) * 4);
        symbolToMember_.emplace(Utf8{std::string_view{nameStart, nameLen}}, memberOffset);
        nameCursor += nameLen + 1;
    }

    return true;
}

uint32_t Archive::memberOffsetForSymbol(const Utf8& symbol) const
{
    const auto it = symbolToMember_.find(symbol);
    return it == symbolToMember_.end() ? 0 : it->second;
}

ByteSpan Archive::memberData(Diagnostic& outDiag, uint32_t headerOffset) const
{
    const ByteSpan span = asByteSpan(bytes_);
    if (headerOffset + MEMBER_HEADER_SIZE > span.size())
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_member_out_of_range);
        return {};
    }
    uint32_t memberSize = 0;
    if (!parseMemberSize(memberSize, span, headerOffset))
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_bad_member);
        return {};
    }
    const size_t dataOffset = headerOffset + MEMBER_HEADER_SIZE;
    if (dataOffset + memberSize > span.size())
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_archive_truncated_member);
        return {};
    }
    return span.subspan(dataOffset, memberSize);
}

bool Archive::tryReadImport(ArchiveImport& outImport, Diagnostic& outDiag, uint32_t headerOffset) const
{
    const ByteSpan data = memberData(outDiag, headerOffset);
    if (data.empty())
        return false;
    if (data.size() < IMPORT_HEADER_SIZE)
        return false;
    if (ByteUtils::readLE16(data, 0) != 0 || ByteUtils::readLE16(data, 2) != IMPORT_SIG2)
        return false; // a regular COFF member, not a short import

    const uint16_t ordinalOrHint = ByteUtils::readLE16(data, 16);
    const uint16_t flags         = ByteUtils::readLE16(data, 18);
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
    void appendHeaderField(std::string& outHeader, std::string_view value, size_t offset, size_t width)
    {
        std::memcpy(outHeader.data() + offset, value.data(), std::min(value.size(), width));
    }

    // Writes a 60-byte archive member header. Numeric fields are left-justified, space-padded.
    void appendMemberHeader(std::vector<std::byte>& out, std::string_view name, uint32_t dataSize)
    {
        std::string header(MEMBER_HEADER_SIZE, ' ');
        appendHeaderField(header, name, 0, 16);
        appendHeaderField(header, "0", 16, 12); // date
        appendHeaderField(header, "0", 28, 6);  // uid
        appendHeaderField(header, "0", 34, 6);  // gid
        appendHeaderField(header, "0", 40, 8);  // mode
        appendHeaderField(header, std::to_string(dataSize), 48, 10);
        header[58] = '\x60';
        header[59] = '\n';
        ByteUtils::appendString(out, header);
    }

    void appendArchiveMember(std::vector<std::byte>& outBytes, std::string_view name, const std::vector<std::byte>& data)
    {
        appendMemberHeader(outBytes, name, static_cast<uint32_t>(data.size()));
        ByteUtils::appendBytes(outBytes, asByteSpan(data));
        if (data.size() & 1)
            outBytes.push_back(static_cast<std::byte>('\n'));
    }

    struct ArchiveMemberBuild
    {
        Utf8                   name;
        std::vector<std::byte> data;
        std::vector<Utf8>      symbols;
        uint32_t               headerOffset = 0;
    };

    // Assembles a COFF archive from prepared members: the linker symbol directory, an optional
    // long-names member, then the member contents.
    void emitArchive(std::vector<std::byte>& outBytes, std::vector<ArchiveMemberBuild>& members)
    {
        // Long member names (>15 chars do not fit the inline "name/" form) live in a "//" member; an
        // affected member references them with "/<decimal-offset>".
        std::vector<std::byte> longNames;
        std::vector<Utf8>      nameField(members.size());
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
                ByteUtils::appendString(longNames, name.view());
                longNames.push_back(static_cast<std::byte>('\n'));
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

        // Linker member data: big-endian symbol count, parallel member offsets, then symbol names.
        std::vector<std::byte> linkerData;
        ByteUtils::appendBE32(linkerData, symbolCount);
        for (const ArchiveMemberBuild& member : members)
            for (size_t s = 0; s < member.symbols.size(); ++s)
                ByteUtils::appendBE32(linkerData, member.headerOffset);
        for (const ArchiveMemberBuild& member : members)
        {
            for (const Utf8& symbol : member.symbols)
            {
                ByteUtils::appendCString(linkerData, symbol.view());
            }
        }

        outBytes.clear();
        ByteUtils::appendString(outBytes, ARCHIVE_MAGIC);

        appendArchiveMember(outBytes, "/", linkerData);
        if (hasLongNames)
            appendArchiveMember(outBytes, "//", longNames);
        for (size_t i = 0; i < members.size(); ++i)
            appendArchiveMember(outBytes, nameField[i].view(), members[i].data);
    }
}

bool buildStaticArchive(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const std::vector<fs::path>& memberPaths)
{
    std::vector<ArchiveMemberBuild> members;
    members.reserve(memberPaths.size());

    for (const fs::path& path : memberPaths)
    {
        FileSystem::IoErrorInfo ioError;
        std::vector<std::byte>  bytes;
        if (FileSystem::readBinaryFile(path, bytes, ioError) != Result::Continue)
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_object_read_failed);
            outDiag.addArgument(Diagnostic::ARG_PATH, Utf8(path));
            outDiag.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::describeIoFailure(ioError));
            return false;
        }

        CoffObject object;
        if (!readCoffObject(object, outDiag, asByteSpan(bytes)))
            return false;

        ArchiveMemberBuild member;
        member.name = Utf8(path.filename());
        member.data = std::move(bytes);
        for (const CoffInputSymbol& symbol : object.definedSymbols)
            member.symbols.push_back(symbol.name);
        members.push_back(std::move(member));
    }

    emitArchive(outBytes, members);
    return true;
}

void buildImportLibrary(std::vector<std::byte>& outBytes, std::string_view dllFileName, const std::vector<Utf8>& exportNames)
{
    std::vector<ArchiveMemberBuild> members;
    members.reserve(exportNames.size());

    for (const Utf8& name : exportNames)
    {
        // A short-import record: IMPORT_OBJECT_HEADER followed by importName\0 dllName\0.
        std::vector<std::byte> data;
        ByteUtils::appendLE16(data, 0); // Sig1
        ByteUtils::appendLE16(data, IMPORT_SIG2);
        ByteUtils::appendLE16(data, 0); // Version
        ByteUtils::appendLE16(data, IMPORT_MACHINE_AMD64);
        ByteUtils::appendLE32(data, 0);                                                               // TimeDateStamp
        ByteUtils::appendLE32(data, static_cast<uint32_t>(name.size() + 1 + dllFileName.size() + 1)); // SizeOfData
        ByteUtils::appendLE16(data, 0);                                                               // OrdinalOrHint
        ByteUtils::appendLE16(data, 1 << 2);                                                          // NameType=NAME(1), Type=CODE(0)
        ByteUtils::appendCString(data, name.view());
        ByteUtils::appendCString(data, dllFileName);

        ArchiveMemberBuild member;
        member.name = Utf8(dllFileName);
        member.data = std::move(data);
        member.symbols.push_back(name);               // the thunk symbol
        member.symbols.emplace_back("__imp_" + name); // the IAT symbol
        members.push_back(std::move(member));
    }

    emitArchive(outBytes, members);
}

SWC_END_NAMESPACE();

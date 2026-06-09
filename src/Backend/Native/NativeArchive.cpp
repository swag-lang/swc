#include "pch.h"
#include "Backend/Native/NativeArchive.h"
#include "Backend/Native/NativeCoffReader.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view ARCHIVE_MAGIC      = "!<arch>\n";
    constexpr size_t           MEMBER_HEADER_SIZE = 60;
    constexpr size_t           IMPORT_HEADER_SIZE = 20;
    constexpr uint16_t         IMPORT_SIG2        = 0xFFFF;

    uint16_t readU16(ByteSpan bytes, size_t offset)
    {
        uint16_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    uint32_t readU32(ByteSpan bytes, size_t offset)
    {
        uint32_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    // The archive symbol directory stores its counts and offsets big-endian.
    uint32_t readBE32(ByteSpan bytes, size_t offset)
    {
        const auto* p = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
        return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
               (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
    }

    // Member sizes are stored as a right-padded decimal ASCII string.
    bool parseMemberSize(ByteSpan bytes, size_t headerOffset, uint32_t& outSize)
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
}

bool NativeArchive::load(std::vector<std::byte> bytes, Utf8& outError)
{
    bytes_ = std::move(bytes);
    symbolToMember_.clear();

    const ByteSpan span = asByteSpan(bytes_);
    if (span.size() < ARCHIVE_MAGIC.size() || asStringView(span.subspan(0, ARCHIVE_MAGIC.size())) != ARCHIVE_MAGIC)
    {
        outError = "not a COFF archive";
        return false;
    }

    // The first member is the linker member: a big-endian symbol -> member-offset directory.
    const size_t firstHeader = ARCHIVE_MAGIC.size();
    if (firstHeader + MEMBER_HEADER_SIZE > span.size())
    {
        outError = "truncated archive";
        return false;
    }

    uint32_t memberSize = 0;
    if (!parseMemberSize(span, firstHeader, memberSize))
    {
        outError = "malformed archive member header";
        return false;
    }

    const size_t dataOffset = firstHeader + MEMBER_HEADER_SIZE;
    if (dataOffset + memberSize > span.size() || memberSize < 4)
    {
        outError = "truncated archive linker member";
        return false;
    }

    const uint32_t symbolCount = readBE32(span, dataOffset);
    const size_t   offsetsAt   = dataOffset + 4;
    const size_t   namesAt     = offsetsAt + static_cast<size_t>(symbolCount) * 4;
    if (namesAt > dataOffset + memberSize)
    {
        outError = "malformed archive symbol index";
        return false;
    }

    size_t nameCursor = namesAt;
    const size_t memberEnd = dataOffset + memberSize;
    for (uint32_t i = 0; i < symbolCount; ++i)
    {
        if (nameCursor >= memberEnd)
        {
            outError = "malformed archive symbol names";
            return false;
        }
        const auto* nameStart = reinterpret_cast<const char*>(span.data() + nameCursor);
        size_t      nameLen   = 0;
        while (nameCursor + nameLen < memberEnd && nameStart[nameLen] != '\0')
            ++nameLen;

        const uint32_t memberOffset = readBE32(span, offsetsAt + static_cast<size_t>(i) * 4);
        symbolToMember_.emplace(Utf8{std::string_view{nameStart, nameLen}}, memberOffset);
        nameCursor += nameLen + 1;
    }

    return true;
}

uint32_t NativeArchive::memberOffsetForSymbol(const Utf8& symbol) const
{
    const auto it = symbolToMember_.find(symbol);
    return it == symbolToMember_.end() ? 0 : it->second;
}

ByteSpan NativeArchive::memberData(uint32_t headerOffset, Utf8& outError) const
{
    const ByteSpan span = asByteSpan(bytes_);
    if (headerOffset + MEMBER_HEADER_SIZE > span.size())
    {
        outError = "archive member out of range";
        return {};
    }
    uint32_t memberSize = 0;
    if (!parseMemberSize(span, headerOffset, memberSize))
    {
        outError = "malformed archive member header";
        return {};
    }
    const size_t dataOffset = headerOffset + MEMBER_HEADER_SIZE;
    if (dataOffset + memberSize > span.size())
    {
        outError = "truncated archive member";
        return {};
    }
    return span.subspan(dataOffset, memberSize);
}

bool NativeArchive::tryReadImport(uint32_t headerOffset, ArchiveImport& outImport, Utf8& outError) const
{
    const ByteSpan data = memberData(headerOffset, outError);
    if (data.empty())
        return false;
    if (data.size() < IMPORT_HEADER_SIZE)
        return false;
    if (readU16(data, 0) != 0 || readU16(data, 2) != IMPORT_SIG2)
        return false; // a regular COFF member, not a short import

    const uint16_t ordinalOrHint = readU16(data, 16);
    const uint16_t flags         = readU16(data, 18);
    const uint16_t type          = flags & 0x3;
    const uint16_t nameType      = (flags >> 2) & 0x7;

    // Strings follow the header: importName\0 dllName\0.
    const auto* strings   = reinterpret_cast<const char*>(data.data() + IMPORT_HEADER_SIZE);
    const size_t maxLen   = data.size() - IMPORT_HEADER_SIZE;
    size_t       nameLen  = 0;
    while (nameLen < maxLen && strings[nameLen] != '\0')
        ++nameLen;
    const std::string_view importName{strings, nameLen};
    size_t                  dllStart = nameLen + 1;
    size_t                  dllLen   = 0;
    while (dllStart + dllLen < maxLen && strings[dllStart + dllLen] != '\0')
        ++dllLen;
    const std::string_view dllName{strings + dllStart, dllLen};

    outImport.importName = Utf8{importName};
    outImport.dll        = Utf8{dllName};
    outImport.isData     = type == 1; // IMPORT_OBJECT_DATA
    outImport.byOrdinal  = nameType == 0; // IMPORT_OBJECT_ORDINAL
    outImport.ordinal    = ordinalOrHint;
    return true;
}

namespace
{
    void appendBE32(std::vector<std::byte>& out, uint32_t value)
    {
        out.push_back(static_cast<std::byte>((value >> 24) & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 16) & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 8) & 0xFF));
        out.push_back(static_cast<std::byte>(value & 0xFF));
    }

    void appendString(std::vector<std::byte>& out, std::string_view text)
    {
        for (const char c : text)
            out.push_back(static_cast<std::byte>(c));
    }

    // Writes a 60-byte archive member header. Numeric fields are left-justified, space-padded.
    void appendMemberHeader(std::vector<std::byte>& out, std::string_view name, uint32_t dataSize)
    {
        std::string header(60, ' ');
        const auto place = [&](std::string_view value, size_t offset, size_t width) {
            std::memcpy(header.data() + offset, value.data(), std::min(value.size(), width));
        };
        place(name, 0, 16);
        place("0", 16, 12);  // date
        place("0", 28, 6);   // uid
        place("0", 34, 6);   // gid
        place("0", 40, 8);   // mode
        place(std::to_string(dataSize), 48, 10);
        header[58] = '\x60';
        header[59] = '\n';
        appendString(out, header);
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
    void emitArchive(std::vector<ArchiveMemberBuild>& members, std::vector<std::byte>& outBytes)
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
                appendString(longNames, name.view());
                longNames.push_back(static_cast<std::byte>('\n'));
            }
        }

        const auto aligned = [](size_t size) { return size + (size & 1); };

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
        cursor += 60 + aligned(linkerDataSize);
        const bool hasLongNames = !longNames.empty();
        if (hasLongNames)
            cursor += 60 + aligned(longNames.size());
        for (ArchiveMemberBuild& member : members)
        {
            member.headerOffset = static_cast<uint32_t>(cursor);
            cursor += 60 + aligned(member.data.size());
        }

        // Linker member data: big-endian symbol count, parallel member offsets, then symbol names.
        std::vector<std::byte> linkerData;
        appendBE32(linkerData, symbolCount);
        for (const ArchiveMemberBuild& member : members)
            for (size_t s = 0; s < member.symbols.size(); ++s)
                appendBE32(linkerData, member.headerOffset);
        for (const ArchiveMemberBuild& member : members)
        {
            for (const Utf8& symbol : member.symbols)
            {
                appendString(linkerData, symbol.view());
                linkerData.push_back(std::byte{0});
            }
        }

        outBytes.clear();
        appendString(outBytes, ARCHIVE_MAGIC);

        const auto appendMember = [&](std::string_view name, const std::vector<std::byte>& data) {
            appendMemberHeader(outBytes, name, static_cast<uint32_t>(data.size()));
            outBytes.insert(outBytes.end(), data.begin(), data.end());
            if (data.size() & 1)
                outBytes.push_back(static_cast<std::byte>('\n'));
        };

        appendMember("/", linkerData);
        if (hasLongNames)
            appendMember("//", longNames);
        for (size_t i = 0; i < members.size(); ++i)
            appendMember(nameField[i].view(), members[i].data);
    }
}

bool buildStaticArchive(const std::vector<fs::path>& memberPaths, std::vector<std::byte>& outBytes, Utf8& outError)
{
    std::vector<ArchiveMemberBuild> members;
    members.reserve(memberPaths.size());

    for (const fs::path& path : memberPaths)
    {
        FileSystem::IoErrorInfo ioError;
        std::vector<std::byte>  bytes;
        if (FileSystem::readBinaryFile(path, bytes, ioError) != Result::Continue)
        {
            outError = std::format("cannot read object '{}'", Utf8(path).view());
            return false;
        }

        CoffObject object;
        Utf8       error;
        if (!readCoffObject(asByteSpan(bytes), object, error))
        {
            outError = error;
            return false;
        }

        ArchiveMemberBuild member;
        member.name = Utf8(path.filename());
        member.data = std::move(bytes);
        for (const CoffInputSymbol& symbol : object.definedSymbols)
            member.symbols.push_back(symbol.name);
        members.push_back(std::move(member));
    }

    emitArchive(members, outBytes);
    return true;
}

bool buildImportLibrary(std::string_view dllFileName, const std::vector<Utf8>& exportNames, std::vector<std::byte>& outBytes, Utf8& outError)
{
    SWC_UNUSED(outError);

    std::vector<ArchiveMemberBuild> members;
    members.reserve(exportNames.size());

    for (const Utf8& name : exportNames)
    {
        // A short-import record: IMPORT_OBJECT_HEADER followed by importName\0 dllName\0.
        std::vector<std::byte> data;
        const auto             u16 = [&](uint16_t v) { data.push_back(static_cast<std::byte>(v & 0xFF)); data.push_back(static_cast<std::byte>((v >> 8) & 0xFF)); };
        const auto             u32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) data.push_back(static_cast<std::byte>((v >> (i * 8)) & 0xFF)); };
        u16(0);                       // Sig1
        u16(0xFFFF);                  // Sig2
        u16(0);                       // Version
        u16(0x8664);                  // Machine = AMD64
        u32(0);                       // TimeDateStamp
        u32(static_cast<uint32_t>(name.size() + 1 + dllFileName.size() + 1)); // SizeOfData
        u16(0);                       // OrdinalOrHint
        u16(static_cast<uint16_t>(1 << 2)); // NameType=NAME(1), Type=CODE(0)
        appendString(data, name.view());
        data.push_back(std::byte{0});
        appendString(data, dllFileName);
        data.push_back(std::byte{0});

        ArchiveMemberBuild member;
        member.name = Utf8(dllFileName);
        member.data = std::move(data);
        member.symbols.push_back(name);          // the thunk symbol
        member.symbols.push_back("__imp_" + name); // the IAT symbol
        members.push_back(std::move(member));
    }

    emitArchive(members, outBytes);
    return true;
}

SWC_END_NAMESPACE();

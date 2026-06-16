#include "pch.h"
#include "Backend/Linker/PdbWriter.h"
#include "Main/Version.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

// ReSharper disable IdentifierTypo
// ReSharper disable CommentTypo

namespace
{
    using ByteUtils::appendLe16;
    using ByteUtils::appendLe32;

    constexpr uint32_t K_BLOCK_SIZE = 4096;

    // ---- CodeView / PDB constants -------------------------------------------------------------------

    constexpr uint32_t K_CV_SIGNATURE_C13 = 4;

    constexpr uint16_t K_S_END        = 0x0006;
    constexpr uint16_t K_S_FRAMEPROC  = 0x1012;
    constexpr uint16_t K_S_OBJNAME    = 0x1101;
    constexpr uint16_t K_S_COMPILE3   = 0x113C;
    constexpr uint16_t K_S_GPROC32    = 0x1110;
    constexpr uint16_t K_S_PUB32      = 0x110E;
    constexpr uint16_t K_S_LDATA32    = 0x110C;
    constexpr uint16_t K_S_GDATA32    = 0x110D;
    constexpr uint16_t K_S_UDT        = 0x1108;
    constexpr uint16_t K_S_REGREL32   = 0x1111;
    constexpr uint16_t K_S_PROCREF    = 0x1125;
    constexpr uint16_t K_S_BUILDINFO  = 0x114C;

    constexpr uint16_t K_LF_BUILDINFO = 0x1603;
    constexpr uint16_t K_LF_STRING_ID = 0x1605;

    constexpr uint32_t K_DEBUG_S_SYMBOLS    = 0xF1;
    constexpr uint32_t K_DEBUG_S_LINES      = 0xF2;
    constexpr uint32_t K_DEBUG_S_FILECHKSMS = 0xF4;

    constexpr uint32_t K_CV_LINE_STATEMENT = 0x80000000u;

    constexpr uint16_t K_CV_CFL_AMD64 = 0x00D0;
    constexpr uint32_t K_CV_CFL_CXX   = 0x01; // S_COMPILE3 language byte: C++ (matches the COFF object writer)

    constexpr uint32_t K_PUB_FLAG_FUNCTION = 0x00000002u;

    constexpr uint32_t K_IPHR_HASH = 4096;

    // PE section characteristic bits (avoid pulling in windows.h here).
    constexpr uint32_t K_SCN_MEM_EXECUTE = 0x20000000u;
    constexpr uint32_t K_SCN_MEM_READ    = 0x40000000u;
    constexpr uint32_t K_SCN_MEM_WRITE   = 0x80000000u;

    // Fixed stream indices. The first four are mandated by the PDB format; the rest are ours.
    enum StreamIndex : uint16_t
    {
        STREAM_OLD_DIRECTORY = 0,
        STREAM_PDB_INFO      = 1,
        STREAM_TPI           = 2,
        STREAM_DBI           = 3,
        STREAM_IPI           = 4,
        STREAM_NAMES         = 5,
        STREAM_MODULE        = 6,
        STREAM_GLOBALS       = 7,
        STREAM_PUBLICS       = 8,
        STREAM_SYM_RECORDS   = 9,
        STREAM_SECTION_HDR   = 10,
        STREAM_TPI_HASH      = 11,
        STREAM_IPI_HASH      = 12,
        STREAM_COUNT         = 13,
    };

    constexpr uint32_t K_TPI_HASH_BUCKETS = 0x3ffff;

    using Bytes = std::vector<std::byte>;

    void appendBytes(Bytes& out, const Bytes& src) { out.insert(out.end(), src.begin(), src.end()); }

    void appendCString(Bytes& out, std::string_view text)
    {
        for (const char ch : text)
            out.push_back(static_cast<std::byte>(ch));
        out.push_back(std::byte{0});
    }

    void alignTo4(Bytes& out, const std::byte pad = std::byte{0})
    {
        while (out.size() % 4 != 0)
            out.push_back(pad);
    }

    // Frames a CodeView symbol record: u16 length (kind+payload), u16 kind, payload, padded so the whole
    // record is a multiple of 4 bytes. Returns the stream offset at which the record was written.
    uint32_t appendSymbol(Bytes& out, const uint16_t kind, const Bytes& payload)
    {
        const auto offset = static_cast<uint32_t>(out.size());

        Bytes body;
        appendLe16(body, kind);
        appendBytes(body, payload);
        while ((body.size() + 2) % 4 != 0)
            body.push_back(std::byte{0});

        appendLe16(out, static_cast<uint16_t>(body.size()));
        appendBytes(out, body);
        return offset;
    }

    uint32_t appendTypeRecord(Bytes& out, const uint16_t kind, const Bytes& payload)
    {
        const auto offset = static_cast<uint32_t>(out.size());

        Bytes body;
        appendLe16(body, kind);
        appendBytes(body, payload);

        const uint32_t rawRecordSize = static_cast<uint32_t>(body.size() + sizeof(uint16_t));
        const uint32_t padBytes      = Math::alignUpU32(rawRecordSize, 4) - rawRecordSize;
        for (uint32_t i = padBytes; i > 0; --i)
            body.push_back(static_cast<std::byte>(0xF0u + i));

        appendLe16(out, static_cast<uint16_t>(body.size()));
        appendBytes(out, body);
        return offset;
    }

    uint32_t appendStringIdRecord(Bytes& out, uint32_t& nextTypeIndex, const Utf8& value)
    {
        Bytes payload;
        appendLe32(payload, 0);
        appendCString(payload, value.view());
        appendTypeRecord(out, K_LF_STRING_ID, payload);
        return nextTypeIndex++;
    }

    uint32_t appendBuildInfoRecord(Bytes& out, uint32_t& nextTypeIndex, const std::array<uint32_t, 5>& items)
    {
        Bytes payload;
        appendLe16(payload, static_cast<uint16_t>(items.size()));
        for (const uint32_t item : items)
            appendLe32(payload, item);
        appendTypeRecord(out, K_LF_BUILDINFO, payload);
        return nextTypeIndex++;
    }

    Utf8 pdbPathString(const fs::path& path)
    {
        fs::path normalized = path.lexically_normal();
        normalized.make_preferred();
        return {normalized.string()};
    }

    Utf8 buildInfoDirectory(const Utf8& sourcePath)
    {
        if (sourcePath.empty())
            return {};
        return pdbPathString(fs::path(sourcePath.c_str()).parent_path());
    }

    Utf8 buildInfoFileName(const Utf8& sourcePath)
    {
        if (sourcePath.empty())
            return {};
        return {fs::path(sourcePath.c_str()).filename().string()};
    }

    // ---- Hashing ------------------------------------------------------------------------------------

    uint32_t loadLe32(const char* p) { return ByteUtils::readLe32(asByteSpan(std::string_view{p, 4}), 0); }

    // CodeView V1 string hash, used by the /names table and the GSI/public symbol hashes.
    uint32_t hashStringV1(std::string_view str)
    {
        uint32_t    result    = 0;
        const auto* data      = str.data();
        const size_t size     = str.size();
        const size_t numLongs = size / 4;
        for (size_t i = 0; i < numLongs; ++i)
            result ^= loadLe32(data + i * 4);

        const char*  rem     = data + numLongs * 4;
        const size_t remSize = size % 4;
        if (remSize >= 2)
        {
            const uint16_t v = static_cast<uint16_t>(static_cast<uint8_t>(rem[0]) | (static_cast<uint8_t>(rem[1]) << 8));
            result ^= v;
            if (remSize == 3)
                result ^= static_cast<uint32_t>(static_cast<uint8_t>(rem[2])) << 16;
        }
        else if (remSize == 1)
        {
            result ^= static_cast<uint8_t>(rem[0]);
        }

        result |= 0x20202020u;
        result ^= (result >> 11);
        result ^= (result >> 16);
        return result;
    }

    // ---- MSF container ------------------------------------------------------------------------------

    // Lays out a set of streams into the MSF (multi-stream file) block structure and serialises the whole
    // file. Stream contents are provided verbatim; this only deals with block allocation and the directory.
    void buildMsf(Bytes& outFile, const std::vector<Bytes>& streams)
    {
        uint32_t nextBlock = 3; // 0 = superblock, 1/2 = the two free-page maps
        const auto allocBlock = [&]() {
            while ((nextBlock % K_BLOCK_SIZE) == 1 || (nextBlock % K_BLOCK_SIZE) == 2)
                ++nextBlock;
            return nextBlock++;
        };

        std::vector<std::vector<uint32_t>> streamBlocks(streams.size());
        for (size_t i = 0; i < streams.size(); ++i)
        {
            const uint32_t numBlocks = Math::alignUpU32(static_cast<uint32_t>(streams[i].size()), K_BLOCK_SIZE) / K_BLOCK_SIZE;
            streamBlocks[i].reserve(numBlocks);
            for (uint32_t b = 0; b < numBlocks; ++b)
                streamBlocks[i].push_back(allocBlock());
        }

        // The stream directory: stream count, each stream's byte size, then every stream's block list.
        Bytes directory;
        appendLe32(directory, static_cast<uint32_t>(streams.size()));
        for (const auto& stream : streams)
            appendLe32(directory, static_cast<uint32_t>(stream.size()));
        for (const auto& blocks : streamBlocks)
            for (const uint32_t block : blocks)
                appendLe32(directory, block);

        const uint32_t directoryBytes  = static_cast<uint32_t>(directory.size());
        const uint32_t directoryBlocks = Math::alignUpU32(directoryBytes, K_BLOCK_SIZE) / K_BLOCK_SIZE;
        std::vector<uint32_t> dirBlockList;
        dirBlockList.reserve(directoryBlocks);
        for (uint32_t b = 0; b < directoryBlocks; ++b)
            dirBlockList.push_back(allocBlock());

        // The block map: one block holding the directory's block numbers.
        SWC_ASSERT(directoryBlocks <= K_BLOCK_SIZE / 4);
        const uint32_t blockMapAddr = allocBlock();

        const uint32_t totalBlocks = nextBlock;
        outFile.assign(static_cast<size_t>(totalBlocks) * K_BLOCK_SIZE, std::byte{0});

        const auto writeAt = [&](uint32_t block, const std::byte* src, size_t size) {
            std::memcpy(outFile.data() + static_cast<size_t>(block) * K_BLOCK_SIZE, src, size);
        };
        const auto writeStreamInto = [&](const std::vector<uint32_t>& blocks, const Bytes& data) {
            size_t pos = 0;
            for (const uint32_t block : blocks)
            {
                const size_t chunk = std::min<size_t>(K_BLOCK_SIZE, data.size() - pos);
                writeAt(block, data.data() + pos, chunk);
                pos += chunk;
            }
        };

        for (size_t i = 0; i < streams.size(); ++i)
            writeStreamInto(streamBlocks[i], streams[i]);
        writeStreamInto(dirBlockList, directory);

        Bytes blockMap;
        for (const uint32_t block : dirBlockList)
            appendLe32(blockMap, block);
        writeAt(blockMapAddr, blockMap.data(), blockMap.size());

        // Superblock.
        Bytes super;
        static constexpr char K_MAGIC[] = "Microsoft C/C++ MSF 7.00\r\n\x1A" "DS\0\0";
        for (size_t i = 0; i < 32; ++i)
            super.push_back(static_cast<std::byte>(K_MAGIC[i]));
        appendLe32(super, K_BLOCK_SIZE);   // BlockSize
        appendLe32(super, 1);              // FreeBlockMapBlock (use FPM #1)
        appendLe32(super, totalBlocks);    // NumBlocks
        appendLe32(super, directoryBytes); // NumDirectoryBytes
        appendLe32(super, 0);              // Unknown
        appendLe32(super, blockMapAddr);   // BlockMapAddr
        writeAt(0, super.data(), super.size());

        // Free page map: a 1-bit-per-block bitmap (1 = free). Mark every block we allocated as used (0).
        Bytes fpm(K_BLOCK_SIZE, std::byte{0xFF});
        for (uint32_t b = 0; b < totalBlocks; ++b)
        {
            const uint32_t byteIdx = b / 8;
            const uint32_t bitIdx  = b % 8;
            fpm[byteIdx] &= static_cast<std::byte>(~(1u << bitIdx));
        }
        writeAt(1, fpm.data(), fpm.size());
        const Bytes fpm2(K_BLOCK_SIZE, std::byte{0xFF});
        writeAt(2, fpm2.data(), fpm2.size());
    }

    // ---- /names string table ------------------------------------------------------------------------

    struct NamesTable
    {
        Bytes                              buffer{std::byte{0}}; // leading empty string at offset 0
        std::unordered_map<Utf8, uint32_t> offsets;
        uint32_t                           count = 0;

        uint32_t insert(const Utf8& value)
        {
            if (value.empty())
                return 0;
            if (const auto it = offsets.find(value); it != offsets.end())
                return it->second;
            const auto offset = static_cast<uint32_t>(buffer.size());
            offsets.emplace(value, offset);
            for (const char ch : value.view())
                buffer.push_back(static_cast<std::byte>(ch));
            buffer.push_back(std::byte{0});
            ++count;
            return offset;
        }

        Bytes serialize() const
        {
            Bytes out;
            appendLe32(out, 0xEFFEEFFEu); // Signature
            appendLe32(out, 1);           // HashVersion (V1)
            appendLe32(out, static_cast<uint32_t>(buffer.size()));
            appendBytes(out, buffer);

            const uint32_t bucketCount = std::max<uint32_t>(1, count * 2 + 1);
            std::vector<uint32_t> buckets(bucketCount, 0);
            for (const auto& [name, offset] : offsets)
            {
                uint32_t b = hashStringV1(name.view()) % bucketCount;
                while (buckets[b] != 0)
                    b = (b + 1) % bucketCount;
                buckets[b] = offset;
            }

            appendLe32(out, bucketCount);
            for (const uint32_t b : buckets)
                appendLe32(out, b);
            appendLe32(out, count);
            return out;
        }
    };

    // ---- GSI / public symbol hash -------------------------------------------------------------------

    struct HashedSym
    {
        uint32_t recordOffset = 0;
        Utf8     name;
    };

    struct ProcRefSym
    {
        Utf8     name;
        uint32_t moduleSymOffset = 0;
        uint16_t moduleIndex     = 0;
    };

    struct PdbModuleBuild
    {
        Utf8                                  name;
        uint32_t                              primaryFileIndex = std::numeric_limits<uint32_t>::max();
        std::vector<uint32_t>                 fileIndices;
        std::vector<const LinkDebugFunction*> functions;
        Bytes                                 stream;
        uint32_t                              symByteSize = 0;
        uint32_t                              c13ByteSize = 0;
        uint16_t                              streamIndex = 0;
        uint16_t                              codeSegment = 1;
        uint32_t                              codeOffset  = 0;
        uint32_t                              codeSize    = 0;
        uint32_t                              codeChars   = 0;
        uint32_t                              buildInfoIndex = 0;
    };

    struct PdbSectionContribBuild
    {
        uint16_t segment         = 0;
        uint32_t offset          = 0;
        uint32_t size            = 0;
        uint32_t characteristics = 0;
        uint16_t moduleIndex     = 0;
    };

    int gsiRecordCmp(std::string_view a, std::string_view b)
    {
        if (a.size() != b.size())
            return static_cast<int>(a.size()) - static_cast<int>(b.size());
        for (size_t i = 0; i < a.size(); ++i)
        {
            const auto la = static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(a[i])));
            const auto lb = static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(b[i])));
            if (la != lb)
                return static_cast<int>(la) - static_cast<int>(lb);
        }
        return 0;
    }

    // Serialises the global-symbol-index hash table over the given records (referenced by their byte
    // offset in the symbol record stream). Shared by the globals stream and the publics stream.
    Bytes buildGsiHash(std::vector<HashedSym> syms)
    {
        std::array<std::vector<HashedSym>, K_IPHR_HASH> buckets;
        for (auto& sym : syms)
        {
            const uint32_t bucket = hashStringV1(sym.name.view()) % K_IPHR_HASH;
            buckets[bucket].push_back(std::move(sym));
        }
        for (auto& bucket : buckets)
            std::ranges::sort(bucket, [](const HashedSym& a, const HashedSym& b) { return gsiRecordCmp(a.name.view(), b.name.view()) < 0; });

        Bytes records;
        Bytes bucketSection;

        // Bitmap of present buckets: (IPHR_HASH/32 + 1) words.
        constexpr uint32_t bitmapWords = K_IPHR_HASH / 32 + 1;
        std::array<uint32_t, bitmapWords> bitmap{};

        Bytes bucketOffsets;
        uint32_t recordsBefore = 0;
        for (uint32_t b = 0; b < K_IPHR_HASH; ++b)
        {
            if (buckets[b].empty())
                continue;
            bitmap[b / 32] |= (1u << (b % 32));
            appendLe32(bucketOffsets, recordsBefore * 12); // 12 = sizeof in-memory HRFile record
            for (const HashedSym& sym : buckets[b])
            {
                appendLe32(records, sym.recordOffset + 1);
                appendLe32(records, 1); // reference count
                ++recordsBefore;
            }
        }

        for (const uint32_t word : bitmap)
            appendLe32(bucketSection, word);
        appendBytes(bucketSection, bucketOffsets);

        Bytes out;
        appendLe32(out, 0xFFFFFFFFu);              // VerSignature
        appendLe32(out, 0xeffe0000u + 19990810u);  // VerHdr
        appendLe32(out, static_cast<uint32_t>(records.size()));
        appendLe32(out, static_cast<uint32_t>(bucketSection.size()));
        appendBytes(out, records);
        appendBytes(out, bucketSection);
        return out;
    }

    // ---- TPI / IPI ----------------------------------------------------------------------------------

    // Builds a TPI/IPI stream. When records is non-empty a hash stream is required (otherwise debuggers
    // fault resolving a type index); its bytes are returned in outHash and referenced by hashStreamIndex.
    Bytes buildTpiStream(const Bytes& records, const uint32_t indexEnd, const uint16_t hashStreamIndex, Bytes& outHash)
    {
        outHash.clear();

        // Walk the records to recover each record's offset (for the hash stream's index->offset map).
        std::vector<uint32_t> recordOffsets;
        for (size_t pos = 0; pos < records.size();)
        {
            recordOffsets.push_back(static_cast<uint32_t>(pos));
            const uint16_t len = static_cast<uint16_t>(static_cast<uint8_t>(records[pos]) | (static_cast<uint8_t>(records[pos + 1]) << 8));
            pos += 2u + len;
        }

        const bool     hasHash    = !records.empty();
        const uint32_t numRecords = static_cast<uint32_t>(recordOffsets.size());

        if (hasHash)
        {
            // Hash value buffer: one bucket index per record (content hash; sufficient for index-based
            // type resolution, which is what local/global type display uses).
            for (uint32_t i = 0; i < numRecords; ++i)
            {
                const uint32_t begin = recordOffsets[i];
                const uint32_t end   = i + 1 < numRecords ? recordOffsets[i + 1] : static_cast<uint32_t>(records.size());
                uint32_t       hash  = 2166136261u;
                for (uint32_t b = begin; b < end; ++b)
                    hash = (hash ^ static_cast<uint8_t>(records[b])) * 16777619u;
                appendLe32(outHash, hash % K_TPI_HASH_BUCKETS);
            }
            // Index-offset map: (type index, record offset) for every record.
            for (uint32_t i = 0; i < numRecords; ++i)
            {
                appendLe32(outHash, 0x1000 + i);
                appendLe32(outHash, recordOffsets[i]);
            }
        }

        const uint32_t hashValuesLen = hasHash ? numRecords * 4 : 0;
        const uint32_t indexOffLen   = hasHash ? numRecords * 8 : 0;

        Bytes out;
        appendLe32(out, 20040203);                              // Version
        appendLe32(out, 0x38);                                  // HeaderSize
        appendLe32(out, 0x1000);                                // TypeIndexBegin
        appendLe32(out, std::max<uint32_t>(0x1000, indexEnd));  // TypeIndexEnd
        appendLe32(out, static_cast<uint32_t>(records.size())); // TypeRecordBytes
        appendLe16(out, hasHash ? hashStreamIndex : 0xFFFF);    // HashStreamIndex
        appendLe16(out, 0xFFFF);                                // HashAuxStreamIndex
        appendLe32(out, 4);                                     // HashKeySize
        appendLe32(out, K_TPI_HASH_BUCKETS);                    // NumHashBuckets
        appendLe32(out, 0);                                     // HashValueBufferOffset
        appendLe32(out, hashValuesLen);                         // HashValueBufferLength
        appendLe32(out, hashValuesLen);                         // IndexOffsetBufferOffset
        appendLe32(out, indexOffLen);                           // IndexOffsetBufferLength
        appendLe32(out, hashValuesLen + indexOffLen);           // HashAdjBufferOffset
        appendLe32(out, 0);                                     // HashAdjBufferLength
        appendBytes(out, records);
        return out;
    }

    // ---- Section contribution / section header helpers ----------------------------------------------

    void appendSectionContribEntry(Bytes& out, const uint16_t isect, const uint32_t off, const uint32_t size, const uint32_t characteristics, const uint16_t moduleIndex = 0)
    {
        appendLe16(out, isect);
        appendLe16(out, 0);            // padding
        appendLe32(out, off);
        appendLe32(out, size);
        appendLe32(out, characteristics);
        appendLe16(out, moduleIndex);
        appendLe16(out, 0);            // padding
        appendLe32(out, 0);            // data CRC
        appendLe32(out, 0);            // reloc CRC
    }
}

// =================================================================================================

void PdbWriter::build(std::vector<std::byte>&             outBytes,
                      std::array<uint8_t, 16>&            outGuid,
                      uint32_t&                           outAge,
                      uint32_t&                           outSignature,
                      const LinkDebugInfo&                debugInfo,
                      const std::vector<PdbSectionInfo>&  sections,
                      const SymbolResolver&               resolver,
                      const Utf8&                         moduleName,
                      const Utf8&                         pdbPath)
{
    outAge = 1;

    // Deterministic GUID/signature derived from the module's debug content so rebuilds are stable.
    uint64_t h0 = 0xcbf29ce484222325ull;
    uint64_t h1 = 0x100000001b3ull;
    const auto mix = [&](std::string_view text) {
        for (const char ch : text)
        {
            h0 = (h0 ^ static_cast<uint8_t>(ch)) * 0x100000001b3ull;
            h1 = (h1 ^ static_cast<uint8_t>(ch)) * 0xcbf29ce484222325ull + 0x9e3779b97f4a7c15ull;
        }
    };
    mix(moduleName.view());
    for (const LinkDebugFunction& fn : debugInfo.functions)
    {
        mix(fn.symbolName.view());
        h0 += fn.codeSize;
    }
    std::memcpy(outGuid.data(), &h0, 8);
    std::memcpy(outGuid.data() + 8, &h1, 8);
    outSignature = static_cast<uint32_t>(h0 ^ (h0 >> 32));

    // ---- /names ---------------------------------------------------------------------------------
    NamesTable names;
    std::vector<uint32_t> fileNameOffsets(debugInfo.files.size());
    for (size_t i = 0; i < debugInfo.files.size(); ++i)
        fileNameOffsets[i] = names.insert(debugInfo.files[i].path);

    // ---- Symbol record stream (publics + globals referenced by GSI/PSI) -------------------------
    Bytes                    symRecords;
    std::vector<HashedSym>   publicSyms;
    std::vector<HashedSym>   globalSyms;
    std::vector<std::pair<uint32_t, PdbSymbolAddress>> publicAddrs; // record offset + address (for the addr map)

    for (const LinkDebugFunction& fn : debugInfo.functions)
    {
        const PdbSymbolAddress addr = resolver.resolve(fn.symbolName);
        if (!addr.found)
            continue;

        Bytes payload;
        appendLe32(payload, K_PUB_FLAG_FUNCTION);
        appendLe32(payload, addr.offset);
        appendLe16(payload, addr.segment);
        appendCString(payload, fn.symbolName.view());
        const uint32_t recordOffset = appendSymbol(symRecords, K_S_PUB32, payload);

        publicSyms.push_back({recordOffset, fn.symbolName});
        publicAddrs.emplace_back(recordOffset, addr);
    }

    for (const LinkDebugGlobal& g : debugInfo.globals)
    {
        const PdbSymbolAddress addr = resolver.resolveSection(g.sectionName, g.sectionOffset);
        if (!addr.found)
            continue;

        Bytes payload;
        appendLe32(payload, g.typeIndex);
        appendLe32(payload, addr.offset);
        appendLe16(payload, addr.segment);
        appendCString(payload, g.displayName.view());
        const uint32_t recordOffset = appendSymbol(symRecords, g.isPublic ? K_S_GDATA32 : K_S_LDATA32, payload);
        globalSyms.push_back({recordOffset, g.displayName});
    }

    for (const LinkDebugUdt& udt : debugInfo.udts)
    {
        Bytes payload;
        appendLe32(payload, udt.typeIndex);
        appendCString(payload, udt.name.view());
        const uint32_t recordOffset = appendSymbol(symRecords, K_S_UDT, payload);
        globalSyms.push_back({recordOffset, udt.name});
    }

    // ---- Module streams -------------------------------------------------------------------------
    // Model each PDB compiland as the object file the backend split functions into (the codegen job),
    // named after that .obj. This mirrors the layout an external link.exe PDB has -- Visual Studio
    // expects per-object compilands -- while every function still carries its own source-file line table.
    std::vector<PdbModuleBuild> modules;
    std::unordered_map<uint32_t, size_t> moduleOfObj;
    const auto addFileToModule = [](PdbModuleBuild& module, const uint32_t fileIndex) {
        if (fileIndex == std::numeric_limits<uint32_t>::max())
            return;
        for (const uint32_t existing : module.fileIndices)
            if (existing == fileIndex)
                return;
        module.fileIndices.push_back(fileIndex);
    };

    for (const LinkDebugFunction& fn : debugInfo.functions)
    {
        const PdbSymbolAddress addr = resolver.resolve(fn.symbolName);
        if (!addr.found)
            continue;

        uint32_t primaryFile = fn.primaryFileIndex;
        if (primaryFile >= debugInfo.files.size() && !fn.lineBlocks.empty() && fn.lineBlocks.front().fileIndex < debugInfo.files.size())
            primaryFile = fn.lineBlocks.front().fileIndex;

        size_t     moduleIndex;
        const auto it = moduleOfObj.find(fn.objIndex);
        if (it != moduleOfObj.end())
        {
            moduleIndex = it->second;
        }
        else
        {
            moduleIndex = modules.size();
            moduleOfObj.emplace(fn.objIndex, moduleIndex);
            PdbModuleBuild module;
            module.primaryFileIndex = primaryFile;
            module.name             = fn.objIndex < debugInfo.objectNames.size() ? debugInfo.objectNames[fn.objIndex] : moduleName;
            modules.push_back(std::move(module));
        }

        PdbModuleBuild& module = modules[moduleIndex];
        module.functions.push_back(&fn);
        addFileToModule(module, primaryFile);
        for (const LinkDebugLineBlock& block : fn.lineBlocks)
            if (block.fileIndex < debugInfo.files.size())
                addFileToModule(module, block.fileIndex);
    }

    uint16_t textSegment = 1;
    uint32_t textChars   = 0;
    for (size_t i = 0; i < sections.size(); ++i)
    {
        if (sections[i].name == ".text")
        {
            textSegment = static_cast<uint16_t>(i + 1);
            textChars   = sections[i].characteristics;
            break;
        }
    }

    constexpr uint32_t symBase = sizeof(uint32_t);
    std::vector<ProcRefSym> procRefs;
    const uint16_t          moduleStreamStart = STREAM_NAMES + 1;
    for (PdbModuleBuild& module : modules)
    {
        module.codeSegment = textSegment;
        module.codeChars   = textChars;

        uint32_t minCodeOffset = std::numeric_limits<uint32_t>::max();
        uint32_t maxCodeOffset = 0;
        for (const LinkDebugFunction* fn : module.functions)
        {
            const PdbSymbolAddress addr = resolver.resolve(fn->symbolName);
            if (!addr.found)
                continue;

            minCodeOffset = std::min(minCodeOffset, addr.offset);
            maxCodeOffset = std::max(maxCodeOffset, addr.offset + fn->codeSize);
        }

        if (minCodeOffset != std::numeric_limits<uint32_t>::max())
        {
            module.codeOffset = minCodeOffset;
            module.codeSize   = maxCodeOffset - minCodeOffset;
        }
    }

    std::ranges::sort(modules, [](const PdbModuleBuild& a, const PdbModuleBuild& b) {
        if (a.codeSegment != b.codeSegment)
            return a.codeSegment < b.codeSegment;
        if (a.codeOffset != b.codeOffset)
            return a.codeOffset < b.codeOffset;
        if (a.codeSize != b.codeSize)
            return a.codeSize < b.codeSize;
        return a.name < b.name;
    });

    Bytes    ipiRecords  = debugInfo.ipiRecords;
    uint32_t ipiIndexEnd = std::max<uint32_t>(0x1000, debugInfo.ipiIndexEnd);
    for (PdbModuleBuild& module : modules)
    {
        const Utf8 primarySource = module.primaryFileIndex < debugInfo.files.size() ? debugInfo.files[module.primaryFileIndex].path : module.name;
        const uint32_t currentDirId  = appendStringIdRecord(ipiRecords, ipiIndexEnd, buildInfoDirectory(primarySource));
        const uint32_t buildToolId   = appendStringIdRecord(ipiRecords, ipiIndexEnd, {});
        const uint32_t sourceFileId  = appendStringIdRecord(ipiRecords, ipiIndexEnd, buildInfoFileName(primarySource));
        const uint32_t pdbFileId     = appendStringIdRecord(ipiRecords, ipiIndexEnd, pdbPath);
        const uint32_t commandLineId = appendStringIdRecord(ipiRecords, ipiIndexEnd, {});
        module.buildInfoIndex        = appendBuildInfoRecord(ipiRecords, ipiIndexEnd, {currentDirId, buildToolId, sourceFileId, pdbFileId, commandLineId});
    }

    for (size_t i = 0; i < modules.size(); ++i)
    {
        PdbModuleBuild& module = modules[i];
        module.streamIndex     = static_cast<uint16_t>(moduleStreamStart + i);

        Bytes moduleSymbols;
        {
            Bytes payload;
            appendLe32(payload, 0); // signature
            appendCString(payload, module.name.view());
            appendSymbol(moduleSymbols, K_S_OBJNAME, payload);
        }
        {
            // Keep this record byte-for-byte consistent with the COFF object writer's S_COMPILE3
            // (DebugInfoCodeView::appendCompileRecord): language C++, a non-zero producer version, and
            // the "swc X.Y.Z" version string. Visual Studio keys source/symbol/JMC behaviour off this
            // record, and a divergent one (language C, version 0) made VS treat the image as external.
            constexpr auto major   = static_cast<uint16_t>(std::max<uint32_t>(1, SWC_VERSION));
            constexpr auto minor   = static_cast<uint16_t>(SWC_REVISION);
            constexpr auto build   = static_cast<uint16_t>(SWC_BUILD_NUM);
            const Utf8     version = debugInfo.compilerVersion.empty() ? Utf8(std::format("swc {}.{}.{}", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM)) : debugInfo.compilerVersion;

            Bytes payload;
            appendLe32(payload, K_CV_CFL_CXX);   // flags (low byte = language: C++)
            appendLe16(payload, K_CV_CFL_AMD64); // machine
            appendLe16(payload, major);          // frontend major (producer/compiler version)
            appendLe16(payload, minor);          // frontend minor
            appendLe16(payload, build);          // frontend build
            appendLe16(payload, 0);              // frontend QFE
            appendLe16(payload, major);          // backend major
            appendLe16(payload, minor);          // backend minor
            appendLe16(payload, build);          // backend build
            appendLe16(payload, 0);              // backend QFE
            appendCString(payload, version.view());
            appendSymbol(moduleSymbols, K_S_COMPILE3, payload);
        }

        for (const LinkDebugFunction* fn : module.functions)
        {
            const PdbSymbolAddress addr = resolver.resolve(fn->symbolName);
            if (!addr.found)
                continue;

            const std::string_view functionName = fn->displayName.empty() ? fn->symbolName.view() : fn->displayName.view();

            Bytes payload;
            appendLe32(payload, 0); // parent
            appendLe32(payload, 0); // end (placeholder)
            appendLe32(payload, 0); // next
            appendLe32(payload, fn->codeSize);
            appendLe32(payload, 0); // dbg start
            appendLe32(payload, fn->codeSize); // dbg end
            appendLe32(payload, fn->procTypeIndex);
            appendLe32(payload, addr.offset);
            appendLe16(payload, addr.segment);
            payload.push_back(std::byte{0}); // flags
            appendCString(payload, functionName);
            const uint32_t procOffset = appendSymbol(moduleSymbols, K_S_GPROC32, payload);
            procRefs.push_back({Utf8(functionName), symBase + procOffset, static_cast<uint16_t>(i)});
            const uint32_t endFieldOffset = procOffset + 2 + 2 + 4;

            {
                // Byte layout must match the COFF object writer's S_FRAMEPROC exactly (26-byte payload):
                // cbFrame, cbPad, cbPadOff, cbSaveRegs, offExHdlr, then the base-register encoding as the
                // u16 at the sectExHdlr slot, then the flags u32 -- with no trailing pad. An extra pad here
                // shifts the flags/base-pointer bits, so msdia/VS reads the wrong frame register and fails
                // to locate locals.
                Bytes fp;
                appendLe32(fp, fn->frameSize);
                appendLe32(fp, 0); // cbPad
                appendLe32(fp, 0); // offset of pad
                appendLe32(fp, 0); // bytes of callee-saved registers
                appendLe32(fp, 0); // exception handler offset
                appendLe16(fp, fn->frameToCodeReg); // frame base-register encoding (sectExHdlr slot)
                appendLe32(fp, fn->frameProcFlags);
                appendSymbol(moduleSymbols, K_S_FRAMEPROC, fp);
            }

            for (const LinkDebugLocal& local : fn->locals)
            {
                // CodeView S_REGREL32 layout is: offset (u32), then type index (u32), then register. They
                // must be in this order -- swapping them feeds msdia/DIA (and thus Visual Studio) a garbage
                // type index, which makes it fault while resolving the local and drop the whole module's
                // symbols. (The COFF object writer, DebugInfoCodeView::appendRegRelativeSymbol, gets it right.)
                Bytes lp;
                appendLe32(lp, static_cast<uint32_t>(local.frameOffset));
                appendLe32(lp, local.typeIndex);
                appendLe16(lp, local.cvRegister);
                appendCString(lp, local.name.view());
                appendSymbol(moduleSymbols, K_S_REGREL32, lp);
            }

            const uint32_t endOffset = appendSymbol(moduleSymbols, K_S_END, {});
            ByteUtils::writeLe32(moduleSymbols, endFieldOffset, symBase + endOffset);
        }

        if (module.buildInfoIndex != 0)
        {
            Bytes payload;
            appendLe32(payload, module.buildInfoIndex);
            appendSymbol(moduleSymbols, K_S_BUILDINFO, payload);
        }

        Bytes c13;
        Bytes chksmContent;
        std::vector<uint32_t> chksmEntryOffset(debugInfo.files.size(), std::numeric_limits<uint32_t>::max());
        for (const uint32_t fileIndex : module.fileIndices)
        {
            const LinkDebugFile& file = debugInfo.files[fileIndex];
            chksmEntryOffset[fileIndex] = static_cast<uint32_t>(chksmContent.size());
            appendLe32(chksmContent, fileNameOffsets[fileIndex]);
            chksmContent.push_back(static_cast<std::byte>(file.checksum.size()));
            chksmContent.push_back(static_cast<std::byte>(file.checksumKind));
            for (const uint8_t b : file.checksum)
                chksmContent.push_back(static_cast<std::byte>(b));
            alignTo4(chksmContent);
        }

        for (const LinkDebugFunction* fn : module.functions)
        {
            if (fn->lineBlocks.empty())
                continue;
            const PdbSymbolAddress addr = resolver.resolve(fn->symbolName);
            if (!addr.found)
                continue;

            Bytes content;
            appendLe32(content, addr.offset);
            appendLe16(content, addr.segment);
            appendLe16(content, 0); // flags (no columns)
            appendLe32(content, fn->codeSize);

            for (const LinkDebugLineBlock& block : fn->lineBlocks)
            {
                const uint32_t numLines = static_cast<uint32_t>(block.lines.size());
                const uint32_t chksmOffset = block.fileIndex < chksmEntryOffset.size() && chksmEntryOffset[block.fileIndex] != std::numeric_limits<uint32_t>::max() ? chksmEntryOffset[block.fileIndex] : 0;
                appendLe32(content, chksmOffset);
                appendLe32(content, numLines);
                appendLe32(content, 12 + numLines * 8);
                for (uint32_t lineIndex = 0; lineIndex < numLines; ++lineIndex)
                {
                    appendLe32(content, block.codeOffsets[lineIndex]);
                    appendLe32(content, K_CV_LINE_STATEMENT | (block.lines[lineIndex] & 0xFFFFFF));
                }
            }

            appendLe32(c13, K_DEBUG_S_LINES);
            appendLe32(c13, static_cast<uint32_t>(content.size()));
            appendBytes(c13, content);
            alignTo4(c13);
        }

        if (!chksmContent.empty())
        {
            appendLe32(c13, K_DEBUG_S_FILECHKSMS);
            appendLe32(c13, static_cast<uint32_t>(chksmContent.size()));
            appendBytes(c13, chksmContent);
            alignTo4(c13);
        }

        appendLe32(module.stream, K_CV_SIGNATURE_C13);
        appendBytes(module.stream, moduleSymbols);
        module.symByteSize = static_cast<uint32_t>(module.stream.size());
        appendBytes(module.stream, c13);
        module.c13ByteSize = static_cast<uint32_t>(c13.size());
        appendLe32(module.stream, 0); // GlobalRefs byte size
    }

    for (const ProcRefSym& procRef : procRefs)
    {
        Bytes payload;
        appendLe32(payload, 0); // checksum of the procedure name; 0 is accepted by MSVC-produced PDBs
        appendLe32(payload, procRef.moduleSymOffset);
        appendLe16(payload, static_cast<uint16_t>(procRef.moduleIndex + 1)); // one-based module index
        appendCString(payload, procRef.name.view());
        const uint32_t recordOffset = appendSymbol(symRecords, K_S_PROCREF, payload);
        globalSyms.push_back({recordOffset, procRef.name});
    }

    // ---- DBI stream -----------------------------------------------------------------------------
    Bytes modInfo;
    uint32_t sourceFileRefCount = 0;
    for (PdbModuleBuild& module : modules)
    {
        appendLe32(modInfo, 0); // Unused1
        appendSectionContribEntry(modInfo, module.codeSegment, module.codeOffset, module.codeSize, module.codeChars, static_cast<uint16_t>(&module - modules.data()));
        appendLe16(modInfo, 0);                 // Flags
        appendLe16(modInfo, module.streamIndex); // ModuleSymStream
        appendLe32(modInfo, module.symByteSize); // SymByteSize
        appendLe32(modInfo, 0);                 // C11ByteSize
        appendLe32(modInfo, module.c13ByteSize); // C13ByteSize
        appendLe16(modInfo, static_cast<uint16_t>(module.fileIndices.size())); // SourceFileCount
        appendLe16(modInfo, 0);                 // padding
        appendLe32(modInfo, 0);                 // Unused2
        appendLe32(modInfo, 0);                 // SourceFileNameIndex (EC string table index)
        appendLe32(modInfo, 0);                 // PdbFilePathNameIndex (EC string table index)
        appendCString(modInfo, module.name.view()); // ModuleName (the object file)
        appendCString(modInfo, module.name.view()); // ObjFileName (standalone object: same as ModuleName)
        alignTo4(modInfo);
        sourceFileRefCount += static_cast<uint32_t>(module.fileIndices.size());
    }

    Bytes secContr;
    {
        std::vector<PdbSectionContribBuild> sectionContribs;
        sectionContribs.reserve(debugInfo.functions.size());
        for (size_t i = 0; i < modules.size(); ++i)
        {
            const PdbModuleBuild& module = modules[i];
            for (const LinkDebugFunction* fn : module.functions)
            {
                const PdbSymbolAddress addr = resolver.resolve(fn->symbolName);
                if (!addr.found || !fn->codeSize)
                    continue;
                sectionContribs.push_back({addr.segment, addr.offset, fn->codeSize, module.codeChars, static_cast<uint16_t>(i)});
            }
        }

        std::ranges::sort(sectionContribs, [](const PdbSectionContribBuild& a, const PdbSectionContribBuild& b) {
            if (a.segment != b.segment)
                return a.segment < b.segment;
            if (a.offset != b.offset)
                return a.offset < b.offset;
            if (a.size != b.size)
                return a.size < b.size;
            return a.moduleIndex < b.moduleIndex;
        });

        appendLe32(secContr, 0xeffe0000u + 19970605u); // Ver60
        for (const PdbSectionContribBuild& sectionContrib : sectionContribs)
            appendSectionContribEntry(secContr, sectionContrib.segment, sectionContrib.offset, sectionContrib.size, sectionContrib.characteristics, sectionContrib.moduleIndex);
    }

    Bytes secMap;
    {
        const auto count = static_cast<uint16_t>(sections.size() + 1);
        appendLe16(secMap, count);
        appendLe16(secMap, count);
        for (size_t i = 0; i < sections.size(); ++i)
        {
            const uint32_t ch = sections[i].characteristics;
            uint16_t flags = 0x8; // AddressIs32Bit
            if (ch & K_SCN_MEM_READ) flags |= 0x1;
            if (ch & K_SCN_MEM_WRITE) flags |= 0x2;
            if (ch & K_SCN_MEM_EXECUTE) flags |= 0x4;
            appendLe16(secMap, flags);
            appendLe16(secMap, 0);                              // Ovl
            appendLe16(secMap, 0);                              // Group
            appendLe16(secMap, static_cast<uint16_t>(i + 1));  // Frame
            appendLe16(secMap, 0xFFFF);                         // SectionName
            appendLe16(secMap, 0xFFFF);                         // ClassName
            appendLe32(secMap, 0);                              // Offset
            appendLe32(secMap, sections[i].virtualSize);        // SectionLength
        }
        // Trailing absolute section descriptor.
        appendLe16(secMap, 0x208);
        appendLe16(secMap, 0);
        appendLe16(secMap, 0);
        appendLe16(secMap, count);
        appendLe16(secMap, 0xFFFF);
        appendLe16(secMap, 0xFFFF);
        appendLe32(secMap, 0);
        appendLe32(secMap, 0xFFFFFFFFu);
    }

    Bytes sourceInfo;
    {
        appendLe16(sourceInfo, static_cast<uint16_t>(modules.size())); // NumModules
        appendLe16(sourceInfo, static_cast<uint16_t>(sourceFileRefCount)); // NumSourceFiles
        uint16_t sourceFileBase = 0;
        for (const PdbModuleBuild& module : modules)
        {
            appendLe16(sourceInfo, sourceFileBase);
            sourceFileBase = static_cast<uint16_t>(sourceFileBase + module.fileIndices.size());
        }
        for (const PdbModuleBuild& module : modules)
            appendLe16(sourceInfo, static_cast<uint16_t>(module.fileIndices.size()));

        Bytes namesBuf;
        std::vector<uint32_t> offs;
        offs.reserve(sourceFileRefCount);
        for (const PdbModuleBuild& module : modules)
        {
            for (const uint32_t fileIndex : module.fileIndices)
            {
                offs.push_back(static_cast<uint32_t>(namesBuf.size()));
                appendCString(namesBuf, debugInfo.files[fileIndex].path.view());
            }
        }
        for (const uint32_t o : offs)
            appendLe32(sourceInfo, o);
        appendBytes(sourceInfo, namesBuf);
        alignTo4(sourceInfo);
    }

    const uint16_t globalsStreamIndex    = static_cast<uint16_t>(moduleStreamStart + modules.size());
    const uint16_t publicsStreamIndex    = static_cast<uint16_t>(globalsStreamIndex + 1);
    const uint16_t symRecordsStreamIndex = static_cast<uint16_t>(publicsStreamIndex + 1);
    const uint16_t sectionHdrStreamIndex = static_cast<uint16_t>(symRecordsStreamIndex + 1);
    const uint16_t tpiHashStreamIndex    = static_cast<uint16_t>(sectionHdrStreamIndex + 1);
    const uint16_t ipiHashStreamIndex    = static_cast<uint16_t>(tpiHashStreamIndex + 1);

    // Edit-and-continue substream: a minimal but valid empty string table.
    Bytes ecSubstream;
    {
        appendLe32(ecSubstream, 0xEFFEEFFEu);
        appendLe32(ecSubstream, 1);
        appendLe32(ecSubstream, 1);
        ecSubstream.push_back(std::byte{0});
        appendLe32(ecSubstream, 1); // bucket count
        appendLe32(ecSubstream, 0); // bucket[0]
        appendLe32(ecSubstream, 0); // name count
        alignTo4(ecSubstream);
    }

    Bytes optDbgHeader;
    {
        for (uint16_t i = 0; i < 11; ++i)
            appendLe16(optDbgHeader, i == 5 ? sectionHdrStreamIndex : 0xFFFF);
    }

    Bytes dbi;
    {
        appendLe32(dbi, 0xFFFFFFFFu);    // VersionSignature (-1)
        appendLe32(dbi, 19990903);       // VersionHeader (V70)
        appendLe32(dbi, outAge);         // Age
        appendLe16(dbi, globalsStreamIndex); // GlobalStreamIndex
        appendLe16(dbi, 0x8e32);         // BuildNumber: new-format flag | 14.50, matching link.exe's DBI header
        appendLe16(dbi, publicsStreamIndex); // PublicStreamIndex
        appendLe16(dbi, 35726);          // PdbDllVersion (non-zero, matching the link.exe-produced PDB)
        appendLe16(dbi, symRecordsStreamIndex); // SymRecordStreamIndex
        appendLe16(dbi, 0);              // PdbDllRbld
        appendLe32(dbi, static_cast<uint32_t>(modInfo.size()));
        appendLe32(dbi, static_cast<uint32_t>(secContr.size()));
        appendLe32(dbi, static_cast<uint32_t>(secMap.size()));
        appendLe32(dbi, static_cast<uint32_t>(sourceInfo.size()));
        appendLe32(dbi, 0);              // TypeServerMapSize
        appendLe32(dbi, 0);              // MFCTypeServerIndex
        appendLe32(dbi, static_cast<uint32_t>(optDbgHeader.size()));
        appendLe32(dbi, static_cast<uint32_t>(ecSubstream.size()));
        appendLe16(dbi, 0);              // Flags
        appendLe16(dbi, 0x8664);         // Machine (AMD64)
        appendLe32(dbi, 0);              // Reserved
        appendBytes(dbi, modInfo);
        appendBytes(dbi, secContr);
        appendBytes(dbi, secMap);
        appendBytes(dbi, sourceInfo);
        appendBytes(dbi, ecSubstream);
        appendBytes(dbi, optDbgHeader);
    }

    // ---- Globals / publics streams --------------------------------------------------------------
    const Bytes globalsStream = buildGsiHash(globalSyms);

    Bytes publicsStream;
    {
        std::ranges::sort(publicAddrs, [](const auto& a, const auto& b) {
            if (a.second.segment != b.second.segment)
                return a.second.segment < b.second.segment;
            return a.second.offset < b.second.offset;
        });

        const Bytes hash = buildGsiHash(publicSyms);
        Bytes addrMap;
        for (const auto& [recordOffset, addr] : publicAddrs)
            appendLe32(addrMap, recordOffset);

        appendLe32(publicsStream, static_cast<uint32_t>(hash.size())); // SymHash size
        appendLe32(publicsStream, static_cast<uint32_t>(addrMap.size())); // AddrMap size
        appendLe32(publicsStream, 0); // NumThunks
        appendLe32(publicsStream, 0); // SizeOfThunk
        appendLe16(publicsStream, 0); // ISectThunkTable
        appendLe16(publicsStream, 0); // padding
        appendLe32(publicsStream, 0); // OffThunkTable
        appendLe32(publicsStream, 0); // NumSections
        appendBytes(publicsStream, hash);
        appendBytes(publicsStream, addrMap);
    }

    // ---- Section headers stream -----------------------------------------------------------------
    Bytes sectionHdrStream;
    for (const PdbSectionInfo& s : sections)
    {
        char nameField[8] = {};
        const std::string_view nm = s.name.view();
        std::memcpy(nameField, nm.data(), std::min<size_t>(nm.size(), 8));
        for (const char c : nameField)
            sectionHdrStream.push_back(static_cast<std::byte>(c));
        appendLe32(sectionHdrStream, s.virtualSize);
        appendLe32(sectionHdrStream, s.rva);
        appendLe32(sectionHdrStream, s.rawSize);
        appendLe32(sectionHdrStream, s.fileOffset);
        appendLe32(sectionHdrStream, 0); // PointerToRelocations
        appendLe32(sectionHdrStream, 0); // PointerToLinenumbers
        appendLe16(sectionHdrStream, 0); // NumberOfRelocations
        appendLe16(sectionHdrStream, 0); // NumberOfLinenumbers
        appendLe32(sectionHdrStream, s.characteristics);
    }

    // ---- PDB info stream ------------------------------------------------------------------------
    Bytes pdbInfo;
    {
        appendLe32(pdbInfo, 20000404);      // Version (VC70)
        appendLe32(pdbInfo, outSignature);  // Signature
        appendLe32(pdbInfo, outAge);        // Age
        for (const uint8_t b : outGuid)
            pdbInfo.push_back(static_cast<std::byte>(b));

        // Named stream map: maps "/names" to the names stream.
        Bytes strBuffer;
        const auto namesKeyOffset = static_cast<uint32_t>(strBuffer.size());
        appendCString(strBuffer, "/names");

        appendLe32(pdbInfo, static_cast<uint32_t>(strBuffer.size()));
        appendBytes(pdbInfo, strBuffer);

        // Hash table with a single entry.
        const uint32_t capacity = 4;
        std::vector<int64_t> bucketKey(capacity, -1);
        std::vector<uint32_t> bucketVal(capacity, 0);
        uint32_t b = hashStringV1("/names") % capacity;
        while (bucketKey[b] != -1)
            b = (b + 1) % capacity;
        bucketKey[b] = namesKeyOffset;
        bucketVal[b] = STREAM_NAMES;

        appendLe32(pdbInfo, 1);        // Size (present entries)
        appendLe32(pdbInfo, capacity); // Capacity
        // Present bit vector.
        const uint32_t presentWords = (capacity + 31) / 32;
        appendLe32(pdbInfo, presentWords);
        std::vector<uint32_t> present(presentWords, 0);
        present[b / 32] |= (1u << (b % 32));
        for (const uint32_t w : present)
            appendLe32(pdbInfo, w);
        appendLe32(pdbInfo, 0); // Deleted bit vector word count
        for (uint32_t i = 0; i < capacity; ++i)
        {
            if (bucketKey[i] == -1)
                continue;
            appendLe32(pdbInfo, static_cast<uint32_t>(bucketKey[i]));
            appendLe32(pdbInfo, bucketVal[i]);
        }

        appendLe32(pdbInfo, 20140508); // Feature: VC140 (signals presence of IPI stream)
    }

    // ---- Assemble all streams -------------------------------------------------------------------
    Bytes tpiHash;
    Bytes ipiHash;
    std::vector<Bytes> streams(static_cast<size_t>(ipiHashStreamIndex) + 1);
    streams[STREAM_OLD_DIRECTORY] = {};
    streams[STREAM_PDB_INFO]      = std::move(pdbInfo);
    streams[STREAM_TPI]           = buildTpiStream(debugInfo.tpiRecords, debugInfo.tpiIndexEnd, tpiHashStreamIndex, tpiHash);
    streams[STREAM_DBI]           = std::move(dbi);
    streams[STREAM_IPI]           = buildTpiStream(ipiRecords, ipiIndexEnd, ipiHashStreamIndex, ipiHash);
    streams[STREAM_NAMES]         = names.serialize();
    for (PdbModuleBuild& module : modules)
        streams[module.streamIndex] = std::move(module.stream);
    streams[globalsStreamIndex]    = globalsStream;
    streams[publicsStreamIndex]    = std::move(publicsStream);
    streams[symRecordsStreamIndex] = std::move(symRecords);
    streams[sectionHdrStreamIndex] = std::move(sectionHdrStream);
    streams[tpiHashStreamIndex]    = std::move(tpiHash);
    streams[ipiHashStreamIndex]    = std::move(ipiHash);

    (void)pdbPath;
    buildMsf(outBytes, streams);
}

SWC_END_NAMESPACE();

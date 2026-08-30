#global public
#global namespace Scc

using Core.Errors, Core.Serialization

// Current major version of the Swag Chunk Container envelope.
const FormatMajor = 1'u16

// Current backward-compatible revision of the Swag Chunk Container envelope.
const FormatMinor = 0'u16

// Number of bytes before the TagBin-encoded SCC header.
const PrefixSize = 32'u64

private const Magic = "SWAGSCC\0"

// Describes the representation stored in a metadata value.
enum MetadataKind
{
    Text         // UTF-8 text in `textValue`.
    Signed       // Signed integer in `signedValue`.
    Unsigned     // Unsigned integer in `unsignedValue`.
    Float        // Floating-point number in `floatValue`.
    Boolean      // Boolean in `booleanValue`.
    Bytes        // Opaque bytes in `bytesValue`.
}

// Stores one typed metadata value.
struct MetadataValue
{
    public
    {
        kind:          MetadataKind     // Selects which value field is meaningful.
        textValue:     String           // UTF-8 value used by `Text`.
        signedValue:   s64              // Integer value used by `Signed`.
        unsignedValue: u64              // Integer value used by `Unsigned`.
        floatValue:    f64              // Floating-point value used by `Float`.
        booleanValue:  bool             // Boolean value used by `Boolean`.
        bytesValue:    Array'u8         // Opaque value used by `Bytes`.
    }
}

// Associates a qualified metadata name with a typed value.
struct Property
{
    public
    {
        name:  String            // Profile-qualified property name.
        value: MetadataValue     // Typed property value.
    }
}

// Describes one node in the manifest's virtual hierarchy.
enum EntryKind
{
    Directory     // A virtual directory that can own other entries.
    File          // A virtual file represented by one or more chunks.
}

// Maps a virtual file or directory to the chunks that represent it.
struct Entry
{
    public
    {
        id:            Guid128            // Stable identity of this virtual entry.
        parentId:      Guid128            // Parent directory identity, or null for a root entry.
        kind:          EntryKind          // Whether this entry is a directory or file.
        name:          String             // Display name inside the virtual hierarchy.
        tags:          Array'String       // Entry-local search tags.
        primaryChunk:  Guid128            // Preferred payload chunk, or null for a directory.
        variantChunks: Array'Guid128      // Alternative or supplemental payload chunks.
        properties:    Array'Property     // Profile-specific entry metadata.
    }
}

// Contains inexpensive information available without reading any chunk payload.
struct Manifest
{
    public
    {
        version:        u32 = 1            // Version of this generic manifest schema.
        profileVersion: u32                // Version interpreted by the container profile.
        name:           String             // Container display name.
        description:    String             // Optional human-readable description.
        createdAt:      Time.DateTime      // Original creation time when known.
        modifiedAt:     Time.DateTime      // Last logical modification time when known.
        tags:           Array'String       // Search tags available from the header alone.
        entries:        Array'Entry        // Virtual files and directories exposed by the container.
        properties:     Array'Property     // Generic or profile-qualified metadata.
        profileData:    Array'u8           // Small profile header decoded without reading a chunk.
    }
}

// Controls how a reader treats a chunk.
#[Swag.EnumFlags]
enum ChunkFlags
{
    None = 0            // No optional behavior.
    Required            // The owning profile needs this chunk to open the document.
    Metadata            // The payload describes other content.
    Streamable          // The payload format permits progressive processing.
    PreserveUnknown     // Editors preserve the stored bytes when they do not understand the chunk.
}

// Describes one independently addressable payload.
struct ChunkInfo
{
    public readonly
    {
        id:              Guid128        // Stable chunk identity.
        typeId:          Guid128        // Payload format or schema identity.
        roleId:          Guid128        // Profile-defined semantic role.
        codecId:         Guid128        // Compression codec, or null for stored bytes.
        schemaVersion:   u32 = 1        // Version of the payload schema.
        flags:           ChunkFlags     // Requirements and preservation hints.
        offset:          u64            // Absolute payload offset in the file.
        storedSize:      u64            // Number of bytes present on disk.
        decodedSize:     u64            // Number of bytes returned by the codec.
        storedChecksum:  u32            // CRC-32 of the stored bytes.
        decodedChecksum: u32            // CRC-32 of the decoded bytes.
    }
}

// Sets resource limits applied before allocation or decompression.
struct ReadLimits
{
    public
    {
        maxHeaderSize:     u64 = 64 * 1024 * 1024            // Largest encoded header accepted.
        maxChunkCount:     u64 = 1_000_000                   // Largest chunk directory accepted.
        maxStoredChunk:    u64 = 16 * 1024 * 1024 * 1024     // Largest stored payload accepted.
        maxDecodedChunk:   u64 = 16 * 1024 * 1024 * 1024     // Largest decoded payload accepted.
        maxExpansionRatio: u64 = 65_536                      // Largest decoded-to-stored ratio accepted.
    }
}

// Supplies compression and decompression for a custom codec identifier.
//
// A registered codec is borrowed and must outlive every reader or writer that stores it.
interface ICodec
{
    // Returns the stable identifier written into SCC chunk entries.
    mtd id()->Guid128

    // Encodes one complete payload into owned stored bytes.
    mtd encode(source: const [..] u8)->Array'u8 fail

    // Decodes one complete payload and returns exactly `decodedSize` bytes.
    mtd decode(source: const [..] u8, decodedSize: u64)->Array'u8 fail
}

// Options used when adding a chunk.
struct ChunkOptions
{
    public
    {
        id:            Guid128        // Requested identity, or null to generate one.
        typeId:        Guid128        // Payload format or schema identity.
        roleId:        Guid128        // Profile-defined semantic role.
        codecId:       Guid128        // Registered codec, or null for no compression.
        schemaVersion: u32 = 1        // Version of the payload schema.
        flags:         ChunkFlags     // Requirements and preservation hints.
        alignment:     u32 = 8        // Payload alignment; zero is treated as one.
    }
}

#[Swag.NoDoc]
#[Serialization.Version(1)]
struct Header
{
    containerKind:    Guid128
    containerId:      Guid128
    generation:       u64 = 1
    declaredFileSize: u64
    manifest:         Manifest
    chunks:           Array'ChunkInfo
}

#[Swag.NoDoc]
struct PendingChunk
{
    info:      ChunkInfo
    alignment: u32
    bytes:     Array'u8
}

// Builds a new SCC file from independently encoded chunks.
#[Swag.NoCopy]
struct Writer
{
    private
    {
        header: Header
        chunks: Array'PendingChunk
        codecs: Array'ICodec
    }
}

// Owns an open SCC file and reads chunks on demand.
#[Swag.NoCopy]
struct Reader
{
    private
    {
        stream: File.FileStream
        header: Header
        limits: ReadLimits
        codecs: Array'ICodec
    }
}

private func writeU16(buffer: *Array'u8, value: u16)
{
    buffer.add(cast(u8) (value & 0xFF))
    buffer.add(cast(u8) ((value >> 8) & 0xFF))
}

private func writeU32(buffer: *Array'u8, value: u32)
{
    for i in 4 do
        buffer.add(cast(u8) ((value >> (i * 8)) & 0xFF))
}

private func writeU64(buffer: *Array'u8, value: u64)
{
    for i in 8 do
        buffer.add(cast(u8) ((value >> (i * 8)) & 0xFF))
}

private func readU16(buffer: const [..] u8, offset: u64)->u16
{
    return cast(u16) buffer[offset] | cast(u16) buffer[offset + 1] << 8
}

private func readU32(buffer: const [..] u8, offset: u64)->u32
{
    var result: u32
    for i in 4 do
        result |= cast(u32) buffer[offset + i] << (i * 8)
    return result
}

private func readU64(buffer: const [..] u8, offset: u64)->u64
{
    var result: u64
    for i in 8 do
        result |= cast(u64) buffer[offset + i] << (i * 8)
    return result
}

private func alignUp(value: u64, alignment: u32)->u64
{
    let effective = alignment ? cast(u64) alignment : 1
    let remainder = value % effective
    return remainder ? value + effective - remainder : value
}

private func sameId(left, right: Guid128)->bool => left == right

private func makeId(text: string)->Guid128
{
    var result: Guid128
    let valid = Guid128.tryParse(text, &result)
    Debug.assert(valid)
    return result
}

// Returns the identifier for an uncompressed chunk.
func noCodecId()->Guid128 => {}

// Returns the predefined zlib/Deflate codec identifier.
func deflateCodecId()->Guid128 => makeId("21bf86c9-55f7-4c90-a454-2f070a0f6e9b")

private func encodeHeader(header: const *Header)->Array'u8 fail
{
    var output:  ConcatBuffer
    var encoder: Encoder'Write.TagBin
    encoder.writeAll(&output, header[])
    output.makeLinear()

    var result: retval
    result.add(output.toSlice()!)
    return result
}

private func decodeHeader(bytes: const [..] u8)->Header fail
{
    var decoder: Decoder'Read.TagBin
    var result:  retval
    decoder.start(bytes)
    decoder.readTypedContent(&result, #typeof(Header))
    decoder.end()
    return result
}

private func findCodec(codecs: Array'ICodec, id: Guid128)->#null ICodec
{
    for codec in codecs where sameId(codec.id(), id) do
        return codec
    return null
}

private func encodePayload(codecs: Array'ICodec, codecId: Guid128, source: const [..] u8)->Array'u8 fail
{
    if codecId.isNull()
    {
        var result: retval
        result.add(source)
        return result
    }

    if sameId(codecId, deflateCodecId())
    {
        var codec: Core.Compress.ZLib
        return codec.compress(source, .BestSpeed)
    }

    let codec = findCodec(codecs, codecId)
    if !codec do
        fail UnsupportedFormatError{"SCC has no encoder for the selected chunk codec"}
    return codec.encode(source)
}

private func decodePayload(codecs: Array'ICodec, info: const *ChunkInfo, source: const [..] u8)->Array'u8 fail
{
    if info.codecId.isNull()
    {
        var result: retval
        result.add(source)
        return result
    }

    if sameId(info.codecId, deflateCodecId())
    {
        var codec: Core.Compress.ZLib
        return codec.decompress(source, info.decodedSize)
    }

    let codec = findCodec(codecs, info.codecId)
    if !codec do
        fail UnsupportedFormatError{"SCC has no decoder for this chunk codec"}
    return codec.decode(source, info.decodedSize)
}

private func validateManifest(manifest: const *Manifest, chunks: const [..] ChunkInfo) fail
{
    var chunkIds: HashSet'Guid128
    for chunk in chunks
    {
        if chunk.id.isNull() or chunkIds.contains(chunk.id) do
            fail InvalidFormatError{"SCC chunk identifiers must be non-null and unique"}
        chunkIds.add(chunk.id)
    }

    var entryKinds: HashTable'(Guid128, EntryKind)
    for entry in manifest.entries
    {
        if entry.id.isNull() or entryKinds.contains(entry.id) do
            fail InvalidFormatError{"SCC virtual entry identifiers must be non-null and unique"}
        if entry.parentId == entry.id do
            fail InvalidFormatError{"SCC virtual entry cannot be its own parent"}
        entryKinds.add(entry.id, entry.kind)
        if !entry.primaryChunk.isNull() and !chunkIds.contains(entry.primaryChunk) do
            fail InvalidFormatError{"SCC virtual entry references an unknown primary chunk"}
        for chunkId in entry.variantChunks where !chunkIds.contains(chunkId) do
            fail InvalidFormatError{"SCC virtual entry references an unknown variant chunk"}
    }

    for entry in manifest.entries
    {
        if entry.parentId.isNull() do
            continue
        let parent = entryKinds.tryFind(entry.parentId)
        if !parent do
            fail InvalidFormatError{"SCC virtual entry references an unknown parent"}
        if parent.value != .Directory do
            fail InvalidFormatError{"SCC virtual entry parent must be a directory"}
    }
}

impl Writer
{
    // Initializes this writer as an empty container for `containerKind`.
    mtd initialize(containerKind: Guid128)
    {
        Debug.assert(!containerKind.isNull())
        .header.containerKind = containerKind
        .header.containerId   = Guid128.random()
    }

    // Returns the persistent identity assigned to this container.
    mtd const id()->Guid128 => .header.containerId

    // Returns mutable header metadata to populate before saving.
    mtd manifest()->*Manifest => &.header.manifest

    // Replaces the persistent identity and generation when rewriting an existing container.
    mtd setIdentity(id: Guid128, generation: u64)
    {
        .header.containerId = id
        .header.generation  = generation
    }

    // Registers a borrowed custom chunk codec.
    mtd registerCodec(codec: ICodec)
    {
        Debug.assert(!codec.id().isNull())
        Debug.assert(!sameId(codec.id(), deflateCodecId()))
        for current in .codecs do
            Debug.assert(!sameId(current.id(), codec.id()))
        .codecs.add(codec)
    }

    // Adds an independently addressable payload and returns its stable chunk identifier.
    mtd addChunk(source: const [..] u8, options: ChunkOptions)->Guid128 fail
    {
        var id = options.id
        if id.isNull() do
            id = Guid128.random()
        for chunk in .chunks where sameId(chunk.info.id, id) do
            fail BadParameterError{"SCC chunk identifiers must be unique"}

        var pending: PendingChunk
        pending.info.id              = id
        pending.info.typeId          = options.typeId
        pending.info.roleId          = options.roleId
        pending.info.codecId         = options.codecId
        pending.info.schemaVersion   = options.schemaVersion
        pending.info.flags           = options.flags
        pending.info.decodedSize     = source.count
        pending.info.decodedChecksum = Hash.Crc32.compute(source)
        pending.alignment            = options.alignment ? options.alignment : 1
        pending.bytes                = try encodePayload(.codecs, options.codecId, source)
        pending.info.storedSize      = pending.bytes.count
        pending.info.storedChecksum  = Hash.Crc32.compute(pending.bytes.toSlice())
        .chunks.add(#move pending)
        return id
    }

    // Writes the complete container to a temporary peer and atomically replaces `fileName`.
    mtd saveAtomic(fileName: string) fail
    {
        .header.chunks.clear()
        for &chunk in .chunks do
            .header.chunks.add(chunk.info)
        validateManifest(&.header.manifest, .header.chunks.toSlice())

        var headerBytes = try encodeHeader(&.header)
        var dataOffset  = alignUp(PrefixSize + headerBytes.count, 8)
        for i in .chunks.count
        {
            dataOffset = alignUp(dataOffset, .chunks[i].alignment)
            if .chunks[i].info.storedSize > 0xFFFFFFFFFFFFFFFF - dataOffset do
                fail OverflowError{"SCC chunk layout exceeds the addressable file size"}
            .chunks[i].info.offset   = dataOffset
            .header.chunks[i].offset = dataOffset
            dataOffset               += .chunks[i].info.storedSize
        }

        .header.declaredFileSize = dataOffset

        headerBytes = try encodeHeader(&.header)
        let firstDataOffset = .chunks.count ? .chunks[0].info.offset : alignUp(PrefixSize + headerBytes.count, 8)
        if PrefixSize + headerBytes.count > firstDataOffset do
            fail OverflowError{"SCC header grew after chunk offsets were assigned"}

        var prefix: Array'u8
        prefix.add(cast(const [..] u8) Magic)
        writeU16(&prefix, FormatMajor)
        writeU16(&prefix, FormatMinor)
        writeU32(&prefix, 0)
        writeU64(&prefix, headerBytes.count)
        writeU32(&prefix, Hash.Crc32.compute(headerBytes.toSlice()))
        writeU32(&prefix, 0)
        Debug.assert(prefix.count == PrefixSize)

        let temporary = Format.toString("%.scc-tmp-%", fileName, Guid64.random())
        var committed = false
        defer
        {
            if !committed and File.exists(temporary) do
                discard catch File.delete(temporary)
        }

        var output = File.openWrite(temporary)
        output.writeAll(prefix.toSlice())
        output.writeAll(headerBytes.toSlice())

        var position = PrefixSize + headerBytes.count
        var zero: [4096] u8
        for chunk in .chunks
        {
            while position < chunk.info.offset
            {
                let count = Math.min(chunk.info.offset - position, #sizeof(zero))
                output.writeAll(zero[until count])
                position += count
            }

            output.writeAll(chunk.bytes.toSlice())
            position += chunk.bytes.count
        }

        while position < .header.declaredFileSize
        {
            let count = Math.min(.header.declaredFileSize - position, #sizeof(zero))
            output.writeAll(zero[until count])
            position += count
        }

        output.flush()
        output.close()
        File.move(fileName, temporary)
        committed = true
    }
}

impl Reader
{
    // Initializes this reader and reads only the SCC prefix and header.
    mtd initialize(fileName: string, limits: ReadLimits = {}) fail
    {
        .limits = limits
        .stream = File.openRead(fileName)

        var prefix: [PrefixSize] u8
        if !.stream.readExact(prefix) do
            fail InvalidFormatError{"SCC prefix is truncated"}
        if Swag.memcmp(&prefix[0], Magic.buffer, Magic.count) != 0 do
            fail InvalidFormatError{"file does not contain an SCC signature"}
        if readU32(prefix, 12) or readU32(prefix, 28) do
            fail UnsupportedFormatError{"SCC prefix contains unsupported flags"}

        let major = readU16(prefix, 8)
        if major != FormatMajor do
            fail InvalidVersion{wantedVersion: FormatMajor, foundVersion: major}

        let headerSize = readU64(prefix, 16)
        if headerSize > limits.maxHeaderSize do
            fail OverflowError{"SCC header exceeds the configured size limit"}
        let fileSize = .stream.size()
        if headerSize > fileSize - PrefixSize do
            fail InvalidFormatError{"SCC header runs past the end of the file"}

        var headerBytes: Array'u8
        headerBytes.resize(headerSize)
        if !.stream.readExact(headerBytes.toSlice()) do
            fail InvalidFormatError{"SCC header is truncated"}
        if Hash.Crc32.compute(headerBytes.toSlice()) != readU32(prefix, 24) do
            fail InvalidFormatError{"SCC header checksum does not match its bytes"}

        .header = try decodeHeader(headerBytes.toSlice())
        if .header.manifest.version > 1 do
            fail InvalidVersion{wantedVersion: 1, foundVersion: .header.manifest.version}
        if .header.containerKind.isNull() or .header.containerId.isNull() or !.header.generation do
            fail InvalidFormatError{"SCC header identities and generation must be non-null"}
        if .header.chunks.count > limits.maxChunkCount do
            fail OverflowError{"SCC chunk count exceeds the configured limit"}
        if .header.declaredFileSize != fileSize do
            fail InvalidFormatError{"SCC declared size does not match the file size"}

        var chunkIds: HashSet'Guid128
        var previousEnd = PrefixSize + headerSize
        for chunk in .header.chunks
        {
            if chunk.id.isNull() or chunkIds.contains(chunk.id) do
                fail InvalidFormatError{"SCC chunk identifiers must be non-null and unique"}
            chunkIds.add(chunk.id)
            if chunk.storedSize > limits.maxStoredChunk or chunk.decodedSize > limits.maxDecodedChunk do
                fail OverflowError{"SCC chunk exceeds the configured size limit"}
            if chunk.offset < PrefixSize + headerSize or chunk.offset > fileSize or chunk.storedSize > fileSize - chunk.offset do
                fail InvalidFormatError{"SCC chunk range runs outside the file"}
            if chunk.offset < previousEnd do
                fail InvalidFormatError{"SCC chunk ranges overlap or are not ordered"}
            previousEnd = chunk.offset + chunk.storedSize
            if chunk.codecId.isNull() and chunk.decodedSize != chunk.storedSize do
                fail InvalidFormatError{"an uncompressed SCC chunk has different stored and decoded sizes"}
            if !chunk.storedSize and chunk.decodedSize do
                fail OverflowError{"SCC chunk expansion ratio exceeds the configured limit"}
            if chunk.storedSize
            {
                let quotient  = chunk.decodedSize / chunk.storedSize
                let remainder = chunk.decodedSize % chunk.storedSize
                if quotient > limits.maxExpansionRatio or (quotient == limits.maxExpansionRatio and remainder) do
                    fail OverflowError{"SCC chunk expansion ratio exceeds the configured limit"}
            }
        }

        validateManifest(&.header.manifest, .header.chunks.toSlice())
    }

    // Closes the underlying file while keeping the decoded header available.
    mtd close()
    {
        .stream.close()
    }

    // Releases the underlying file when the reader leaves scope.
    mtd opDrop()
    {
        .close()
    }

    // Registers a borrowed custom chunk codec.
    mtd registerCodec(codec: ICodec)
    {
        Debug.assert(!codec.id().isNull())
        Debug.assert(!sameId(codec.id(), deflateCodecId()))
        for current in .codecs do
            Debug.assert(!sameId(current.id(), codec.id()))
        .codecs.add(codec)
    }

    // Returns the container profile identifier.
    mtd const kind()->Guid128 => .header.containerKind

    // Returns the persistent container identity.
    mtd const id()->Guid128 => .header.containerId

    // Returns the container generation.
    mtd const generation()->u64 => .header.generation

    // Returns borrowed metadata valid until this reader is destroyed.
    mtd const manifest()->const *Manifest => &.header.manifest

    // Returns borrowed chunk entries valid until this reader is destroyed.
    mtd const chunks()->const [..] ChunkInfo => .header.chunks.toSlice()

    // Finds a chunk by identifier, or returns `null` when it is absent.
    mtd const findChunk(id: Guid128)->#null const *ChunkInfo
    {
        for &chunk in .header.chunks where sameId(chunk.id, id) do
            return chunk
        return null
    }

    // Finds the first chunk carrying `roleId`, or returns `null` when it is absent.
    mtd const findRole(roleId: Guid128)->#null const *ChunkInfo
    {
        for &chunk in .header.chunks where sameId(chunk.roleId, roleId) do
            return chunk
        return null
    }

    // Reads stored bytes without requiring the chunk codec.
    mtd readStoredChunk(id: Guid128)->Array'u8 fail
    {
        let info = .findChunk(id)
        if !info do
            fail BadParameterError{"SCC has no chunk with this identifier"}

        var result: retval
        result.resize(info.storedSize)
        if !.stream.readExactAt(info.offset, result.toSlice()) do
            fail InvalidFormatError{"SCC chunk payload is truncated"}
        if Hash.Crc32.compute(result.toSlice()) != info.storedChecksum do
            fail InvalidFormatError{"SCC stored chunk checksum does not match its bytes"}
        return result
    }

    // Reads, verifies, and decompresses one chunk into owned bytes.
    mtd readChunk(id: Guid128)->Array'u8 fail
    {
        let info = .findChunk(id)
        if !info do
            fail BadParameterError{"SCC has no chunk with this identifier"}

        var stored = try .readStoredChunk(id)
        let result = try decodePayload(.codecs, info!, stored.toSlice())
        if result.count != info.decodedSize do
            fail InvalidFormatError{"SCC codec returned a different decoded size"}
        if Hash.Crc32.compute(result.toSlice()) != info.decodedChecksum do
            fail InvalidFormatError{"SCC decoded chunk checksum does not match its bytes"}
        return result
    }
}

// Returns whether `fileName` begins with the SCC signature.
func hasSignature(fileName: string)->bool fail
{
    var stream = File.openRead(fileName)
    var magic: [8] u8
    if !stream.readExact(magic) do
        return false
    return Swag.memcmp(&magic[0], Magic.buffer, Magic.count) == 0
}

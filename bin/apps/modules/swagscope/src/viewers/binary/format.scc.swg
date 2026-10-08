#global internal
#global namespace Viewers.Binary

using Core

// Bytes every Swag Chunk Container begins with.
private const SccMagic = "SWAGSCC"

// Returns whether the file begins with the container signature.
func isSccContainer(image: *BinaryImage)->bool => image.matches(0, SccMagic) and image.u8At(7) == 0

// Adds the envelope, the manifest, and the chunk directory of a Swag Chunk Container.
//
// The prefix is read from the loaded bytes and the rest through the container reader, so a file
// whose header fails validation still shows the envelope that says why.
func reportSccContainer(image: *BinaryImage, report: *Report, fileName: string)
{
    image.bigEndian = false

    let texts      = texts()
    let major      = image.u16At(8)
    let minor      = image.u16At(10)
    let headerSize = image.u64At(16)

    report.beginGroup(texts.scc_Prefix, SccMagic, "", offset: 0, length: Scc.PrefixSize, open: true)
    report.field(8, 4, texts.fld_Version, "", "")
    report.numField(8, 2, "FormatMajor", cast(u64, major))
    report.numField(10, 2, "FormatMinor", cast(u64, minor))
    report.hexField(12, 4, "Flags", cast(u64, image.u32At(12)))
    report.sizeField(16, 8, "HeaderSize", headerSize)
    report.hexField(24, 4, "HeaderChecksum", cast(u64, image.u32At(24)))
    report.field(Scc.PrefixSize, headerSize, texts.fld_Header, "", texts.scc_Manifest)
    report.endGroup()

    report.formatName = "SCC"

    var reader: Scc.Reader
    catch reader.initialize(fileName) as openError
    if openError != null
    {
        report.note(texts.scc_Unreadable)
        report.summary = Format.toString("SCC %.% · %", major, minor, texts.scc_Unreadable)
        return
    }

    let identity   = reader.id().toString()
    let kind       = reader.kind().toString()
    let generation = reader.generation()

    report.beginGroup(texts.scc_Container, identity, "", open: true)
    report.derived("ContainerKind", kind)
    report.derived("ContainerId", identity)
    let generationText = Format.toString("%", generation)
    report.derived("Generation", generationText)
    report.endGroup()

    reportSccManifest(report, reader.manifest())
    reportSccChunks(report, reader.chunks())

    let chunks = countText(reader.chunks().count, texts.word_Chunk, texts.word_Chunks)
    report.summary = Format.toString("SCC %.% · %", major, minor, chunks)
}

// Reports the SCC manifest: version, profile, description, dates and tags, then its properties and
// entries.
private func reportSccManifest(report: *Report, manifest: const *Scc.Manifest)
{
    let texts = texts()
    report.beginGroup(texts.scc_Manifest, manifest.name, "", open: true)

    let version = Format.toString("%", manifest.version)
    let profile = Format.toString("%", manifest.profileVersion)
    report.derived(texts.fld_Version, version)
    report.derived("ProfileVersion", profile)
    if not manifest.description.isEmpty() do
        report.derived("Description", manifest.description)

    let created  = manifest.createdAt.toString(.DateTimeIso)
    let modified = manifest.modifiedAt.toString(.DateTimeIso)
    if manifest.createdAt.isValid() do
        report.derived(texts.scc_Created, created)
    if manifest.modifiedAt.isValid() do
        report.derived(texts.scc_Modified, modified)

    if not manifest.tags.isEmpty()
    {
        var joined: String
        for tag in manifest.tags
        {
            if not joined.isEmpty() do
                joined += ", "
            joined += tag.toString()
        }

        report.derived(texts.scc_Tags, joined)
    }

    if not manifest.profileData.isEmpty()
    {
        let stored = StrConv.toDisplaySize(manifest.profileData.count)
        report.derived(texts.scc_Profile, stored)
    }

    reportSccProperties(report, manifest.properties.toSlice())
    reportSccEntries(report, manifest.entries.toSlice())
    report.endGroup()
}

private func reportSccProperties(report: *Report, properties: const [..] Scc.Property)
{
    if not properties.count do
        return

    let texts = texts()
    let total = countText(properties.count, texts.word_Property, texts.word_Properties)
    report.beginGroup(texts.scc_Properties, total, "")

    for property in properties
    {
        let value = sccValueText(&property.value)
        report.derived(property.name, value)
    }

    report.endGroup()
}

// Returns one typed metadata value in the reading its own kind calls for.
private func sccValueText(value: const *Scc.MetadataValue)->String
{
    switch value.kind
    {
    case .Text:     return value.textValue
    case .Signed:   return Format.toString("%", value.signedValue)
    case .Unsigned: return Format.toString("%", value.unsignedValue)
    case .Float:    return Format.toString("%", value.floatValue)
    case .Boolean:  return Format.toString("%", value.booleanValue)
    case .Bytes:    return StrConv.toDisplaySize(value.bytesValue.count)
    }

    return NoValue
}

// Adds the virtual hierarchy the manifest declares, parents before the entries they own.
private func reportSccEntries(report: *Report, entries: const [..] Scc.Entry)
{
    if not entries.count do
        return

    let texts = texts()
    let total = countText(entries.count, texts.word_Entry, texts.word_Entries)
    report.beginGroup(texts.scc_Entries, total, "", open: true)

    for entry in entries
    {
        let kind = entry.kind == .Directory ? texts.scc_Directory : texts.scc_VirtualFile
        report.beginGroup(entry.name, kind, "")

        let identity = entry.id.toString()
        report.derived("Id", identity)
        if not entry.parentId.isNull()
        {
            let parent = entry.parentId.toString()
            report.derived("ParentId", parent)
        }

        if not entry.primaryChunk.isNull()
        {
            let chunk = entry.primaryChunk.toString()
            report.derived("PrimaryChunk", chunk)
        }

        if not entry.variantChunks.isEmpty()
        {
            let variants = countText(entry.variantChunks.count, texts.word_Chunk, texts.word_Chunks)
            report.derived("VariantChunks", variants)
        }

        reportSccProperties(report, entry.properties.toSlice())
        report.endGroup()
    }

    report.endGroup()
}

// Reports every chunk of the container with its identities, codec, sizes and checksums, each as a
// group spanning its stored payload.
private func reportSccChunks(report: *Report, chunks: const [..] Scc.ChunkInfo)
{
    let texts = texts()
    let total = countText(chunks.count, texts.word_Chunk, texts.word_Chunks)
    report.beginGroup(texts.scc_Chunks, total, "", open: true)

    for chunk in chunks
    {
        let identity = chunk.id.toString()
        let stored   = StrConv.toDisplaySize(chunk.storedSize)
        let codec    = sccCodecName(chunk.codecId)

        // The group covers the payload itself, so a search hit inside a chunk lands on that chunk.
        report.beginGroup(identity, stored, codec, offset: chunk.offset, length: chunk.storedSize)

        let typeId = chunk.typeId.toString()
        let roleId = chunk.roleId.toString()
        report.derived("TypeId", typeId)
        report.derived("RoleId", roleId)
        if not chunk.codecId.isNull()
        {
            let codecId = chunk.codecId.toString()
            report.derived("CodecId", codecId, codec)
        }

        let schema = Format.toString("%", chunk.schemaVersion)
        let names  = sccChunkFlagsText(chunk.flags)
        report.derived("SchemaVersion", schema)
        report.derived("Flags", names)
        report.hexField(chunk.offset, 8, "Offset", chunk.offset)
        report.sizeField(chunk.offset, 8, "StoredSize", chunk.storedSize)
        report.sizeField(chunk.offset, 8, "DecodedSize", chunk.decodedSize)

        let storedCrc  = hexText(cast(u64, chunk.storedChecksum), 8)
        let decodedCrc = hexText(cast(u64, chunk.decodedChecksum), 8)
        report.derived("StoredChecksum", storedCrc)
        report.derived("DecodedChecksum", decodedCrc)
        report.endGroup()
    }

    report.endGroup()
}

private func sccCodecName(codecId: Guid128)->string
{
    let texts = texts()
    if codecId.isNull() do
        return texts.scc_Stored
    if codecId == Scc.deflateCodecId() do
        return texts.scc_Deflate
    return texts.scc_Codec
}

private func sccChunkFlagsText(value: Scc.ChunkFlags)->String
{
    let names = [FlagName{1, "Required"},
                 FlagName{2, "Metadata"},
                 FlagName{4, "Streamable"},
                 FlagName{8, "PreserveUnknown"}]
    return flagsText(cast(u64, value), names)
}

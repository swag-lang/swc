#global internal

using Core

// Bytes every Swag Chunk Container begins with.
private const SccMagic = "SWAGSCC"

// Returns whether the file begins with the container signature.
func isSccContainer(image: *BinaryImage)->bool => image.matches(0, SccMagic) and image.u8At(7) == 0

// Adds the envelope, the manifest, and the chunk directory of a Swag Chunk Container.
//
// The prefix is read from the loaded bytes and the rest through the container reader, so a file
// whose header fails validation still shows the envelope that says why.
func reportSccContainer(image: *BinaryImage, report: *BinaryReport, fileName: string)
{
    image.bigEndian = false

    let s          = binStrings()
    let major      = image.u16At(8)
    let minor      = image.u16At(10)
    let headerSize = image.u64At(16)

    report.beginGroup(s.scc_Prefix, SccMagic, "", offset: 0, length: Scc.PrefixSize, open: true)
    report.field(8, 4, "Version", "", "")
    report.numField(8, 2, "FormatMajor", cast(u64) major)
    report.numField(10, 2, "FormatMinor", cast(u64) minor)
    report.hexField(12, 4, "Flags", cast(u64) image.u32At(12))
    report.sizeField(16, 8, "HeaderSize", headerSize)
    report.hexField(24, 4, "HeaderChecksum", cast(u64) image.u32At(24))
    report.field(Scc.PrefixSize, headerSize, "Header", "", s.scc_Manifest)
    report.endGroup()

    report.formatName = String.from("SCC")

    var reader: Scc.Reader
    catch reader.initialize(fileName) as openError
    if openError != null
    {
        report.note(s.scc_Unreadable)
        report.summary = Format.toString("SCC %.% · %", major, minor, s.scc_Unreadable)
        return
    }

    let identity   = reader.id().toString()
    let kind       = reader.kind().toString()
    let generation = reader.generation()

    report.beginGroup(s.scc_Container, identity.toString(), "", open: true)
    report.derived("ContainerKind", kind.toString())
    report.derived("ContainerId", identity.toString())
    let generationText = Format.toString("%", generation)
    report.derived("Generation", generationText.toString())
    report.endGroup()

    reportSccManifest(report, reader.manifest())
    reportSccChunks(report, reader.chunks())

    let chunks = countText(@countof(reader.chunks()), s.word_Chunk, s.word_Chunks)
    report.summary = Format.toString("SCC %.% · %", major, minor, chunks)
}

private func reportSccManifest(report: *BinaryReport, manifest: const *Scc.Manifest)
{
    let s = binStrings()
    report.beginGroup(s.scc_Manifest, manifest.name.toString(), "", open: true)

    let version = Format.toString("%", manifest.version)
    let profile = Format.toString("%", manifest.profileVersion)
    report.derived("Version", version.toString())
    report.derived("ProfileVersion", profile.toString())
    if !manifest.description.isEmpty() do
        report.derived("Description", manifest.description.toString())

    let created  = manifest.createdAt.toString(.DateTimeIso)
    let modified = manifest.modifiedAt.toString(.DateTimeIso)
    if manifest.createdAt.isValid() do
        report.derived(s.scc_Created, created.toString())
    if manifest.modifiedAt.isValid() do
        report.derived(s.scc_Modified, modified.toString())

    if !manifest.tags.isEmpty()
    {
        var joined: String
        for tag in manifest.tags
        {
            if !joined.isEmpty() do
                joined += ", "
            joined += tag.toString()
        }

        report.derived(s.scc_Tags, joined.toString())
    }

    if !manifest.profileData.isEmpty()
    {
        let stored = StrConv.toDisplaySize(manifest.profileData.count)
        report.derived(s.scc_Profile, stored.toString())
    }

    reportSccProperties(report, manifest.properties.toSlice())
    reportSccEntries(report, manifest.entries.toSlice())
    report.endGroup()
}

private func reportSccProperties(report: *BinaryReport, properties: const [..] Scc.Property)
{
    if !@countof(properties) do
        return

    let s     = binStrings()
    let total = countText(@countof(properties), s.word_Property, s.word_Properties)
    report.beginGroup(s.scc_Properties, total.toString(), "")

    for property in properties
    {
        let value = sccValueText(&property.value)
        report.derived(property.name.toString(), value.toString())
    }

    report.endGroup()
}

// Returns one typed metadata value in the reading its own kind calls for.
private func sccValueText(value: const *Scc.MetadataValue)->String
{
    switch value.kind
    {
    case .Text:     return String.from(value.textValue.toString())
    case .Signed:   return Format.toString("%", value.signedValue)
    case .Unsigned: return Format.toString("%", value.unsignedValue)
    case .Float:    return Format.toString("%", value.floatValue)
    case .Boolean:  return Format.toString("%", value.booleanValue)
    case .Bytes:    return StrConv.toDisplaySize(value.bytesValue.count)
    }

    return String.from(BinaryNoValue)
}

// Adds the virtual hierarchy the manifest declares, parents before the entries they own.
private func reportSccEntries(report: *BinaryReport, entries: const [..] Scc.Entry)
{
    if !@countof(entries) do
        return

    let s     = binStrings()
    let total = countText(@countof(entries), s.word_Entry, s.word_Entries)
    report.beginGroup(s.scc_Entries, total.toString(), "", open: true)

    for entry in entries
    {
        let kind = entry.kind == .Directory ? s.scc_Directory : s.scc_VirtualFile
        report.beginGroup(entry.name.toString(), kind, "")

        let identity = entry.id.toString()
        report.derived("Id", identity.toString())
        if !entry.parentId.isNull()
        {
            let parent = entry.parentId.toString()
            report.derived("ParentId", parent.toString())
        }

        if !entry.primaryChunk.isNull()
        {
            let chunk = entry.primaryChunk.toString()
            report.derived("PrimaryChunk", chunk.toString())
        }

        if !entry.variantChunks.isEmpty()
        {
            let variants = countText(entry.variantChunks.count, s.word_Chunk, s.word_Chunks)
            report.derived("VariantChunks", variants.toString())
        }

        reportSccProperties(report, entry.properties.toSlice())
        report.endGroup()
    }

    report.endGroup()
}

private func reportSccChunks(report: *BinaryReport, chunks: const [..] Scc.ChunkInfo)
{
    let s     = binStrings()
    let total = countText(@countof(chunks), s.word_Chunk, s.word_Chunks)
    report.beginGroup(s.scc_Chunks, total.toString(), "", open: true)

    for chunk in chunks
    {
        let identity = chunk.id.toString()
        let stored   = StrConv.toDisplaySize(chunk.storedSize)
        let codec    = sccCodecName(chunk.codecId)

        // The group covers the payload itself, so a search hit inside a chunk lands on that chunk.
        report.beginGroup(identity.toString(), stored.toString(), codec, offset: chunk.offset, length: chunk.storedSize)

        let typeId = chunk.typeId.toString()
        let roleId = chunk.roleId.toString()
        report.derived("TypeId", typeId.toString())
        report.derived("RoleId", roleId.toString())
        if !chunk.codecId.isNull()
        {
            let codecId = chunk.codecId.toString()
            report.derived("CodecId", codecId.toString(), codec)
        }

        let schema = Format.toString("%", chunk.schemaVersion)
        let names  = sccChunkFlagsText(chunk.flags)
        report.derived("SchemaVersion", schema.toString())
        report.derived("Flags", names.toString())
        report.hexField(chunk.offset, 8, "Offset", chunk.offset)
        report.sizeField(chunk.offset, 8, "StoredSize", chunk.storedSize)
        report.sizeField(chunk.offset, 8, "DecodedSize", chunk.decodedSize)

        let storedCrc  = hexText(cast(u64) chunk.storedChecksum, 8)
        let decodedCrc = hexText(cast(u64) chunk.decodedChecksum, 8)
        report.derived("StoredChecksum", storedCrc.toString())
        report.derived("DecodedChecksum", decodedCrc.toString())
        report.endGroup()
    }

    report.endGroup()
}

private func sccCodecName(codecId: Guid128)->string
{
    let s = binStrings()
    if codecId.isNull() do
        return s.scc_Stored
    if codecId == Scc.deflateCodecId() do
        return s.scc_Deflate
    return s.scc_Codec
}

private func sccChunkFlagsText(value: Scc.ChunkFlags)->String
{
    let names = [BinaryFlagName{1, "Required"},
                 BinaryFlagName{2, "Metadata"},
                 BinaryFlagName{4, "Streamable"},
                 BinaryFlagName{8, "PreserveUnknown"}]
    return flagsText(cast(u64) value, names)
}

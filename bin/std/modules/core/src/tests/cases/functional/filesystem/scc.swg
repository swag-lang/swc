#global if #command == Swag.CompilerCommand.Test
#global private

struct ReverseSccCodec
{
    codecId: Guid128
}

impl Scc.ICodec for ReverseSccCodec
{
    mtd impl id()->Guid128 => .codecId

    mtd impl encode(source: const [..] u8)->Array'u8 fail
    {
        var result: #returntype
        result.resize(source.count)
        for value, index in source do
            result[source.count - index - 1] = value
        return result
    }

    mtd impl decode(source: const [..] u8, decodedSize: u64)->Array'u8 fail
    {
        if source.count != decodedSize do
            fail Errors.InvalidFormatError{"reverse test codec received a different size"}
        return try .encode(source)
    }
}

func sccTestId(text: string)->Guid128 => expect Guid128.parse(text)

// The header and one selected chunk are sufficient; unrelated payload corruption is lazy.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_random_access.tmp")
    defer discard catch File.delete(path)

    let kind        = sccTestId("fc9456cf-5ec9-4710-bd12-b6bdd64a77a5")
    let previewRole = sccTestId("582e4036-ee6f-45b5-86d9-7972bb7e0a19")
    let imageRole   = sccTestId("b390ebc7-2563-4898-82ff-67cc398d7cd3")
    let bytesType   = sccTestId("679e4f35-8ef2-40b1-9af5-a0ddc03276df")
    let deflate     = Scc.deflateCodecId()

    var manifest: Scc.Manifest
    manifest.name = "Indexed document"
    manifest.tags.add("library")

    var writer: Scc.Writer
    writer.initialize(kind)
    writer.manifest()[] = #move manifest
    let previewId = expect writer.addChunk("small preview", {typeId: bytesType, roleId: previewRole, flags: .Required})

    var large: Array'u8
    large.resize(256 * 1024)
    for &value, index in large do
        value[] = cast(u8, (index & 0xFF))
    let imageId = expect writer.addChunk(large.toSlice(), {typeId: bytesType, roleId: imageRole, codecId: deflate})
    expect writer.saveAtomic(path)

    var imageOffset: u64
    scope
    {
        var index: Scc.Reader
        expect index.initialize(path)
        Swag.require(index.kind() == kind)
        Swag.require(index.manifest().name == "Indexed document")
        Swag.require((index.chunks()).count == 2)
        Swag.require(index.findRole(previewRole)!.id == previewId)
        imageOffset = index.findChunk(imageId)!.offset
    }

    var stream  = expect File.open(path, .Open, .ReadWrite, .Read)
    var damaged = 0xA5'u8
    expect stream.writeAllAt(imageOffset, Swag.makeSlice(&damaged, 1))
    stream.close()

    // Opening and reading the preview do not touch the damaged image payload.
    var reader: Scc.Reader
    expect reader.initialize(path)
    var preview = expect reader.readChunk(previewId)
    Swag.require(Slice.equals(preview.toSlice(), "small preview"))
    var damagedErrorOutcome: Swag.Error
    discard catch reader.readChunk(imageId) as damagedErrorOutcome
    let damagedError = damagedErrorOutcome.value()
    Swag.require(damagedError != null)
}

// Predefined Deflate and a caller-provided codec both round-trip independently.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_codecs.tmp")
    defer discard catch File.delete(path)

    let kind = sccTestId("c80a0567-314c-44dd-9370-20047131490e")
    let role = sccTestId("d31f4fd8-a007-4ed0-8561-e41dfe7e010d")
    let type = sccTestId("022eaea7-dbac-40c8-8100-399dd41bb0a2")

    let deflate = Scc.deflateCodecId()
    var custom  = ReverseSccCodec{codecId: sccTestId("9319fcf9-c8de-42aa-993a-06cb37a77e85")}
    var writer: Scc.Writer
    writer.initialize(kind)
    writer.registerCodec(&custom)
    let customId  = expect writer.addChunk("custom codec", {typeId: type, roleId: role, codecId: custom.codecId})
    let deflateId = expect writer.addChunk("deflate deflate deflate deflate", {typeId: type, roleId: role, codecId: deflate})
    expect writer.saveAtomic(path)

    var reader: Scc.Reader
    expect reader.initialize(path)
    var missingCodecOutcome: Swag.Error
    discard catch reader.readChunk(customId) as missingCodecOutcome
    let missingCodec = missingCodecOutcome.value()
    Swag.require(missingCodec != null)
    reader.registerCodec(&custom)

    let customBytes  = expect reader.readChunk(customId)
    let deflateBytes = expect reader.readChunk(deflateId)
    Swag.require(Slice.equals(customBytes.toSlice(), "custom codec"))
    Swag.require(Slice.equals(deflateBytes.toSlice(), "deflate deflate deflate deflate"))
}

// Stored chunks can be copied without knowing their codec; corruption is rejected before the
// destination writer accepts the chunk.
#test
{
    let sourcePath = CoreTests.makeFilesystemTestPath("core_scc_stored_source.tmp")
    let copyPath   = CoreTests.makeFilesystemTestPath("core_scc_stored_copy.tmp")
    defer
    {
        discard catch File.delete(sourcePath)
        discard catch File.delete(copyPath)
    }

    let kind = sccTestId("e6f71e08-c56a-4d70-a546-17b4b58b03c2")
    let role = sccTestId("d8993350-f65a-4992-ac77-600284eaaad6")
    let type = sccTestId("ecbc60fa-28d7-49e4-86b1-f6c1616fa26e")
    var codec = ReverseSccCodec{codecId: sccTestId("b9623a96-6cb1-4a35-9ec3-5a99a9c006a1")}

    var original: Scc.Writer
    original.initialize(kind)
    original.registerCodec(&codec)
    original.manifest().name = "Original metadata"
    let id = expect original.addChunk("payload for an unknown codec", {typeId: type, roleId: role, codecId: codec.codecId})
    expect original.saveAtomic(sourcePath)

    var source: Scc.Reader
    expect source.initialize(sourcePath)
    let info   = unwrap source.findChunk(id)
    let stored = expect source.readStoredChunk(id)

    var copy: Scc.Writer
    copy.initialize(kind)
    copy.setIdentity(source.id(), source.generation() + 1)
    copy.manifest()[] = source.manifest()[]
    copy.manifest().name = "Updated metadata"

    var damaged = stored
    damaged[0] = damaged[0] ^ 1
    var badChecksum: Swag.Error
    discard catch copy.addStoredChunk(damaged.toSlice(), info) as badChecksum
    Swag.require(badChecksum.value() != null)
    expect copy.addStoredChunk(stored.toSlice(), info)
    source.close()
    expect copy.saveAtomic(copyPath)

    var reopened: Scc.Reader
    expect reopened.initialize(copyPath)
    Swag.require(reopened.id() == source.id())
    Swag.require(reopened.generation() == source.generation() + 1)
    Swag.require(reopened.manifest().name == "Updated metadata")
    Swag.require(reopened.findChunk(id)!.codecId == codec.codecId)
    let copiedStored = expect reopened.readStoredChunk(id)
    Swag.require(Slice.equals(copiedStored.toSlice(), stored.toSlice()))
    reopened.registerCodec(&codec)
    let decoded = expect reopened.readChunk(id)
    Swag.require(Slice.equals(decoded.toSlice(), "payload for an unknown codec"))
}

// Header limits are enforced before the decoder allocates attacker-controlled sizes.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_limits.tmp")
    defer discard catch File.delete(path)

    var writer: Scc.Writer
    writer.initialize(sccTestId("a2866312-8a4d-49dd-97b0-17c91c8dfb65"))
    discard expect writer.addChunk("data", {})
    expect writer.saveAtomic(path)

    var limits: Scc.ReadLimits
    limits.maxHeaderSize = 1
    var reader: Scc.Reader
    var limitErrorOutcome: Swag.Error
    discard catch reader.initialize(path, limits) as limitErrorOutcome
    let limitError = limitErrorOutcome.value()
    Swag.require(limitError != null)
    expect File.delete(path)
}

// Empty containers remain valid and closing a reader releases the Windows file lock.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_empty.tmp")
    defer discard catch File.delete(path)

    var manifest: Scc.Manifest
    manifest.name = "Metadata only"
    var writer: Scc.Writer
    writer.initialize(sccTestId("0293583e-3019-4a79-9ba6-0678436dcf67"))
    writer.manifest()[] = #move manifest
    expect writer.saveAtomic(path)

    var reader: Scc.Reader
    expect reader.initialize(path)
    Swag.require(reader.manifest().name == "Metadata only")
    Swag.require((reader.chunks()).count == 0)
    reader.close()

    expect File.delete(path)
    Swag.require(not File.exists(path))
}

// The virtual hierarchy can group one logical file and its alternate representations.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_hierarchy.tmp")
    defer discard catch File.delete(path)

    var writer: Scc.Writer
    writer.initialize(sccTestId("ad14e4cc-b1eb-4b73-b655-77b246771976"))
    let png = expect writer.addChunk("png", {typeId: sccTestId("1b0c8d6a-e6b8-412f-8bd2-da8167f625d6")})
    let jpg = expect writer.addChunk("jpg", {typeId: sccTestId("e4c7db2f-a433-40bf-a0c2-3eac0ea981ff")})

    var folder: Scc.Entry
    folder.id   = sccTestId("e642cf23-a0d7-4c3c-a364-4285b3e69f95")
    folder.kind = .Directory
    folder.name = "images"
    writer.manifest().entries.add(folder)

    var image: Scc.Entry
    image.id           = sccTestId("90ba499a-c9e1-45fb-bbd2-65931544c0c3")
    image.parentId     = folder.id
    image.kind         = .File
    image.name         = "capture"
    image.primaryChunk = png
    image.variantChunks.add(jpg)
    writer.manifest().entries.add(image)
    expect writer.saveAtomic(path)

    var reader: Scc.Reader
    expect reader.initialize(path)
    Swag.require(reader.manifest().entries.count == 2)
    Swag.require(reader.manifest().entries[1].parentId == folder.id)
    Swag.require(reader.manifest().entries[1].variantChunks[0] == jpg)
}

// Invalid virtual references fail before an existing destination can be replaced.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_invalid_manifest.tmp")
    defer discard catch File.delete(path)
    expect File.writeAllBytes(path, "keep me")

    var writer: Scc.Writer
    writer.initialize(sccTestId("84fef8e9-d020-465b-8f4e-81ef18400ce9"))
    var entry: Scc.Entry
    entry.id           = sccTestId("0171e40a-07fa-4da9-b0b0-47cb7a95f676")
    entry.kind         = .File
    entry.primaryChunk = sccTestId("05438e64-524b-4ba7-ac81-794e80bf4733")
    writer.manifest().entries.add(entry)

    var invalidOutcome: Swag.Error
    discard catch writer.saveAtomic(path) as invalidOutcome
    let invalid = invalidOutcome.value()
    Swag.require(invalid != null)
    let bytes = expect File.readAllBytes(path)
    Swag.require(Slice.equals(bytes.toSlice(), "keep me"))
}

// Cyclic virtual-directory parents are rejected before the destination is replaced.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_parent_cycle.tmp")
    defer discard catch File.delete(path)
    expect File.writeAllText(path, "keep me")

    var first: Scc.Entry
    first.id       = sccTestId("31f70d3c-9bca-45da-8778-31cb33af6342")
    first.kind     = .Directory
    first.parentId = sccTestId("a6e29ee0-9f62-4e9b-bb0c-63972f34bb33")

    var second: Scc.Entry
    second.id       = first.parentId
    second.kind     = .Directory
    second.parentId = first.id

    var writer: Scc.Writer
    writer.initialize(sccTestId("9bc2db82-bfb6-4b85-98b2-6090f870e3cf"))
    writer.manifest().entries.add(first)
    writer.manifest().entries.add(second)

    var errorOutcome: Swag.Error
    discard catch writer.saveAtomic(path) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.InvalidFormatError)
    Swag.require((expect File.readAllText(path)) == "keep me")
}

// A writer cannot replace an existing file with a header that its Reader rejects.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_invalid_identity.tmp")
    defer discard catch File.delete(path)
    expect File.writeAllText(path, "keep me")

    var writer: Scc.Writer
    writer.initialize(sccTestId("6cfd74c7-00cb-428c-a6e6-bc817d8fdf8f"))
    discard expect writer.addChunk("payload", {})

    writer.setIdentity(Guid128{}, 1)
    var nullIdOutcome: Swag.Error
    discard catch writer.saveAtomic(path) as nullIdOutcome
    Swag.require(nullIdOutcome.value() is Errors.BadParameterError)
    Swag.require((expect File.readAllText(path)) == "keep me")

    writer.setIdentity(sccTestId("a4fe2ad0-71e9-4df8-aa9f-367c76d08d92"), 0)
    var zeroGenerationOutcome: Swag.Error
    discard catch writer.saveAtomic(path) as zeroGenerationOutcome
    Swag.require(zeroGenerationOutcome.value() is Errors.BadParameterError)
    Swag.require((expect File.readAllText(path)) == "keep me")
}

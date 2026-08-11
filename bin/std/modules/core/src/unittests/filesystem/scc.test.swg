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
        var result: retval
        result.resize(@countof(source))
        for value, index in source do
            result[@countof(source) - index - 1] = value
        return result
    }

    mtd impl decode(source: const [..] u8, decodedSize: u64)->Array'u8 fail
    {
        if @countof(source) != decodedSize do
            fail Errors.InvalidFormatError{"reverse test codec received a different size"}
        return .encode(source)
    }
}

func sccTestId(text: string)->Guid128 => expect Guid128.parse(text)

func sameSccBytes(left, right: const [..] u8)->bool
{
    return @countof(left) == @countof(right) and (!@countof(left) or @memcmp(@dataof(left), @dataof(right), @countof(left)) == 0)
}

// The header and one selected chunk are sufficient; unrelated payload corruption is lazy.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_scc_random_access.tmp")
    defer discard catch File.delete(path)

    let kind        = sccTestId("fc9456cf-5ec9-4710-bd12-b6bdd64a77a5")
    let previewRole = sccTestId("f53e06c1-05a7-4537-9c6a-d85609209874")
    let imageRole   = sccTestId("04267f4e-d659-4d32-9296-cc68be5bdb9d")
    let bytesType   = sccTestId("679e4f35-8ef2-40b1-9af5-a0ddc03276df")
    let deflate     = Scc.deflateCodecId()

    var manifest: Scc.Manifest
    manifest.name = "Indexed document"
    manifest.tags.add("library")

    var writer: Scc.Writer
    writer.initialize(kind)
    dref writer.manifest() = #move manifest
    let previewId = expect writer.addChunk("small preview", {typeId: bytesType, roleId: previewRole, flags: .Required})

    var large: Array'u8
    large.resize(256 * 1024)
    for &value, index in large do
        value = cast(u8) (index & 0xFF)
    let imageId = expect writer.addChunk(large.toSlice(), {typeId: bytesType, roleId: imageRole, codecId: deflate})
    expect writer.saveAtomic(path)

    var imageOffset: u64
    {
        var index: Scc.Reader
        expect index.initialize(path)
        @assert(index.kind() == kind)
        @assert(index.manifest().name == "Indexed document")
        @assert(@countof(index.chunks()) == 2)
        @assert(index.findRole(previewRole)!.id == previewId)
        imageOffset = index.findChunk(imageId)!.offset
    }

    var stream  = expect File.open(path, .Open, .ReadWrite, .Read)
    var damaged = 0xA5'u8
    expect stream.writeAllAt(imageOffset, @mkslice(&damaged, 1))
    stream.close()

    // Opening and reading the preview do not touch the damaged image payload.
    var reader: Scc.Reader
    expect reader.initialize(path)
    var preview = expect reader.readChunk(previewId)
    @assert(sameSccBytes(preview.toSlice(), "small preview"))
    discard catch reader.readChunk(imageId) as damagedError
    @assert(damagedError != null)
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
    discard catch reader.readChunk(customId) as missingCodec
    @assert(missingCodec != null)
    reader.registerCodec(&custom)

    let customBytes  = expect reader.readChunk(customId)
    let deflateBytes = expect reader.readChunk(deflateId)
    @assert(sameSccBytes(customBytes.toSlice(), "custom codec"))
    @assert(sameSccBytes(deflateBytes.toSlice(), "deflate deflate deflate deflate"))
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
    discard catch reader.initialize(path, limits) as limitError
    @assert(limitError != null)
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
    dref writer.manifest() = #move manifest
    expect writer.saveAtomic(path)

    var reader: Scc.Reader
    expect reader.initialize(path)
    @assert(reader.manifest().name == "Metadata only")
    @assert(@countof(reader.chunks()) == 0)
    reader.close()

    expect File.delete(path)
    @assert(!File.exists(path))
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
    @assert(reader.manifest().entries.count == 2)
    @assert(reader.manifest().entries[1].parentId == folder.id)
    @assert(reader.manifest().entries[1].variantChunks[0] == jpg)
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

    discard catch writer.saveAtomic(path) as invalid
    @assert(invalid != null)
    let bytes = expect File.readAllBytes(path)
    @assert(sameSccBytes(bytes.toSlice(), "keep me"))
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if actual.count != expected.count do
        return false

    for actual.count
    {
        if actual[Swag.index] != expected[Swag.index] do
            return false
    }

    return true
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_existing.tmp")

    discard expect File.writeAllBytes(fileName, ['a'u8, 'b'u8])
    {
        var stream = expect File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
        discard expect stream.write(("cd").buffer, 2)
        stream.close()
    }

    {
        let content = expect File.readAllBytes(fileName)
        Swag.assert(assertBytes(content.toSlice(), ['a'u8, 'b'u8, 'c'u8, 'd'u8]))
    }

    discard expect File.delete(fileName)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_random_access.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, File.FileMode.CreateNew, File.FileAccess.ReadWrite, File.FileShare.Read)
    expect stream.resize(32)
    Swag.assert(expect stream.size() == 32)
    Swag.assert(expect stream.position() == 0)

    let payload: [5] u8 = [1, 3, 5, 7, 9]
    expect stream.writeAllAt(11, payload)
    expect stream.flush()
    Swag.assert(expect stream.position() == 16)

    var recovered: [5] u8
    Swag.assert(expect stream.readExactAt(11, recovered))
    Swag.assert(assertBytes(recovered, payload))
    Swag.assert(expect stream.position() == 16)

    var beyond: [17] u8
    Swag.assert(!(expect stream.readExactAt(16, beyond)))

    expect stream.seek(.Begin, 8)
    expect stream.resize(12)
    Swag.assert(expect stream.position() == 8)
    expect stream.resize(4)
    Swag.assert(expect stream.position() == 4)
    Swag.assert(expect stream.size() == 4)
    stream.close()
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_utf8_chunks.tmp")
    defer discard catch File.delete(fileName)

    let content = "abcé◆xyz"
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) content.buffer, content.count))

    var stream = expect File.openRead(fileName)
    defer stream.close()

    var recovered: String
    while true
    {
        let chunk = expect stream.readUtf8Chunk(4)
        if chunk.isEmpty() do
            break
        Swag.assert(chunk.count <= 4)
        Swag.assert(Utf8.isValid(chunk.toSlice()))
        recovered += chunk
    }

    Swag.assert(recovered == content)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_invalid_utf8_chunk.tmp")
    defer discard catch File.delete(fileName)

    discard expect File.writeAllBytes(fileName, ['a'u8, 0xFF'u8, 'b'u8])
    var stream = expect File.openRead(fileName)
    defer stream.close()

    Swag.assert((expect stream.readUtf8Chunk(16)) == "a")
    discard catch stream.readUtf8Chunk(16) as err
    Swag.assert(err is Errors.InvalidFormatError)
    Swag.assert(expect stream.position() == 1)
}

// Offsets are 64-bit all the way down to the platform call. Everything from 2 GB upward has bit 31
// set, which a 32-bit signed distance cannot carry, so these are the offsets a container-sized file
// actually lives at. Seeking never allocates a byte, so the file stays empty throughout.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_large_offset.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, File.FileMode.CreateNew, File.FileAccess.ReadWrite, File.FileShare.Read)
    defer stream.close()

    let offsets: [4] u64 = [0x7FFF_FFFF, 0x8000_0000, 0x1_0000_0000, 0x3_1234_5678]
    for offset in offsets
    {
        expect stream.seek(.Begin, offset)
        Swag.assert(expect stream.position() == offset)
    }

    expect stream.seek(.Begin, 0x8000_0000)
    expect stream.skip(0x8000_0000)
    Swag.assert(expect stream.position() == 0x1_0000_0000)
    Swag.assert(expect stream.size() == 0)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_create.tmp")

    var stream = expect File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
    discard expect stream.write(("xy").buffer, 2)
    stream.close()

    let content = expect File.readAllBytes(fileName)
    Swag.assert(assertBytes(content.toSlice(), ['x'u8, 'y'u8]))

    discard expect File.delete(fileName)
}

#test
{
    let source = CoreTests.makeFilesystemTestPath("core_file_move_source.tmp")
    let target = CoreTests.makeFilesystemTestPath("core_file_move_target.tmp")

    defer
    {
        if File.exists(source.toString()) do
            discard catch File.delete(source.toString())
        if File.exists(target.toString()) do
            discard catch File.delete(target.toString())
    }

    discard expect File.writeAllBytes(source.toString(), Swag.makeSlice(cast(const [*] u8) ("moved").buffer, 5))
    expect File.move(target.toString(), source.toString())

    Swag.assert(!File.exists(source.toString()))
    Swag.assert(File.exists(target.toString()))
    Swag.assert((expect File.readAllText(target.toString())) == "moved")

    // Moving over an existing file replaces it rather than refusing.
    discard expect File.writeAllBytes(source.toString(), Swag.makeSlice(cast(const [*] u8) ("again").buffer, 5))
    expect File.move(target.toString(), source.toString())
    Swag.assert((expect File.readAllText(target.toString())) == "again")
}

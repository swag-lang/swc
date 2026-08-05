#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if @countof(actual) != @countof(expected) do
        return false

    for @countof(actual)
    {
        if actual[@index] != expected[@index] do
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
        discard expect stream.write(@dataof("cd"), 2)
        stream.close()
    }

    {
        let content = expect File.readAllBytes(fileName)
        @assert(assertBytes(content.toSlice(), ['a'u8, 'b'u8, 'c'u8, 'd'u8]))
    }

    discard expect File.delete(fileName)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_random_access.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, File.FileMode.CreateNew, File.FileAccess.ReadWrite, File.FileShare.Read)
    expect stream.resize(32)
    @assert(expect stream.size() == 32)
    @assert(expect stream.position() == 0)

    let payload: [5] u8 = [1, 3, 5, 7, 9]
    expect stream.writeAllAt(11, payload)
    expect stream.flush()
    @assert(expect stream.position() == 16)

    var recovered: [5] u8
    @assert(expect stream.readExactAt(11, recovered))
    @assert(assertBytes(recovered, payload))
    @assert(expect stream.position() == 16)

    var beyond: [17] u8
    @assert(!(expect stream.readExactAt(16, beyond)))

    expect stream.seek(.Begin, 8)
    expect stream.resize(12)
    @assert(expect stream.position() == 8)
    expect stream.resize(4)
    @assert(expect stream.position() == 4)
    @assert(expect stream.size() == 4)
    stream.close()
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
        @assert(expect stream.position() == offset)
    }

    expect stream.seek(.Begin, 0x8000_0000)
    expect stream.skip(0x8000_0000)
    @assert(expect stream.position() == 0x1_0000_0000)
    @assert(expect stream.size() == 0)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_create.tmp")

    var stream = expect File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
    discard expect stream.write(@dataof("xy"), 2)
    stream.close()

    let content = expect File.readAllBytes(fileName)
    @assert(assertBytes(content.toSlice(), ['x'u8, 'y'u8]))

    discard expect File.delete(fileName)
}

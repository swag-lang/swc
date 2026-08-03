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

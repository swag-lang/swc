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

    discard catch File.writeAllBytes(fileName, ['a'u8, 'b'u8]) as err
    @assert(err == null)

    {
        var stream = catch File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero) as err2
        @assert(err2 == null)

        discard catch stream.write(@dataof("cd"), 2) as err3
        @assert(err3 == null)
        stream.close()
    }

    {
        let content = catch File.readAllBytes(fileName) as err4
        @assert(err4 == null)
        @assert(assertBytes(content.toSlice(), ['a'u8, 'b'u8, 'c'u8, 'd'u8]))
    }

    discard catch File.delete(fileName) as err5
    @assert(err5 == null)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_create.tmp")

    var stream = catch File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero) as err6
    @assert(err6 == null)

    discard catch stream.write(@dataof("xy"), 2) as err7
    @assert(err7 == null)
    stream.close()

    let content = catch File.readAllBytes(fileName) as err8
    @assert(err8 == null)
    @assert(assertBytes(content.toSlice(), ['x'u8, 'y'u8]))

    discard catch File.delete(fileName) as err9
    @assert(err9 == null)
}

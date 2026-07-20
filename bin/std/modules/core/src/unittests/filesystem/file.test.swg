#global #if #command == Swag.CompilerCommand.Test
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

    discard catch File.writeAllBytes(fileName, ['a''u8, 'b''u8])
    @assert(@err == null)

    {
        var stream = catch File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
        @assert(@err == null)

        discard catch stream.write(@dataof("cd"), 2)
        @assert(@err == null)
        stream.close()
    }

    {
        let content = catch File.readAllBytes(fileName)
        @assert(@err == null)
        @assert(assertBytes(content.toSlice(), ['a''u8, 'b''u8, 'c''u8, 'd''u8]))
    }

    discard catch File.delete(fileName)
    @assert(@err == null)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_create.tmp")

    var stream = catch File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
    @assert(@err == null)

    discard catch stream.write(@dataof("xy"), 2)
    @assert(@err == null)
    stream.close()

    let content = catch File.readAllBytes(fileName)
    @assert(@err == null)
    @assert(assertBytes(content.toSlice(), ['x''u8, 'y''u8]))

    discard catch File.delete(fileName)
    @assert(@err == null)
}

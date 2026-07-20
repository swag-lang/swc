#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertString(value: const &String, expected: #nonull string)->bool
{
    return value == expected and @countof(value) == @countof(expected)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_utf8_bom.tmp")

    let payload: [7] u8 = [0xEF, 0xBB, 0xBF, 'c''u8, 'o''u8, 'r''u8, 'e''u8]
    discard catch File.writeAllBytes(fileName, payload)
    @assert(@err == null)

    var reader: File.TextReader
    discard catch reader.open(fileName)
    @assert(@err == null)

    let content = reader.readToEnd()
    @assert(assertString(content, "core"))

    reader.close()

    discard catch File.delete(fileName)
    @assert(@err == null)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_lines.tmp")

    let payload: [21] u8 = [0xEF, 0xBB, 0xBF, 'a''u8, 'l''u8, 'p''u8, 'h''u8, 'a''u8, '\r''u8, '\n''u8, 'b''u8, 'e''u8, 't''u8, 'a''u8, '\n''u8, '\n''u8, 'g''u8, 'a''u8, 'm''u8, 'm''u8, 'a''u8]
    discard catch File.writeAllBytes(fileName, payload)
    @assert(@err == null)

    let lines = catch File.readAllLines(fileName)
    @assert(@err == null)
    @assert(lines.count == 4)
    @assert(assertString(lines[0], "alpha"))
    @assert(assertString(lines[1], "beta"))
    @assert(assertString(lines[2], ""))
    @assert(assertString(lines[3], "gamma"))

    discard catch File.delete(fileName)
    @assert(@err == null)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_foreach_temp.tmp")

    var content: String
    for 40 do
        content += "2x3x4\n"

    discard catch File.writeAllBytes(fileName, content.toSlice())
    @assert(@err == null)

    var lineCount = 0
    var totalSize = 0'u64
    assume
    {
        for line in File.readAllLines(fileName)
        {
            lineCount += 1
            totalSize += @countof(line)
        }
    }

    @assert(lineCount == 40)
    @assert(totalSize == 200)

    discard catch File.delete(fileName)
    @assert(@err == null)
}

#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertString(value: const &String, expected: string)->bool
{
    return value == expected and @countof(value) == @countof(expected)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_utf8_bom.tmp")

    let payload: [7] u8 = [0xEF, 0xBB, 0xBF, 'c''u8, 'o''u8, 'r''u8, 'e''u8]
    discard catch File.writeAllBytes(fileName, payload) as err
    @assert(err == null)

    var reader: File.TextReader
    discard catch reader.open(fileName) as err2
    @assert(err2 == null)

    let content = reader.readToEnd()
    @assert(assertString(content, "core"))

    reader.close()

    discard catch File.delete(fileName) as err3
    @assert(err3 == null)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_lines.tmp")

    let payload: [21] u8 = [0xEF, 0xBB, 0xBF, 'a''u8, 'l''u8, 'p''u8, 'h''u8, 'a''u8, '\r''u8, '\n''u8, 'b''u8, 'e''u8, 't''u8, 'a''u8, '\n''u8, '\n''u8, 'g''u8, 'a''u8, 'm''u8, 'm''u8, 'a''u8]
    discard catch File.writeAllBytes(fileName, payload) as err4
    @assert(err4 == null)

    let lines = catch File.readAllLines(fileName) as err5
    @assert(err5 == null)
    @assert(lines.count == 4)
    @assert(assertString(lines[0], "alpha"))
    @assert(assertString(lines[1], "beta"))
    @assert(assertString(lines[2], ""))
    @assert(assertString(lines[3], "gamma"))

    discard catch File.delete(fileName) as err6
    @assert(err6 == null)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_foreach_temp.tmp")

    var content: String
    for 40 do
        content += "2x3x4\n"

    discard catch File.writeAllBytes(fileName, content.toSlice()) as err7
    @assert(err7 == null)

    var lineCount = 0
    var totalSize = 0'u64
    expect
    {
        for line in File.readAllLines(fileName)
        {
            lineCount += 1
            totalSize += @countof(line)
        }
    }

    @assert(lineCount == 40)
    @assert(totalSize == 200)

    discard catch File.delete(fileName) as err8
    @assert(err8 == null)
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertString(value: String, expected: string)->bool
{
    return value == expected and value.count == expected.count
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_utf8_bom.tmp")

    let payload: [7] u8 = [0xEF, 0xBB, 0xBF, 'c'u8, 'o'u8, 'r'u8, 'e'u8]
    discard expect File.writeAllBytes(fileName, payload)
    var reader: File.TextReader
    discard expect reader.open(fileName)
    let content = expect reader.readToEnd()
    Swag.assert(assertString(content, "core"))

    reader.close()

    discard expect File.delete(fileName)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_lines.tmp")

    let payload: [21] u8 = [0xEF, 0xBB, 0xBF, 'a'u8, 'l'u8, 'p'u8, 'h'u8, 'a'u8, '\r'u8, '\n'u8, 'b'u8, 'e'u8, 't'u8, 'a'u8, '\n'u8, '\n'u8, 'g'u8, 'a'u8, 'm'u8, 'm'u8, 'a'u8]
    discard expect File.writeAllBytes(fileName, payload)
    let lines = expect File.readAllLines(fileName)
    Swag.assert(lines.count == 4)
    Swag.assert(assertString(lines[0], "alpha"))
    Swag.assert(assertString(lines[1], "beta"))
    Swag.assert(assertString(lines[2], ""))
    Swag.assert(assertString(lines[3], "gamma"))

    discard expect File.delete(fileName)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_foreach_temp.tmp")

    var content: String
    for 40 do
        content += "2x3x4\n"

    discard expect File.writeAllBytes(fileName, content.toSlice())
    var lineCount = 0
    var totalSize = 0'u64
    expect
    {
        for line in File.readAllLines(fileName)
        {
            lineCount += 1
            totalSize += line.count
        }
    }

    Swag.assert(lineCount == 40)
    Swag.assert(totalSize == 200)

    discard expect File.delete(fileName)
}

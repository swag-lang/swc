#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A leading UTF-8 byte-order mark is not part of the text.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_utf8_bom.tmp")
    defer discard catch File.delete(fileName)

    let payload: [7] u8 = [0xEF, 0xBB, 0xBF, 'c'u8, 'o'u8, 'r'u8, 'e'u8]
    discard expect File.writeAllBytes(fileName, payload)

    var reader: File.TextReader
    expect reader.open(fileName)
    defer reader.close()
    let content = expect reader.readToEnd()
    Swag.assert(content == "core")
}

// Lines end with '\n', '\r\n', or the end of the file, and keep no end-of-line character.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_lines.tmp")
    defer discard catch File.delete(fileName)

    let payload: [21] u8 = [0xEF, 0xBB, 0xBF, 'a'u8, 'l'u8, 'p'u8, 'h'u8, 'a'u8, '\r'u8, '\n'u8, 'b'u8, 'e'u8, 't'u8, 'a'u8, '\n'u8, '\n'u8, 'g'u8, 'a'u8, 'm'u8, 'm'u8, 'a'u8]
    discard expect File.writeAllBytes(fileName, payload)

    let lines = expect File.readAllLines(fileName)
    Swag.assert(lines.count == 4)
    Swag.assert(lines[0] == "alpha")
    Swag.assert(lines[1] == "beta")
    Swag.assert(lines[2] == "")
    Swag.assert(lines[3] == "gamma")
}

// Text written by writeAllText reads back unchanged, whole or line by line.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_roundtrip.tmp")
    defer discard catch File.delete(fileName)

    var content: String
    for 40 do
        content += "2x3x4\n"
    Swag.assert(expect File.writeAllText(fileName, content) == 240)

    let text = expect File.readAllText(fileName)
    Swag.assert(text == content)

    var lineCount = 0
    var totalSize = 0'u64
    expect File.readEachLine(fileName)
    {
        lineCount += 1
        totalSize += line.length
    }

    Swag.assert(lineCount == 40)
    Swag.assert(totalSize == 200)
}

// Normalizing line endings turns '\r\n' into '\n' and terminates the last line.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_normalize.tmp")
    defer discard catch File.delete(fileName)

    discard expect File.writeAllText(fileName, "one\r\ntwo")
    let text = expect File.readAllText(fileName, normalizeEol: true)
    Swag.assert(text == "one\ntwo\n")
}

// A reader can be opened again once closed, on another file, and reads that file from its start.
#test
{
    let first  = CoreTests.makeFilesystemTestPath("core_textreader_reopen_first.tmp")
    let second = CoreTests.makeFilesystemTestPath("core_textreader_reopen_second.tmp")
    defer discard catch File.delete(first)
    defer discard catch File.delete(second)
    discard expect File.writeAllText(first, "first\nline\n")
    discard expect File.writeAllText(second, "second\n")

    var reader: File.TextReader
    var line:   String
    expect reader.open(first)
    Swag.assert(expect reader.readLine(&line))
    Swag.assert(line == "first")
    reader.close()

    expect reader.open(second)
    defer reader.close()
    Swag.assert(expect reader.readLine(&line))
    Swag.assert(line == "second")
}

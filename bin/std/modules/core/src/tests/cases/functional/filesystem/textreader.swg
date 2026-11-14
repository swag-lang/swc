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
    Swag.require(content == "core")
}

// Lines end with '\n', '\r\n', or the end of the file, and keep no end-of-line character.
// The BOM and first CRLF leave the next long-word scan at an unaligned byte offset.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_lines.tmp")
    defer discard catch File.delete(fileName)

    let payload: [21] u8 = [0xEF, 0xBB, 0xBF, 'a'u8, 'l'u8, 'p'u8, 'h'u8, 'a'u8, '\r'u8, '\n'u8, 'b'u8, 'e'u8, 't'u8, 'a'u8, '\n'u8, '\n'u8, 'g'u8, 'a'u8, 'm'u8, 'm'u8, 'a'u8]
    discard expect File.writeAllBytes(fileName, payload)

    let lines = expect File.readAllLines(fileName)
    Swag.require(lines.count == 4)
    Swag.require(lines[0] == "alpha")
    Swag.require(lines[1] == "beta")
    Swag.require(lines[2] == "")
    Swag.require(lines[3] == "gamma")
}

// Text written by writeAllText reads back unchanged, whole or line by line.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_roundtrip.tmp")
    defer discard catch File.delete(fileName)

    var content: String
    for 40 do
        content += "2x3x4\n"
    Swag.require(expect File.writeAllText(fileName, content) == 240)

    let text = expect File.readAllText(fileName)
    Swag.require(text == content)

    var lineCount = 0
    var totalSize = 0'u64
    expect File.readEachLine(fileName)
    {
        lineCount += 1
        totalSize += line.length
    }

    Swag.require(lineCount == 40)
    Swag.require(totalSize == 200)
}

// Normalizing line endings turns '\r\n' into '\n' and terminates the last line.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_normalize.tmp")
    defer discard catch File.delete(fileName)

    discard expect File.writeAllText(fileName, "one\r\ntwo")
    let text = expect File.readAllText(fileName, normalizeEol: true)
    Swag.require(text == "one\ntwo\n")
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
    Swag.require(expect reader.readLine(&line))
    Swag.require(line == "first")
    reader.close()

    expect reader.open(second)
    defer reader.close()
    Swag.require(expect reader.readLine(&line))
    Swag.require(line == "second")
}

// TextReader rejects malformed UTF-8 in a line and in an unterminated final line.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_invalid_utf8.tmp")
    defer discard catch File.delete(fileName)

    discard expect File.writeAllBytes(fileName, ['a'u8, 0xFF, '\n'u8])
    var reader: File.TextReader
    expect reader.open(fileName)
    defer reader.close()

    var line:      String
    var lineError: Swag.Error
    discard catch reader.readLine(&line) as lineError
    Swag.require(lineError.value() is Errors.InvalidFormatError)

    reader.close()
    discard expect File.writeAllBytes(fileName, ['a'u8, 0xC3])
    expect reader.open(fileName)

    var textError: Swag.Error
    discard catch reader.readToEnd() as textError
    Swag.require(textError.value() is Errors.InvalidFormatError)
}

// A CR at the end of the 64 KiB read window consumes a following LF from the next refill.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_textreader_crlf_refill.tmp")
    defer discard catch File.delete(fileName)

    var payload: [64 * 1024 + 5] u8
    for index in 64 * 1024 - 1 do
        payload[index] = 'a'u8
    payload[64 * 1024 - 1] = '\r'u8
    payload[64 * 1024]     = '\n'u8
    Memory.copy(payload.buffer + 64 * 1024 + 1, "tail".buffer, 4)
    discard expect File.writeAllBytes(fileName, payload)

    var reader: File.TextReader
    expect reader.open(fileName)
    defer reader.close()

    var line: String
    Swag.require(expect reader.readLine(&line))
    Swag.require(line.length == 64 * 1024 - 1)
    Swag.require(line[0] == 'a' and line[line.length - 1] == 'a')
    Swag.require(expect reader.readLine(&line) and line == "tail")
    let hasMoreLines = expect reader.readLine(&line)
    Swag.require(not hasMoreLines)
}

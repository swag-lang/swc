#global if #command == Swag.CompilerCommand.Test
#global private

// A pair straddling the requested segment stays together in either UTF-16 byte order.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_utf16_segment_boundary.tmp")
    defer discard catch File.delete(fileName)

    for encoding in [Text.Encoding.Utf16Le, .Utf16Be]
    {
        var bytes: [8] u8 = ['A', 0, 0x3D, 0xD8, 0x00, 0xDE, 'B', 0]
        if encoding == .Utf16Be
        {
            for index in 4 do
                swap(&bytes[index * 2], &bytes[index * 2 + 1])
        }

        discard expect File.writeAllBytes(fileName, bytes)
        var stream = expect File.openRead(fileName)
        defer stream.close()

        // Five requested bytes are rounded to two complete UTF-16 units.
        let first = expect stream.readTextChunk(5, encoding)
        Swag.assert(first == "A")
        Swag.assert(expect stream.position() == 2)

        let pair = expect stream.readTextChunk(5, encoding)
        Swag.assert(pair == "\U0001F600")
        Swag.assert(expect stream.position() == 6)

        let last = expect stream.readTextChunk(5, encoding)
        Swag.assert(last == "B")
        Swag.assert(expect stream.position() == bytes.count)
        let end = expect stream.readTextChunk(5, encoding)
        Swag.assert(end.isEmpty())
    }
}

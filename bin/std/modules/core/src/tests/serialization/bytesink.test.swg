#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core.Errors

func sinkBytesEqual(actual: const [..] u8, expected: const [..] u8)->bool
{
    if actual.count != expected.count do
        return false
    for value, index in actual where value != expected[index] do
        return false
    return true
}

// Returns a payload larger than the write window, filled with a pattern a misplaced write breaks.
func sinkLargePayload()->Array'u8
{
    var result: retval
    result.resize(ByteSink.WindowSize + 321)
    for index in result.count do
        result[index] = cast(u8) ((index * 13 + 5) & 0xFF)
    return result
}

// Writes one stream through `sink` and returns the bytes the stream must end up holding.
//
// Small pieces, typed values, a payload that bypasses the window, and two patches — one while
// the header still sits in the window, one after a large write forced it to the file — cover
// every path a container encoder takes.
func writeSinkStream(sink: *ByteSink)->Array'u8
{
    var expected: retval

    expect sink.writeText("RIFF")
    expected.add(cast(const [..] u8) "RIFF")
    let sizeField = sink.position()
    expect sink.writeLittleEndian(0'u32)
    expected.add([0'u8, 0, 0, 0])
    expect sink.writeBigEndian(0x1234'u16)
    expected.add([0x12'u8, 0x34])
    expect sink.writeByte(0xEE)
    expected.add(0xEE'u8)

    // The patch lands while the header is still in the write window.
    const FirstPatch: [4] u8 = [9, 8, 7, 6]
    expect sink.patch(sizeField, FirstPatch)
    for value, index in FirstPatch do
        expected[sizeField + index] = value
    Swag.assert(sink.position() == 11)

    let payload = sinkLargePayload()
    expect sink.write(payload.toSlice())
    expected.add(payload.toSlice())
    Swag.assert(sink.position() == expected.count)

    // The patch now lands in what the file already holds, and appending resumes after it.
    const SecondPatch: [4] u8 = [1, 2, 3, 4]
    expect sink.patch(sizeField, SecondPatch)
    for value, index in SecondPatch do
        expected[sizeField + index] = value
    expect sink.writeText("END")
    expected.add(cast(const [..] u8) "END")
    Swag.assert(sink.position() == expected.count)

    // A patch cannot reach past what was written, and an empty one changes nothing.
    const Overrun: [3] u8 = [0, 0, 0]
    discard catch sink.patch(expected.count - 2, Overrun) as pastEnd
    Swag.assert(pastEnd is BadParameterError)
    var none: Array'u8
    expect sink.patch(expected.count, none.toSlice())
    return expected
}

// A file sink holds one window and produces exactly the stream that was written to it.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("bytesink_stream.bin")
    defer discard catch File.delete(fileName)

    var sink = expect ByteSink.createFile(fileName.toString())
    Swag.assert(sink.path() == fileName.toString())
    let expected = writeSinkStream(&sink)
    expect sink.close()
    expect sink.close()

    let actual = expect File.readAllBytes(fileName)
    Swag.assert(sinkBytesEqual(actual.toSlice(), expected.toSlice()))
}

// A memory sink appends after whatever its buffer already holds, and its offsets stay relative
// to the first byte it wrote, so the same encoder produces the same stream on both backings.
#test
{
    var buffer: ConcatBuffer
    buffer.addBytes(cast(const [..] u8) "prefix")

    var sink = ByteSink.createMemory(&buffer)
    Swag.assert(!(sink.path()).count)
    let expected = writeSinkStream(&sink)
    expect sink.close()

    let actual = buffer.toArray()
    Swag.assert(actual.count == 6 + expected.count)
    Swag.assert(sinkBytesEqual(actual.toSlice()[0 until 6], cast(const [..] u8) "prefix"))
    Swag.assert(sinkBytesEqual(actual.toSlice()[6 until actual.count], expected.toSlice()))
}

// A struct is written as it is laid out, and a flush hands the window to the file without
// closing it, so writing goes on afterwards and the stream still ends up complete.
#test
{
    struct Header
    {
        tag:  u8
        size: u8
    }

    let fileName = CoreTests.makeFilesystemTestPath("bytesink_flush.bin")
    defer discard catch File.delete(fileName)

    var sink = expect ByteSink.createFile(fileName.toString())
    expect sink.writeNative(Header{7, 9})
    expect sink.flush()
    Swag.assert(sink.position() == 2)
    expect sink.writeByte(3)
    expect sink.close()

    let actual = expect File.readAllBytes(fileName)
    Swag.assert(sinkBytesEqual(actual.toSlice(), [7'u8, 9, 3]))
}

// A memory sink appends even when the caller previously moved its buffer cursor backwards.
#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("prefix")
    buffer.addBytes(" kept")
    buffer.setPosition({})
    buffer.advance(2)

    var sink = ByteSink.createMemory(&buffer)
    expect sink.writeText("data")
    expect sink.patch(1, cast(const [..] u8) "XY")
    expect sink.writeByte('!'u8)
    expect sink.close()
    Swag.assert(buffer.toString() == "prefix keptdXYa!")
    Swag.assert(sink.position() == 5)
}

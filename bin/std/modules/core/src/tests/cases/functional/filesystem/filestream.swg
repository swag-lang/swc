#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Exact reads distinguish a complete value from a short read at the end of the file.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_filestream_exact.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, .CreateNew, .ReadWrite, .Read)
    defer stream.close()

    var expected: u32 = 0x1234_5678
    let bytes         = Swag.makeSlice(cast(const [*] u8, &expected), #sizeof(u32))
    expect stream.writeAll(bytes)
    expect stream.flush()
    Swag.require(expect stream.position() == #sizeof(u32))

    expect stream.seek(.Begin, 0)
    var value: u32
    Swag.require(expect stream.readValue(&value))
    Swag.require(value == expected)

    expect stream.seek(.Begin, 0)
    var recovered: [4] u8
    Swag.require(expect stream.readExact(recovered))
    Swag.require(Slice.equals(recovered, bytes))

    expect stream.seek(.Begin, 2)
    var partial: [3] u8
    Swag.require(not (expect stream.readExact(partial)))
    Swag.require(expect stream.position() == #sizeof(u32))
}

// Offset reads and writes leave the cursor immediately after the transferred bytes.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_filestream_at.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, .CreateNew, .ReadWrite, .Read)
    defer stream.close()

    let initial: [4] u8 = [0x10, 0x20, 0x30, 0x40]
    expect stream.writeAll(initial)
    expect stream.writeAllAt(1, [0xAA'u8, 0xBB])
    Swag.require(expect stream.position() == 3)

    var pair: [2] u8
    Swag.require(expect stream.readExactAt(1, pair))
    Swag.require(Slice.equals(pair, [0xAA'u8, 0xBB]))
    Swag.require(expect stream.position() == 3)

    var tail: [3] u8
    Swag.require(not (expect stream.readExactAt(2, tail)))
    Swag.require(tail[0] == 0xBB and tail[1] == 0x40)
    Swag.require(expect stream.position() == 4)
}

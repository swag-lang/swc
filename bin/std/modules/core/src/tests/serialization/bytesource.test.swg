#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core.Errors

// The byte the stream fixture holds at `index`, chosen so a read landing one byte off is caught.
func sourcePattern(index: u64)->u8 => cast(u8) ((index * 7 + 3) & 0xFF)

func sourceMatches(bytes: const [..] u8, start: u64)->bool
{
    for value, index in bytes where value != sourcePattern(start + index) do
        return false
    return true
}

// A non-null slice has no fallback for `expect`, so a test peeks through this nullable adapter.
func peekBytes(source: *ByteSource, count: u64)->const [..] u8? fail => source.peek(count)

// Writes a fixture of `count` pattern bytes and returns its path.
func writeSourceFixture(name: string, count: u64)->String
{
    var bytes: Array'u8
    bytes.resize(count)
    for index in count do
        bytes[index] = sourcePattern(index)

    let fileName = CoreTests.makeFilesystemTestPath(name)
    discard expect File.writeAllBytes(fileName, bytes.toSlice())
    return fileName
}

// A memory source is a cursor over borrowed bytes: every positioning operation and every read
// answers from the slice, and a peek returns everything that remains.
#test
{
    const Bytes: [8] u8 = [1, 2, 3, 4, 5, 6, 7, 8]
    var source = ByteSource.openMemory(Bytes)
    Swag.assert(source.isOpen())
    Swag.assert(not (source.path()).count)
    Swag.assert(source.size() == 8 and source.position() == 0 and source.remaining() == 8)
    Swag.assert(not source.isAtEnd())

    Swag.assert(expect source.readByte() == 1)
    expect source.skip(2)
    var pair: [2] u8
    expect source.readExact(pair)
    Swag.assert(pair[0] == 4 and pair[1] == 5)
    Swag.assert(source.position() == 5)

    let rest = expect peekBytes(&source, 1)!
    Swag.assert(rest.count == 3 and rest[0] == 6 and rest[2] == 8)
    Swag.assert(source.position() == 5)

    expect source.seek(8)
    Swag.assert(source.isAtEnd() and not source.remaining())

    // At the end there is nothing to peek at, and asking for nothing is not an error.
    discard expect peekBytes(&source, 0)

    discard catch source.readByte() as pastEnd
    Swag.assert(pastEnd is InvalidFormatError)
    discard catch source.seek(9) as pastSeek
    Swag.assert(pastSeek is InvalidFormatError)
    discard catch peekBytes(&source, 1) as pastPeek
    Swag.assert(pastPeek is InvalidFormatError)
    expect source.seek(6)
    discard catch source.skip(3) as pastSkip
    Swag.assert(pastSkip is InvalidFormatError)

    // An at-most read stops at the end and reports how much it delivered.
    var tail: [8] u8
    Swag.assert(expect source.read(tail) == 2)
    Swag.assert(tail[0] == 7 and tail[1] == 8)
    Swag.assert(not (expect source.read(tail)))

    source.close()
    Swag.assert(not source.isOpen() and not source.size())
    source.close()
}

// Typed reads take the declared byte order, not the host's, and a struct reads as it is laid out.
#test
{
    struct Header
    {
        tag:  u8
        size: u8
    }

    const Bytes: [8] u8 = [0x34, 0x12, 0xAA, 0xBB, 0xCC, 0xDD, 7, 9]
    var source = ByteSource.openMemory(Bytes)
    Swag.assert(expect source.readLittleEndian'u16() == 0x1234)
    Swag.assert(expect source.readBigEndian'u32() == 0xAABBCCDD)
    let header = expect source.readNative'Header()
    Swag.assert(header.tag == 7 and header.size == 9)
    Swag.assert(source.isAtEnd())
}

// A line ends at a line feed whichever end-of-line convention wrote it, and a line that never
// ends is refused at its bound rather than read to the end of the stream.
#test
{
    let text   = "first\r\nsecond\nunterminated"
    var source = ByteSource.openMemory(cast(const [..] u8) text)
    Swag.assert(expect source.readLine(16) == "first")
    Swag.assert(expect source.readLine(16) == "second")
    Swag.assert(source.position() == 14)

    discard catch source.readLine(4) as tooLong
    Swag.assert(tooLong is InvalidFormatError)
    expect source.seek(14)
    discard catch source.readLine(64) as noTerminator
    Swag.assert(noTerminator is InvalidFormatError)
}

// A file source reads through one window: reads that cross its edges, reads that skip it
// because they are larger than it, and reads after a seek all return the bytes of the file.
#test
{
    const Count = 3 * ByteSource.WindowSize + 1234
    let fileName = writeSourceFixture("bytesource_window.bin", Count)
    defer discard catch File.delete(fileName)

    var source = expect ByteSource.openFile(fileName.toString())
    Swag.assert(source.isOpen())
    Swag.assert(source.path() == fileName.toString())
    Swag.assert(source.size() == Count)

    // Small reads walk across the first window boundary one hundred bytes at a time.
    var small: [100] u8
    var at = 0'u64
    while at + 100 <= ByteSource.WindowSize + 500
    {
        expect source.readExact(small)
        Swag.assert(sourceMatches(small, at))
        at += 100
    }

    Swag.assert(source.position() == at)

    // A read larger than the window bypasses it and lands where the position says.
    var large: Array'u8
    large.resize(ByteSource.WindowSize + 77)
    expect source.readExact(large.toSlice())
    Swag.assert(sourceMatches(large.toSlice(), at))
    at += large.count
    Swag.assert(source.position() == at)

    // The window is stale after the bypass, and a small read right after it still answers.
    expect source.readExact(small)
    Swag.assert(sourceMatches(small, at))

    // Seeking anywhere reads what is there, including the last byte of the file.
    expect source.seek(Count - 1)
    Swag.assert(expect source.readByte() == sourcePattern(Count - 1))
    Swag.assert(source.isAtEnd())
    expect source.seek(12345)
    Swag.assert(expect source.readByte() == sourcePattern(12345))

    // An at-most read at the tail returns the bytes that remain.
    expect source.seek(Count - 10)
    Swag.assert(expect source.read(small) == 10)
    Swag.assert(sourceMatches(small[0 until 10], Count - 10))

    source.close()
    Swag.assert(not source.isOpen())
}

// A peek on a file source answers at least what was asked for and reads ahead as far as the
// window goes, refills only when the request leaves the window, and grows the window when the
// request is larger than it.
#test
{
    const Count = 2 * ByteSource.WindowSize + 999
    let fileName = writeSourceFixture("bytesource_peek.bin", Count)
    defer discard catch File.delete(fileName)

    var source = expect ByteSource.openFile(fileName.toString())

    let head = expect peekBytes(&source, 16)!
    Swag.assert(head.count == ByteSource.WindowSize)
    Swag.assert(sourceMatches(head, 0))
    Swag.assert(source.position() == 0)

    // A scanner that advances inside the window keeps reading the same fill.
    expect source.skip(1000)
    let inside = expect peekBytes(&source, 16)!
    Swag.assert(inside.count == ByteSource.WindowSize - 1000)
    Swag.assert(sourceMatches(inside, 1000))

    // A request that leaves the window refills it from the read position.
    expect source.seek(ByteSource.WindowSize - 8)
    let straddling = expect peekBytes(&source, 16)!
    Swag.assert(straddling.count == ByteSource.WindowSize)
    Swag.assert(sourceMatches(straddling, ByteSource.WindowSize - 8))

    // A request larger than the window is honored whole.
    expect source.seek(5)
    let grown = expect peekBytes(&source, ByteSource.WindowSize + 500)!
    Swag.assert(grown.count >= ByteSource.WindowSize + 500)
    Swag.assert(sourceMatches(grown, 5))

    // The tail answers what remains, and nothing past it.
    expect source.seek(Count - 3)
    let tail = expect peekBytes(&source, 3)!
    Swag.assert(tail.count == 3)
    Swag.assert(sourceMatches(tail, Count - 3))
    discard catch peekBytes(&source, 4) as pastEnd
    Swag.assert(pastEnd is InvalidFormatError)

    // A peek consumes nothing, so the read that follows starts where the peek looked.
    var bytes: [3] u8
    expect source.readExact(bytes)
    Swag.assert(sourceMatches(bytes, Count - 3))
    Swag.assert(source.isAtEnd())
}

// Text lines and typed values read the same from a file as from memory.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("bytesource_lines.txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) "HEADER 1\r\nFRAME\n\x01\x02\x03\x04")

    var source = expect ByteSource.openFile(fileName.toString())
    Swag.assert(expect source.readLine(32) == "HEADER 1")
    Swag.assert(expect source.readLine(32) == "FRAME")
    Swag.assert(expect source.readBigEndian'u32() == 0x01020304)
    Swag.assert(source.isAtEnd())
}

// A file that does not exist fails to open rather than opening empty.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("bytesource_missing.bin")
    let source   = catch ByteSource.openFile(fileName.toString()) as err
    discard source
    Swag.assert(err != null)
}

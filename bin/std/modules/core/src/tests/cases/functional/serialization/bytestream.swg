#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let input = [0x10'u8, 0x20, 0x30, 0x40]

    var stream = ByteStream.openRead(input)
    Swag.require(stream.length() == 4)
    Swag.require(stream.position() == 0)
    Swag.require(not stream.isEof())
    Swag.require(stream.peekU8() == 0x10)
    Swag.require(stream.readU8() == 0x10)
    Swag.require(stream.position() == 1)
    Swag.require(stream.peekU8() == 0x20)
    Swag.require(Slice.equals(stream.remainingBytes(), [0x20, 0x30, 0x40]))
    Swag.require(stream.remainingString() == "\x20\x30\x40")

    stream.advance(2)
    Swag.require(stream.position() == 3)
    Swag.require(not stream.isEof())
    Swag.require(stream.readU8() == 0x40)
    Swag.require(stream.position() == 4)
    Swag.require(stream.isEof())
    Swag.require(stream.peekU8() == 0)
}

#test
{
    var bytes: Array'u8
    var stream = ByteStream.openRead(bytes.toSlice())

    Swag.require(stream.remainingBytes().count == 0)
    Swag.require(stream.remainingString().count == 0)
}

#test
{
    var buffer: Array'u8
    var stream = ByteStream.openWrite(&buffer)
    stream.writeBytes([0xAB, 0xCD, 0xEF])

    Swag.require(stream.length() == 3)
    Swag.require(stream.position() == 3)
    Swag.require(Slice.equals(buffer.toSlice(), [0xAB, 0xCD, 0xEF]))

    stream.setPosition(0)
    Swag.require(not stream.isEof())
    Swag.require(stream.peekU8() == 0xAB)
    Swag.require(stream.readU8() == 0xAB)
    Swag.require(Slice.equals(stream.remainingBytes(), [0xCD, 0xEF]))
}

#test
{
    var buffer: Array'u8
    buffer.reserve(4)
    buffer.add([10'u8, 20, 30, 40])

    var stream = ByteStream.openWrite(&buffer)
    stream.setPosition(1)
    stream.writeBytes(buffer[0 until 3])
    Swag.require(Slice.equals(buffer.toSlice(), [10, 10, 20, 30]))

    stream.setPosition(4)
    stream.writeBytes(buffer.toSlice())
    Swag.require(Slice.equals(buffer.toSlice(), [10, 10, 20, 30, 10, 10, 20, 30]))
}

#test
{
    var buffer: Array'u8
    buffer.reserve(8)
    buffer.add([0x41'u8, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48])
    let value = Swag.makeString(buffer.buffer, buffer.count)

    var stream = ByteStream.openWrite(&buffer)
    stream.writeSizedString(value)

    let expected: [12] u8 = [8, 0, 0, 0, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48]
    Swag.require(Slice.equals(buffer.toSlice(), expected))
}

// LEB128 varints round-trip across the byte widths, and a truncated or over-long
// encoding is refused.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    let values: [7] u64 = [0, 1, 127, 128, 300, 0xFFFFFFFF, Swag.U64.Max]
    for v in values do
        writer.writeVarint(v)

    var reader = ByteStream.openRead(buffer.toSlice())
    for v in values do
        Swag.require((expect reader.readVarint()) == v)
    Swag.require(reader.position() == buffer.count)

    // A single-byte value encodes as itself.
    var small: Array'u8
    var sw = ByteStream.openWrite(&small)
    sw.writeVarint(0x45)
    Swag.require(Slice.equals(small.toSlice(), [0x45]))

    // Truncated in the middle of a continuation.
    let cut: [1] u8 = [0x80]
    var truncated   = ByteStream.openRead(cut)
    var errcutOutcome: Swag.Error
    discard catch truncated.readVarint() as errcutOutcome
    let errcut = errcutOutcome.value()
    Swag.require(errcut != null)

    // More than 64 bits of payload is refused.
    let long: [11] u8 = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]
    var overlong      = ByteStream.openRead(long)
    var errlongOutcome: Swag.Error
    discard catch overlong.readVarint() as errlongOutcome
    let errlong = errlongOutcome.value()
    Swag.require(errlong != null)
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeLittleEndian(0x1234'u16)
    writer.writeLittleEndian(0xAABBCCDD'u32)
    writer.writeBigEndian(0xAABBCCDD'u32)

    // The bytes must be the declared order, not the host's.
    Swag.require(Slice.equals(buffer.toSlice(), [0x34, 0x12, 0xDD, 0xCC, 0xBB, 0xAA, 0xAA, 0xBB, 0xCC, 0xDD]))

    var reader = ByteStream.openRead(buffer.toSlice())
    Swag.require(expect reader.readLittleEndian'u16() == 0x1234)
    Swag.require(expect reader.readLittleEndian'u32() == 0xAABBCCDD)
    Swag.require(expect reader.readBigEndian'u32() == 0xAABBCCDD)
    Swag.require(reader.position() == 10)
}

// A signed field is written and read with its exact bit pattern, and a single byte carries
// no byte order at all.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeBigEndian(800's16)
    writer.writeBigEndian(-800's16)
    writer.writeBigEndian(-70000's32)
    writer.writeBigEndian(-5_000_000_000's64)
    writer.writeBigEndian(200'u8)
    writer.writeBigEndian(-100's8)

    // 800 is 0x0320, so a big-endian field stores its high byte first.
    Swag.require(Slice.equals(buffer[0 until 2], [0x03, 0x20]))
    Swag.require(Slice.equals(buffer[2 until 4], [0xFC, 0xE0]))

    var reader = ByteStream.openRead(buffer.toSlice())
    Swag.require(expect reader.readBigEndian's16() == 800)
    Swag.require(expect reader.readBigEndian's16() == -800)
    Swag.require(expect reader.readBigEndian's32() == -70000)
    Swag.require(expect reader.readBigEndian's64() == -5_000_000_000)
    Swag.require(expect reader.readBigEndian'u8() == 200)
    Swag.require(expect reader.readBigEndian's8() == -100)
    Swag.require(reader.position() == 18)
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeLittleEndian(800's16)
    writer.writeLittleEndian(-70000's32)
    writer.writeLittleEndian(-100's8)

    Swag.require(Slice.equals(buffer[0 until 2], [0x20, 0x03]))

    var reader = ByteStream.openRead(buffer.toSlice())
    Swag.require(expect reader.readLittleEndian's16() == 800)
    Swag.require(expect reader.readLittleEndian's32() == -70000)
    Swag.require(expect reader.readLittleEndian's8() == -100)
    Swag.require(reader.position() == 7)
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("sample")
    writer.writeSizedString("")

    // A 32-bit little-endian byte count precedes the bytes.
    Swag.require(buffer.count == 4 + 6 + 4)
    Swag.require(Slice.equals(buffer[0 until 4], [6, 0, 0, 0]))

    var reader = ByteStream.openRead(buffer.toSlice())
    Swag.require(expect reader.readSizedString() == "sample")
    Swag.require((expect reader.readSizedString()).isEmpty())
    Swag.require(reader.isEof() or reader.position() == buffer.count)
}

#test
{
    let source    = [0'u8]
    let oversized = Swag.makeString(source.buffer, cast(u64, Swag.U32.Max) + 1)
    var buffer: Array'u8
    var writer    = ByteStream.openWrite(&buffer)

    let rejected = Swag.catchPanic(func|&writer, oversized|() { writer.writeSizedString(oversized) })
    Swag.require(rejected.raised and rejected.message() == "sized string exceeds the 32-bit byte-count limit")
    Swag.require(buffer.isEmpty())
}

// A stored count beyond the cap must fail instead of reserving it.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("too long")

    var reader = ByteStream.openRead(buffer.toSlice())
    var errOutcome: Swag.Error
    discard catch reader.readSizedString(4) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// A truncated payload must fail rather than read past the end.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("sample")
    buffer.resize(buffer.count - 2)

    var reader = ByteStream.openRead(buffer.toSlice())
    var errOutcome: Swag.Error
    discard catch reader.readSizedString() as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// A zero-byte read from an empty stream does not ask for backing storage.
#test
{
    var bytes: Array'u8
    var stream    = ByteStream.openWrite(&bytes)
    var byte:  u8 = 0xA5
    expect stream.readBytes(&byte, 0)
    Swag.require(byte == 0xA5 and stream.position() == 0)
}

// Oversized reads fail before touching the destination or advancing the cursor.
#test
{
    let input  = [0x10'u8, 0x20, 0x30, 0x40]
    var stream = ByteStream.openRead(input)
    stream.setPosition(1)

    var byte: u8 = 0xA5
    var oversizedReadOutcome: Swag.Error
    discard catch stream.readBytes(&byte, Swag.U64.Max) as oversizedReadOutcome
    let error = oversizedReadOutcome.value()
    Swag.require(error is Errors.OverflowError)
    Swag.require(byte == 0xA5 and stream.position() == 1)

    let next = expect stream.readNative'u8()
    Swag.require(next == 0x20 and stream.position() == 2)

    var nativeReadOutcome: Swag.Error
    discard catch stream.readNative'u32() as nativeReadOutcome
    let nativeError = nativeReadOutcome.value()
    Swag.require(nativeError is Errors.OverflowError)
    Swag.require(stream.position() == 2)

    var tail: [2] u8
    expect stream.readBytes(&tail[0], tail.count)
    Swag.require(Slice.equals(tail, [0x30, 0x40]))
    Swag.require(stream.position() == input.count)

    expect stream.readBytes(&byte, 0)
    var endReadOutcome: Swag.Error
    discard catch stream.readBytes(&byte, 1) as endReadOutcome
    let endError = endReadOutcome.value()
    Swag.require(endError is Errors.OverflowError)
    Swag.require(byte == 0xA5 and stream.position() == input.count)
}

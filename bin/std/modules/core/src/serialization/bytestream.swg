using Core.Errors

// Provides a bounded cursor over borrowed bytes or a caller-owned byte array.
//
// A read stream borrows its input slice. A write stream borrows its destination
// array and can reallocate that array while it grows.
public struct ByteStream
{
    internal
    {
        readBuffer:  const [..] u8?     // Borrowed read-only bytes.
        writeBuffer: *Array'u8?         // Borrowed writable destination.
        seek:        u64                // Current byte position.
        eof:         bool               // Whether a read advanced to the end.
    }
}

public impl ByteStream
{
    // Creates a stream that reads the borrowed bytes of `readBuffer`.
    func openRead(readBuffer: const [..] u8)->ByteStream
    {
        var result: retval
        result.readBuffer = readBuffer
        return result
    }

    // Creates a stream that writes into the borrowed array `writeBuffer`, growing it as needed.
    func openWrite(writeBuffer: *Array'u8)->ByteStream
    {
        var result: retval
        result.writeBuffer = writeBuffer
        return result
    }

    // Returns the unread bytes from the current position to the end.
    mtd remainingBytes()->const [..] u8 => Swag.makeSlice(.data() + .seek, .length() - .seek)

    // Returns the unread bytes as a borrowed string.
    mtd remainingString()->string => Swag.makeString(.data() + .seek, .length() - .seek)

    // Returns the total length of the underlying buffer, in bytes.
    mtd const length()->u64 => .writeBuffer ? .writeBuffer.count : (.readBuffer).count

    // Kept in the exported dependency because public generic methods expand in
    // their caller and need this primitive. It is not part of the documented API.
    #[Swag.NoDoc]
    mtd data()->const [*] u8 => .writeBuffer ? .writeBuffer.buffer! : (.readBuffer).buffer!

    // Returns whether [[Core.ByteStream.advance]], [[Core.ByteStream.readU8]], or [[Core.ByteStream.setPosition]] reached the end of the buffer.
    mtd const isEof()->bool => .eof

    // Writes `val` as the host lays it out and advances past it.
    mtd(T) writeNative(val: T)
    {
        Swag.assert(.writeBuffer != null)

        let wb = .writeBuffer!
        if .seek + #sizeof(T) > wb.count do
            wb.grow(.seek + #sizeof(T))
        let ptr = cast(*T) (wb.storage() + .seek)
        ptr[]    = val
        .seek    += #sizeof(T)
        wb.count = Math.max(wb.count, .seek)
    }

    // Writes the bytes of `slice` and advances past them.
    mtd writeBytes(slice: const [..] u8)
    {
        Swag.assert(.writeBuffer != null)

        let count = slice.count
        if not count do
            return

        let wb = .writeBuffer
        if .seek + count > wb.count do
            wb.grow(.seek + count)
        let buffer = wb.storage()
        let ptr    = buffer + .seek
        Memory.copy(ptr, slice.buffer, count)
        .seek    += count
        wb.count = Math.max(wb.count, .seek)
    }

    // Reads a value of type `T` laid out as the host stores it, and advances past it.
    mtd(T) readNative()->T fail
    {
        if .seek + #sizeof(T) > .length() do
            fail OverflowError{"byte stream overflow"}
        let val = (cast(const *T) (.data() + .seek))[]
        .seek += #sizeof(T)
        return val
    }

    // Copies the next `count` bytes to `dest` and advances past them.
    mtd readBytes(dest: *u8?, count: u64) fail
    {
        if .seek + count > .length() do
            fail OverflowError{"byte stream overflow"}
        Memory.copy(dest, .data() + .seek, count)
        .seek += count
    }

    // Writes a value of type `T` in little-endian byte order.
    //
    // Use this instead of [[Core.ByteStream.writeNative]] for a persisted or transmitted format,
    // so the bytes do not depend on the architecture that produced them.
    mtd(T) writeLittleEndian(value: T)
    {
        .writeNative'T(Math.nativeToLittleEndian(value))
    }

    // Reads a little-endian value of type `T`.
    mtd(T) readLittleEndian()->T fail => Math.littleEndianToNative(try .readNative'T())

    // Writes a value of type `T` in big-endian byte order.
    mtd(T) writeBigEndian(value: T)
    {
        .writeNative'T(Math.nativeToBigEndian(value))
    }

    // Reads a big-endian value of type `T`.
    mtd(T) readBigEndian()->T fail => Math.bigEndianToNative(try .readNative'T())

    // Writes an unsigned value as a LEB128 varint.
    //
    // Seven value bits per byte, low bits first; the high bit of a byte marks a
    // continuation. Values below 128 take a single byte.
    mtd writeVarint(value: u64)
    {
        var v = value
        while v >= 0x80
        {
            .writeNative(cast(u8) ((v & 0x7F) | 0x80))
            v >>= 7
        }

        .writeNative(cast(u8) v)
    }

    // Reads an unsigned LEB128 varint written by [[Core.ByteStream.writeVarint]].
    //
    // Fails when the stream ends inside the value or the encoding exceeds 64 bits.
    mtd readVarint()->u64 fail
    {
        var result: u64
        var shift = 0'u32
        while true
        {
            let b       = try .readNative'u8()
            let payload = cast(u64) (b & 0x7F)

            // The tenth byte can only carry the top bit of a 64-bit value; anything
            // wider is an over-long encoding.
            if shift == 63 and payload > 1 do
                fail OverflowError{"varint is too long"}

            result |= payload << shift
            if b < 0x80 do
                return result
            shift += 7
            if shift >= 64 do
                fail OverflowError{"varint is too long"}
        }
    }

    // Writes a string as a little-endian `u32` byte count followed by its bytes.
    //
    // This is the framing [[Core.ByteStream.readSizedString]] expects. The count is a byte count,
    // not a character count.
    mtd writeSizedString(value: string)
    {
        .writeLittleEndian(cast(u32) value.count)
        .writeBytes(cast(const [..] u8) value)
    }

    // Reads a string written by [[Core.ByteStream.writeSizedString]].
    //
    // Fails when the stored byte count exceeds `maxLength` or the remaining
    // bytes, so a corrupted or hostile input cannot request a huge allocation.
    mtd readSizedString(maxLength: u64 = Swag.U32.Max)->String fail
    {
        var result: retval
        let count = cast(u64) (try .readLittleEndian'u32())
        if count > maxLength do
            fail OverflowError{"sized string is too long"}
        if count > .remainingBytes().count do
            fail OverflowError{"sized string is longer than the remaining input"}
        result.reserve(count)
        try .readBytes(result.buffer, count)
        result.length = count
        return result
    }

    // Reads one byte and advances past it, or returns zero at the end of the buffer.
    mtd readU8()->u8
    {
        let c = .peekU8()
        .advance()
        return c
    }

    // Returns the byte at the current position without consuming it, or zero at the end of the buffer.
    mtd peekU8()->u8
    {
        if .seek >= .length() do
            return 0
        return (.data() + .seek)[]
    }

    // Advances by `count` bytes, clamping at the end of the buffer.
    mtd advance(count: u64 = 1)
    {
        let len = .length()
        if count >= len - .seek
        {
            .seek = len
            .eof  = true
            return
        }

        .seek += count
    }

    // Sets the absolute byte position.
    mtd setPosition(position: u64)
    {
        let len = .length()
        Swag.assert(position <= len)
        .seek = position
        .eof  = .seek >= len
    }

    // Returns the current absolute byte position.
    mtd const position()->u64 => .seek
}

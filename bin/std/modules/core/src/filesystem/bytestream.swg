using Core.Errors

// Provides a bounded cursor over borrowed bytes or a caller-owned byte array.
//
// A read stream borrows its input slice. A write stream borrows its destination
// array and can reallocate that array while it grows.
public struct ByteStream
{
    internal
    {
        readBuffer:  #null const [..] u8     // Borrowed read-only bytes.
        writeBuffer: #null *Array'u8         // Borrowed writable destination.
        seek:        u64                     // Current byte position.
        eof:         bool                    // Whether a read advanced to the end.
    }
}

public impl ByteStream
{
    // Creates a byte stream for reading from a buffer
    func openRead(readBuffer: const [..] u8)->ByteStream
    {
        var result: retval
        result.readBuffer = readBuffer
        return result
    }

    // Creates a byte stream for writing to a buffer
    func openWrite(writeBuffer: *Array'u8)->ByteStream
    {
        var result: retval
        result.writeBuffer = writeBuffer
        return result
    }

    // Returns the unread bytes from the current position to the end.
    mtd remainingBytes()->const [..] u8
    {
        return @mkslice(.data() + .seek, .length() - .seek)
    }

    // Returns the unread bytes as a borrowed string.
    mtd remainingString()->string
    {
        return @mkstring(.data() + .seek, .length() - .seek)
    }

    // Returns the total length of the buffer (read or write)
    mtd const length()->u64
    {
        return .writeBuffer ? .writeBuffer.count : @countof(.readBuffer)
    }

    // Kept in the exported dependency because public generic methods expand in
    // their caller and need this primitive. It is not part of the documented API.
    #[Swag.NoDoc]
    mtd data()->const [*] u8
    {
        return .writeBuffer ? notnull .writeBuffer.buffer : notnull @dataof(.readBuffer)
    }

    // Returns true if the end of the buffer was reached during reading
    mtd const isEof()->bool
    {
        return .eof
    }

    // Writes a native value of type 'T' to the stream
    mtd(T) writeNative(val: T)
    {
        Debug.assert(writeBuffer != null)

        let wb = notnull writeBuffer
        if seek + #sizeof(T) > wb.count do
            wb.reserve(seek + #sizeof(T))
        let buffer = notnull wb.buffer
        var ptr    = cast(*T) (buffer + seek)
        dref ptr = val
        seek     += #sizeof(T)
        wb.count = Math.max(wb.count, seek)
    }

    // Writes a slice of bytes to the stream
    mtd writeBytes(slice: const [..] u8)
    {
        Debug.assert(.writeBuffer != null)

        let count = @countof(slice)
        if !count do
            return

        let wb = notnull .writeBuffer
        if .seek + count > wb.count do
            wb.reserve(.seek + count)
        let buffer = notnull wb.buffer
        let ptr    = buffer + .seek
        Memory.copy(ptr, @dataof(slice), count)
        .seek    += count
        wb.count = Math.max(wb.count, .seek)
    }

    // Reads a native value of type 'T' from the stream
    mtd(T) readNative()->T fail
    {
        if .seek + #sizeof(T) > .length() do
            fail OverflowError{"byte stream overflow"}
        let val = dref cast(const *T) (.data() + .seek)
        .seek += #sizeof(T)
        return val
    }

    // Reads 'count' bytes from the stream into 'dest'
    mtd readBytes(dest: #null *u8, count: u64) fail
    {
        if .seek + count > .length() do
            fail OverflowError{"byte stream overflow"}
        Memory.copy(dest, .data() + .seek, count)
        .seek += count
    }

    // Reads and consumes a single byte
    mtd readU8()->u8
    {
        let c = .peekU8()
        .advance()
        return c
    }

    // Peeks at a single byte without consuming it
    mtd peekU8()->u8
    {
        if .seek >= .length() do
            return 0
        return dref (.data() + .seek)
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
        Debug.assert(position <= len)
        .seek = position
        .eof  = .seek >= len
    }

    // Returns the current absolute byte position.
    mtd const position()->u64 => .seek
}

#global namespace File

// Reads a UTF-8 text file through an owned, buffered [[Core.File.FileStream]].
//
// A byte-order mark at the start of the file is skipped.
public struct TextReader
{
    internal
    {
        stream:        FileStream     // Owned file stream.
        buffer:        Array'u8       // Bytes read from the stream and not yet consumed.
        byteSeek:      u64            // Offset of the first unconsumed byte in `buffer`.
        checkPreamble: bool           // Whether the next refill is the first one, which may start with a byte-order mark.
    }
}

impl TextReader
{
    // Refills the buffer from the stream and skips a byte-order mark on the first refill.
    mtd readBuffer() fail
    {
        .byteSeek     = 0
        .buffer.count = try .stream.read(.buffer.buffer, .buffer.capacity)
        if not .checkPreamble do
            return

        .checkPreamble = false
        if Text.hasBom(.buffer.toSlice(), .Utf8) do
            .byteSeek = Text.bomLength(.Utf8)
    }
}

public impl TextReader
{
    // Opens `fullName` for reading.
    mtd open(fullName: string) fail
    {
        Swag.assert(not .stream.isOpen())
        .stream = try openRead(fullName)

        // Small files are read in one refill; large ones through a 64 KiB window.
        .buffer.clear()
        .buffer.reserve(Math.clamp(try .stream.size(), 16'u64, 64 * 1024'u64))
        .byteSeek      = 0
        .checkPreamble = true
    }

    // Closes the reader and its stream.
    mtd close()
    {
        .stream.close()
    }

    // Reads one line into `result` and returns false at end of file.
    //
    // Line-ending bytes are consumed but not included in the result.
    #[Swag.Safety(.BoundCheck | .Overflow, false)]
    mtd readLine(result: *String)->bool fail
    {
        result.clear()

        if .byteSeek == .buffer.count
        {
            try .readBuffer()
            if .buffer.isEmpty() do
                return false
        }

        for
        {
            Swag.assert(.buffer.buffer != null)
            var cursor       = .buffer.buffer + .byteSeek
            let segmentBegin = cursor
            let bufferEnd    = .buffer.buffer + .buffer.count

            // Scan eight bytes at a time for a line ending, then finish byte by byte.
            while cursor + 8'u64 <= bufferEnd
            {
                let word = cast(const *u64, cursor)[]
                if Math.hasByte(word, '\r') or Math.hasByte(word, '\n') do
                    break
                cursor += 8
            }

            while cursor != bufferEnd and cursor[] != '\r' and cursor[] != '\n' do
                cursor += 1

            let segmentBytes = cast(u64, (cursor - segmentBegin))
            result[] += Swag.makeString(segmentBegin, segmentBytes)

            // The line continues in the next refill; at end of file it ends here.
            if cursor == bufferEnd
            {
                try .readBuffer()
                if .buffer.isEmpty() do
                    return true
                continue
            }

            // Consume the line ending too.
            .byteSeek += segmentBytes + 1

            // A '\r' followed by '\n' is one line ending, even when a refill separates them.
            if cursor[] == '\r'
            {
                if cursor + 1'u64 < bufferEnd
                {
                    if (cursor + 1)[] == '\n' do
                        .byteSeek += 1
                }
                else
                {
                    try .readBuffer()
                    if .byteSeek < .buffer.count and .buffer[.byteSeek] == '\n' do
                        .byteSeek += 1
                }
            }

            break
        }

        return true
    }

    // Reads from the current position to the end of the file.
    mtd readToEnd()->String fail
    {
        var result: retval
        if .byteSeek == .buffer.count do
            try .readBuffer()

        while .byteSeek < .buffer.count
        {
            let remainingBytes = .buffer.count - .byteSeek
            result.grow(result.length + remainingBytes)
            Memory.copy(result.buffer + result.length, .buffer.buffer + .byteSeek, remainingBytes)
            result.length += remainingBytes
            try .readBuffer()
        }

        return result
    }
}

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
            var ptr  = .buffer.buffer + .byteSeek
            let ptrB = ptr
            let ptrE = .buffer.buffer + .buffer.count

            // Scan eight bytes at a time for a line ending, then finish byte by byte.
            while ptr + 8'u64 <= ptrE
            {
                let c64 = (cast(const *u64) ptr)[]
                if Math.hasByte(c64, '\r') or Math.hasByte(c64, '\n') do
                    break
                ptr += 8
            }

            while ptr != ptrE and ptr[] != '\r' and ptr[] != '\n' do
                ptr += 1

            let range = cast(u64) (ptr - ptrB)
            result[] += Swag.makeString(ptrB, range)

            // The line continues in the next refill; at end of file it ends here.
            if ptr == ptrE
            {
                try .readBuffer()
                if .buffer.isEmpty() do
                    return true
                continue
            }

            // Consume the line ending too.
            .byteSeek += range + 1

            // A '\r' followed by '\n' is one line ending, even when a refill separates them.
            if ptr[] == '\r'
            {
                if ptr + 1'u64 < ptrE
                {
                    if (ptr + 1)[] == '\n' do
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
            let remain = .buffer.count - .byteSeek
            result.grow(result.length + remain)
            Memory.copy(result.buffer + result.length, .buffer.buffer + .byteSeek, remain)
            result.length += remain
            try .readBuffer()
        }

        return result
    }
}

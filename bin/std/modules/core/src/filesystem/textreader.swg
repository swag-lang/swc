#global namespace File

// Text encoding formats supported for reading text files
public enum TextEncoding
{
    Ascii     // ASCII encoding
    Utf8      // UTF-8 encoding
}

// Reads a text file through an owned, buffered [[Core.File.FileStream]].
public struct TextReader
{
    internal
    {
        stream:        FileStream            // Owned file stream.
        buffer:        Array'u8              // Buffered encoded bytes.
        encodingType = TextEncoding.Utf8     // Selected source encoding.
        byteSeek:      u64                   // Current byte offset in the buffer.
        bufferSize:    u64                   // Target buffer capacity.
        checkPreamble: bool                  // Whether the first read must inspect a UTF-8 BOM.
    }
}

impl TextReader
{
    mtd readBuffer() fail
    {
        .byteSeek = 0

        // First init. Fill force 4 bytes of the decode buffer to be 0 to
        // read the BOM
        if .checkPreamble
        {
            .checkPreamble = false
            .buffer.reserve(.bufferSize)

            if .encodingType == .Utf8
            {
                let buffer = notnull .buffer.buffer
                dref cast(*u32) buffer = 0
                .buffer.count          = .stream.read(buffer, .buffer.capacity)

                // BOM
                if .buffer.count >= 3 and .buffer[0] == 0xEF and .buffer[1] == 0xBB and .buffer[2] == 0xBF do
                    .byteSeek = 3

                return
            }
        }

        .buffer.count = .stream.read(.buffer.buffer, .buffer.capacity)
    }
}

public impl TextReader
{
    // Opens the reader with the specified text encoding (default is UTF-8)
    mtd open(fullname: string, encoding = TextEncoding.Utf8) fail
    {
        Debug.assert(!.stream.isOpen())

        .stream = try openRead(fullname)
        Debug.assert(.stream.isOpen())

        .byteSeek      = 0
        .checkPreamble = true
        .bufferSize    = Math.min(.stream.size(), 64 * 1024'u64)
        .bufferSize    = Math.max(.bufferSize, 16)
        .encodingType  = encoding
    }

    // Closes the reader and the associated stream
    mtd close()
    {
        .stream.close()
    }

    // Reads one line into `result` and returns false at end of file.
    //
    // Line-ending bytes are consumed but not included in the result.
    #[Swag.Safety(.BoundCheck | .Overflow, false)]
    mtd readLine(result: &String)->bool fail
    {
        result.clear()

        if .byteSeek == .buffer.count
        {
            .readBuffer()
            if .buffer.isEmpty() do
                return false
        }

        for
        {
            var ptr  = (notnull .buffer.buffer) + .byteSeek
            let ptrB = ptr
            let ptrE = (notnull .buffer.buffer) + .buffer.count

            // u64 by u64
            while ptr + 8'u64 <= ptrE
            {
                let c64 = dref cast(*u64) ptr
                if Math.hasByte(c64, '\r') or Math.hasByte(c64, '\n') do
                    break
                ptr += 8
            }

            // u8 by u8
            while ptr != ptrE and dref ptr != '\r' and dref ptr != '\n' do
                ptr += 1

            let range = cast(u64) (ptr - ptrB)
            result += @mkstring(ptrB, range)

            // We have reached the end of the buffer without finding an eol
            // Restart
            if ptr == ptrE
            {
                .readBuffer()
                if .buffer.isEmpty() do
                    return true
                continue
            }

            // + 1 because we eat the eol
            .byteSeek += range + 1

            // If we have a '\r', then eat the following '\n' if it exists
            if dref ptr == '\r'
            {
                if ptr + 1'u64 < ptrE
                {
                    if dref (ptr + 1) == '\n' do
                        .byteSeek += 1
                }
                else
                {
                    .readBuffer()
                    if .byteSeek < .buffer.count and .buffer[.byteSeek] == '\n' do
                        .byteSeek += 1
                }
            }

            break
        }

        return true
    }

    // Reads from the current position to the end as UTF-8 text.
    mtd readToEnd()->String fail
    {
        var result: retval

        // Append what remains valid in the current decoded buffer
        if .byteSeek < .buffer.count
        {
            let remain = .buffer.count - .byteSeek
            result.grow(result.length + remain)
            Memory.copy(result.buffer + result.length, .buffer.buffer + .byteSeek, remain)
            result.length += remain
        }

        // Then read and append all the rest
        .readBuffer()
        while .buffer.count
        {
            let remain = .buffer.count - .byteSeek
            result.grow(result.length + remain)
            Memory.copy(result.buffer + result.length, .buffer.buffer + .byteSeek, remain)
            result.length += remain
            .readBuffer()
        }

        return result
    }
}

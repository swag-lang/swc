#global public

using Core, Core.Errors

// Reads the bytes of an encoded video stream, from a file or from memory.
//
// A decoder receives one of these and never learns which backing it has: the same reads
// and seeks work on both. A file-backed source keeps one read window alive and nothing
// else, so decoding costs the same memory whether the file holds ten frames or ten hours
// of them. This is what makes [[Video.Reader]] independent of the stream length.
//
// A memory source borrows its bytes: they must stay valid and unchanged until the source
// is closed.
#[Swag.NoCopy]
struct Source
{
    internal
    {
        stream:      File.FileStream         // Open file, when the source reads from a file.
        memory:      #null const [..] u8     // Borrowed encoded bytes, when the source reads from memory.
        path:        String                  // File the source reads, empty for a memory source.
        window:      Array'u8                // Read-ahead window over the file.
        windowStart: u64                     // Stream offset of the first byte held in the window.
        windowCount: u64                     // Number of valid bytes in the window.
        cursor:      u64                     // Read position in the stream.
        length:      u64                     // Total size of the stream, in bytes.
        isFile:      bool                    // Whether the source reads from `stream`.
    }
}

impl Source
{
    // Size of the read-ahead window of a file source.
    //
    // It bounds the memory a source of any length uses, and it is the threshold above
    // which a read goes straight to its destination instead of being copied twice.
    private const WindowSize = 64 * 1024'u64

    // Opens `fileName` for streaming reads.
    //
    // The file stays open until the source is closed, and it must remain available and
    // unchanged until then.
    func openFile(fileName: string)->Source fail
    {
        var result: retval
        result.stream = File.openRead(fileName)
        result.length = result.stream.size()
        result.path   = fileName
        result.isFile = true
        return result
    }

    // Borrows `bytes` as one complete encoded stream.
    func openMemory(bytes: const [..] u8)->Source
    {
        var result: retval
        result.memory = bytes
        result.length = bytes.count
        return result
    }

    // Releases the file this source reads. Repeated calls do nothing.
    mtd close()
    {
        .stream.close()
        .windowCount = 0
    }

    // Returns the file this source reads, or an empty string for a memory source.
    mtd const sourcePath()->string => .path

    // Returns the total size of the stream, in bytes.
    mtd const size()->u64 => .length

    // Returns the read position, in bytes from the start of the stream.
    mtd const position()->u64 => .cursor

    // Returns the number of bytes between the read position and the end of the stream.
    mtd const remaining()->u64 => .length - .cursor

    // Reports whether the read position reached the end of the stream.
    mtd const isAtEnd()->bool => .cursor >= .length

    // Moves the read position to `offset` bytes from the start of the stream.
    //
    // Seeking to the end of the stream is valid; seeking past it fails, because a decoder
    // computing such an offset is reading a truncated stream.
    mtd seek(offset: u64) fail
    {
        if offset > .length do
            fail InvalidFormatError{"video stream offset runs past the end of the stream"}
        .cursor = offset
    }

    // Advances the read position by `count` bytes.
    mtd skip(count: u64) fail
    {
        if count > .remaining() do
            fail InvalidFormatError{"video stream ends before the skipped bytes"}
        .cursor += count
    }

    // Reads exactly as many bytes as `buffer` holds.
    //
    // Fails when the stream ends first, and leaves the read position unspecified in that
    // case: a decoder that hits the end of a stream reopens or seeks rather than resuming.
    mtd readExact(buffer: [..] u8) fail
    {
        let wanted = buffer.count
        if wanted > .remaining() do
            fail InvalidFormatError{"video stream ends before the requested bytes"}
        if !wanted do
            return

        if !.isFile
        {
            Memory.copy(buffer.buffer, (.memory).buffer! + .cursor, wanted)
            .cursor += wanted
            return
        }

        var done = 0'u64
        while done < wanted
        {
            let missing = wanted - done
            if .cursor >= .windowStart and .cursor < .windowStart + .windowCount
            {
                let available = Math.min(missing, .windowStart + .windowCount - .cursor)
                Memory.copy(buffer.buffer + done, .window.buffer! + (.cursor - .windowStart), available)
                done    += available
                .cursor += available
                continue
            }

            // A frame payload is larger than the window and is read once, so buffering it
            // would copy every byte twice and evict a window the header parser still uses.
            if missing >= WindowSize
            {
                if !.stream.readExactAt(.cursor, buffer[done until done + missing]) do
                    fail InvalidFormatError{"video stream ends before the requested bytes"}
                .cursor += missing
                return
            }

            .fillWindow()
        }
    }

    // Reads one byte.
    mtd readByte()->u8 fail
    {
        var value: u8
        .readExact(Swag.makeSlice(&value, 1))
        return value
    }

    // Reads the bytes up to the next line feed and returns the line without it.
    //
    // A trailing carriage return is removed, so a stream written with either end-of-line
    // convention parses the same. Fails when the line reaches `maxBytes` or the stream ends
    // before the terminator, which is how a text header of a binary stream stays bounded.
    mtd readLine(maxBytes: u64)->String fail
    {
        var bytes: Array'u8
        while true
        {
            let value = .readByte()
            if value == '\n'
            {
                if bytes.count and bytes.back() == '\r' do
                    discard bytes.popBack()
                return String.from(Swag.makeString(bytes.buffer, bytes.count))
            }

            bytes.add(value)
            if bytes.count > maxBytes do
                fail InvalidFormatError{"video stream line exceeds its maximum length"}
        }
    }

    // Refills the read window from the current position.
    private mtd fillWindow() fail
    {
        if .window.count != WindowSize do
            .window.resize(WindowSize)

        let wanted = Math.min(WindowSize, .remaining())
        .stream.seek(.Begin, .cursor)
        let read = .stream.read(.window.toSlice()[0 until wanted])
        if !read do
            fail InvalidFormatError{"video stream ends before the requested bytes"}

        .windowStart = .cursor
        .windowCount = read
    }
}

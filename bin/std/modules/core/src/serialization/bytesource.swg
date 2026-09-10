#global public

using Core.Errors

// Reads the bytes of a stream held in a file or in memory, through one cursor and one window.
//
// A decoder receives one of these and never learns which backing it has: the same reads,
// seeks, and peeks work on both. A file source keeps one read window alive and nothing else,
// so decoding costs the same memory whether the file holds ten frames or ten hours of them,
// and a read larger than the window goes straight to its destination rather than through it.
//
// A memory source borrows its bytes: they must stay valid and unchanged until the source is
// closed. [[Core.ByteStream]] is the cursor for bytes that are already in memory; this is what a
// codec reads a file of any size through.
//
// A read that runs past the end of the stream fails with [[Core.Errors.InvalidFormatError]],
// because a decoder computing such an offset is reading a truncated stream.
#[Swag.NoCopy]
struct ByteSource
{
    internal
    {
        stream:      File.FileStream     // Open file, when the source reads from a file.
        memory:      const [..] u8?      // Borrowed bytes, when the source reads from memory.
        fileName:    String              // File the source reads, empty for a memory source.
        window:      Array'u8            // Read-ahead window over the file.
        windowStart: u64                 // Stream offset of the first byte held in the window.
        windowCount: u64                 // Number of valid bytes in the window.
        cursor:      u64                 // Read position in the stream.
        length:      u64                 // Total size of the stream, in bytes.
        isFile:      bool                // Whether the source reads from `stream`.
        isMemory:    bool                // Whether the source reads from `memory`.
    }
}

impl ByteSource
{
    // Size of the read window of a file source, in bytes.
    //
    // It bounds the memory a source of any length uses, and it is the threshold from which a
    // read goes straight to its destination instead of being copied twice.
    const WindowSize = 64 * 1024'u64

    // Opens `fileName` for streaming reads.
    //
    // The file stays open until the source is closed, and it must remain available and
    // unchanged until then.
    func openFile(fileName: string)->ByteSource fail
    {
        var result: retval
        result.stream   = File.openRead(fileName)
        result.length   = result.stream.size()
        result.fileName = fileName
        result.isFile   = true
        return result
    }

    // Borrows `bytes` as one complete stream.
    func openMemory(bytes: const [..] u8)->ByteSource
    {
        var result: retval
        result.memory   = bytes
        result.length   = bytes.count
        result.isMemory = true
        return result
    }

    // Releases the file or the borrowed bytes and leaves an empty source. Repeated calls do nothing.
    //
    // A source that leaves scope closes itself; calling this earlier is how a reader releases a
    // file before its own value goes away.
    mtd close()
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)
    }

    // Reports whether the source still has a stream to read.
    mtd const isOpen()->bool => .isFile ? .stream.isOpen() : .isMemory

    // Returns the file this source reads, or an empty string for a memory source.
    mtd const path()->string => .fileName

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
    // Seeking to the end of the stream is valid; seeking past it fails.
    mtd seek(offset: u64) fail
    {
        if offset > .length do
            fail InvalidFormatError{"byte source offset runs past the end of the stream"}
        .cursor = offset
    }

    // Advances the read position by `count` bytes.
    mtd skip(count: u64) fail
    {
        if count > .remaining() do
            fail InvalidFormatError{"byte source ends before the skipped bytes"}
        .cursor += count
    }

    // Reads at most as many bytes as `buffer` holds and returns how many were read.
    //
    // The count is smaller than the buffer only when the stream ends first, and zero once the
    // read position is at the end. Fails when the file turns out shorter than it was when the
    // source opened it.
    mtd read(buffer: [..] u8)->u64 fail
    {
        let wanted = Math.min(buffer.count, .remaining())
        if not wanted do
            return 0

        if not .isFile
        {
            Memory.copy(buffer.buffer, (.memory).buffer! + .cursor, wanted)
            .cursor += wanted
            return wanted
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

            // A payload larger than the window is read once, so buffering it would copy every
            // byte twice and evict a window the header parser still uses.
            if missing >= WindowSize
            {
                if not .stream.readExactAt(.cursor, buffer[done until done + missing]) do
                    fail InvalidFormatError{"byte source ends before the requested bytes"}
                .cursor += missing
                return wanted
            }

            .fillWindow(missing)
        }

        return wanted
    }

    // Reads exactly as many bytes as `buffer` holds.
    //
    // Fails when the stream ends first, and leaves the read position unspecified in that case: a
    // decoder that hits the end of a stream reopens or seeks rather than resuming.
    mtd readExact(buffer: [..] u8) fail
    {
        if buffer.count > .remaining() do
            fail InvalidFormatError{"byte source ends before the requested bytes"}
        discard .read(buffer)
    }

    // Reads one byte.
    mtd readByte()->u8 fail
    {
        var value: u8
        .readExact(Swag.makeSlice(&value, 1))
        return value
    }

    // Reads one value of type `T` laid out as the host stores it.
    //
    // This is the read for a binary layout declared as a struct, or for an integer whose byte
    // order is the host's. Use [[Core.ByteSource.readLittleEndian]] or
    // [[Core.ByteSource.readBigEndian]] for a persisted or transmitted integer.
    mtd(T) readNative()->T fail
    {
        var result: T
        .readExact(Swag.makeSlice(cast([*] u8) &result, #sizeof(T)))
        return result
    }

    // Reads a little-endian integer of type `T`.
    mtd(T) readLittleEndian()->T fail
    {
        return Math.littleEndianToNative(.readNative'T())
    }

    // Reads a big-endian integer of type `T`.
    mtd(T) readBigEndian()->T fail
    {
        return Math.bigEndianToNative(.readNative'T())
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
                fail InvalidFormatError{"byte source line exceeds its maximum length"}
        }
    }

    // Returns the bytes at the read position without consuming them.
    //
    // The slice holds at least `count` bytes, and every further byte the source already holds
    // after them: a memory source returns everything up to the end of the stream, a file source
    // whatever its window covers. A scanner that walks frame headers therefore asks for the
    // header it needs and reads ahead as far as the window goes at no cost. Fails when fewer
    // than `count` bytes remain.
    //
    // The slice borrows the source's own storage and stays valid until the next read, seek,
    // skip, or peek on it. A file source grows its window to hold `count` bytes when they do not
    // fit, so a caller bounds `count` to bound its memory.
    mtd peek(count: u64)->const [..] u8 fail
    {
        if count > .remaining() do
            fail InvalidFormatError{"byte source ends before the requested bytes"}
        if .isAtEnd() do
            return Swag.makeSlice(.window.buffer, 0)

        if not .isFile do
            return Swag.makeSlice((.memory).buffer! + .cursor, .remaining())

        if .cursor < .windowStart or .cursor + count > .windowStart + .windowCount do
            .fillWindow(count)
        return .window.toSlice()[.cursor - .windowStart until .windowCount]
    }

    // Refills the window from the read position, with at least `wanted` bytes when they remain.
    private mtd fillWindow(wanted: u64) fail
    {
        let size = Math.max(WindowSize, wanted)
        if .window.count < size do
            .window.resize(size)

        let count = Math.min(size, .remaining())
        if not .stream.readExactAt(.cursor, .window.toSlice()[0 until count]) do
            fail InvalidFormatError{"byte source ends before the requested bytes"}

        .windowStart = .cursor
        .windowCount = count
    }
}

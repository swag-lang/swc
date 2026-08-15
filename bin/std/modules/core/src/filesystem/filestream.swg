#global public
#global namespace File

// Opaque handle to a file, used internally by FileStream
alias FileHandle = #null const *void

// Owns an open file and exposes byte-oriented reading, writing, and seeking.
#[Swag.NoCopy]
struct FileStream
{
    // What the stream is and what it can do. All of it is fixed when the file is opened, by the
    // access the caller asked for; reopen the file to change any of it.
    public readonly
    {
        name:     String     // File name associated with the stream
        canRead:  bool       // True if the stream supports reading
        canSeek:  bool       // True if the stream supports seeking
        canWrite: bool       // True if the stream supports writing
    }

    // Platform handle of the open file, owned by the stream and closed with it.
    internal handle: FileHandle
}

impl FileStream
{
    // Releases the native file handle still owned by this value.
    mtd opDrop()
    {
        .close()
    }

    // Establishes what an opened stream is and what it can do.
    //
    // The platform opener calls this once, with the access the caller asked for. Everything it
    // sets is fixed for the life of the stream.
    internal mtd open(name: string, handle: FileHandle, canRead, canWrite, canSeek: bool)
    {
        .name     = name
        .handle   = handle
        .canRead  = canRead
        .canWrite = canWrite
        .canSeek  = canSeek
    }

    // Returns true if the stream is currently open and valid
    func isOpen(const me)->bool
    {
        return .handle != null
    }

    // Reads at most `length` bytes, completing host-sized chunks until the stream ends.
    mtd read(buffer: #null *void, length: u64)->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canRead)
        if !length do
            return 0

        var total = 0'u64
        let bytes = cast([*] u8) buffer!
        while total < length
        {
            let chunk = cast(u32) Math.min(length - total, cast(u64) Swag.U32.Max)
            let read  = .readNative(bytes + total, chunk)
            total += read
            if read < chunk do
                break
        }

        return total
    }

    // Writes at most `length` bytes, completing host-sized chunks while progress is made.
    mtd write(buffer: #null const *void, length: u64)->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canWrite)
        if !length do
            return 0

        var total = 0'u64
        let bytes = cast(const [*] u8) buffer!
        while total < length
        {
            let chunk   = cast(u32) Math.min(length - total, cast(u64) Swag.U32.Max)
            let written = .writeNative(bytes + total, chunk)
            total += written
            if !written do
                break
        }

        return total
    }

    // Closes the stream. Repeated calls do nothing.
    mtd close()
    {
        if !.handle do
            return
        .closeNative()
        .handle = null
    }

    // Returns the current file length in bytes.
    mtd size()->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)
        return .sizeNative()
    }

    // Changes the file length and preserves the current position while it remains in range.
    mtd resize(newSize: u64) fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)
        Debug.assert(.canWrite)

        let oldPosition = .position()
        .seek(.Begin, newSize)
        .resizeNative()
        .seek(.Begin, Math.min(oldPosition, newSize))
    }

    // Commits buffered file data and metadata to the underlying device.
    mtd flush() fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canWrite)
        .flushNative()
    }

    // Returns the current absolute byte position.
    mtd position()->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)
        return .positionNative()
    }

    // Moves to `offset` bytes from `origin`.
    mtd seek(origin: SeekOrigin, offset: u64) fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)
        .seekNative(origin, offset)
    }

    // Advances by `count` bytes from the current position.
    mtd skip(count: u64) fail
    {
        .seek(.Current, count)
    }

    // Reads one native value and returns whether all of its bytes were available.
    mtd(T) readValue(buffer: *T)->bool fail
    {
        return .read(buffer, #sizeof(T)) == #sizeof(T)
    }

    // Reads at most the size of `buffer` and returns the number of bytes read.
    mtd read(buffer: [..] u8)->u64 fail
    {
        return .read(@dataof(buffer), @countof(buffer))
    }

    // Reads the next bounded UTF-8 segment without splitting an encoded rune.
    //
    // The stream position advances by the returned byte count. `maxBytes` needs at least four
    // bytes, so every UTF-8 rune can make progress. A malformed sequence at the current position
    // leaves that position unchanged and reports [[Core.Errors.InvalidFormatError]]. An empty
    // result means end of file.
    mtd readUtf8Chunk(maxBytes: u64)->String fail
    {
        if maxBytes < 4 do
            fail Errors.BadParameterError{"UTF-8 chunk size needs at least four bytes"}

        let start    = .position()
        let fileSize = .size()
        if start >= fileSize do
            return {}
        let remaining = fileSize - start

        let target = Math.min(maxBytes, remaining)
        let probe  = target <= Swag.U64.Max - 3 ? Math.min(target + 3, remaining) : remaining
        var bytes: Array'u8
        bytes.resize(probe)
        let count = .read(bytes.toSlice())
        bytes.resize(count)
        if !count do
            return {}

        var accepted = Math.min(target, count)
        let shortest = accepted > 3 ? accepted - 3 : 0
        while accepted > shortest and !Utf8.isValid(bytes.toSlice()[0 until accepted]) do
            accepted -= 1

        if !accepted or !Utf8.isValid(bytes.toSlice()[0 until accepted])
        {
            .seek(.Begin, start)
            fail Errors.InvalidFormatError{"file content is not valid UTF-8"}
        }

        if accepted != count do
            .seek(.Begin, start + accepted)
        return String.from(@mkstring(bytes.buffer!, accepted))
    }

    // Writes at most the size of `buffer` and returns the number of bytes written.
    mtd write(buffer: const [..] u8)->u64 fail
    {
        return .write(@dataof(buffer), @countof(buffer))
    }

    // Reads the complete `buffer` and returns false only when the stream ends first.
    mtd readExact(buffer: [..] u8)->bool fail
    {
        return .read(buffer) == @countof(buffer)
    }

    // Moves to `offset`, reads the complete `buffer`, and returns false only when the stream ends first.
    // The resulting stream position follows the bytes read.
    mtd readExactAt(offset: u64, buffer: [..] u8)->bool fail
    {
        .seek(.Begin, offset)
        return .readExact(buffer)
    }

    // Writes the complete `buffer` or fails if the stream stops accepting bytes.
    mtd writeAll(buffer: const [..] u8) fail
    {
        if .write(buffer) != @countof(buffer) do
            fail Swag.SystemError{"file write stopped before all bytes were written"}
    }

    // Moves to `offset` and writes the complete `buffer`.
    // The resulting stream position follows the bytes written.
    mtd writeAllAt(offset: u64, buffer: const [..] u8) fail
    {
        .seek(.Begin, offset)
        .writeAll(buffer)
    }
}

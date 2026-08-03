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
    readonly
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

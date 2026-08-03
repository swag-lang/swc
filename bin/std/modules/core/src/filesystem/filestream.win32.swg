#global if WINDOWS
#global public
#global namespace File

using Win32

impl FileStream
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .close()
    }

    // Reads at most `length` bytes and returns the number of bytes read.
    mtd read(buffer: #null *void, length: u64)->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canRead)

        if !length do
            return 0

        var total = 0'u64
        let bytes = cast([*] u8) notnull buffer
        while total < length
        {
            let chunk = cast(u32) Math.min(length - total, cast(u64) Swag.U32.Max)
            var read: DWORD
            if !ReadFile(.handle, bytes + total, chunk, &read, null) do
                failWinError(GetLastError())
            total += read
            if read < chunk do
                break
        }

        return total
    }

    // Writes `length` bytes and returns the number of bytes written.
    mtd write(buffer: #null const *void, length: u64)->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canWrite)

        if !length do
            return 0

        var total = 0'u64
        let bytes = cast(const [*] u8) notnull buffer
        while total < length
        {
            let chunk = cast(u32) Math.min(length - total, cast(u64) Swag.U32.Max)
            var written: DWORD
            discard catch WriteFile(.handle, bytes + total, chunk, &written, null) as err
            Errors.transformWinErrors(err)
            total += written
            if !written do
                break
        }

        return total
    }

    // Close the given file stream
    mtd close()
    {
        if .handle
        {
            CloseHandle(.handle)
            .handle = null
        }
    }

    // Returns the current file length in bytes.
    mtd size()->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)

        let hFile = cast(HANDLE) .handle
        var high  = 0'u32
        let low   = catch GetFileSize(hFile, &high) as err
        Errors.transformWinErrors(err)
        return low + (cast(u64) high << 32)
    }

    // Changes the file length while preserving the current position when it remains in range.
    // Shrinking past the current position leaves the position at the new end of the file.
    mtd resize(newSize: u64) fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)
        Debug.assert(.canWrite)

        let oldPosition = .position()
        .seek(.Begin, newSize)
        catch SetEndOfFile(cast(HANDLE) .handle) as err
        Errors.transformWinErrors(err, .name)
        .seek(.Begin, Math.min(oldPosition, newSize))
    }

    // Commits buffered file data and metadata to the underlying device.
    mtd flush() fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canWrite)

        catch FlushFileBuffers(cast(HANDLE) .handle) as err
        Errors.transformWinErrors(err, .name)
    }

    // Returns the current absolute byte position.
    mtd position()->u64 fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)

        let hFile = cast(HANDLE) .handle
        var high  = 0
        let low   = catch SetFilePointer(hFile, 0, &high, FILE_CURRENT) as err
        Errors.transformWinErrors(err)
        return low + (cast(u64) high << 32)
    }

    // Moves to `offset` bytes from `origin`.
    mtd seek(origin: SeekOrigin, offset: u64) fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)

        let hFile = cast(HANDLE) .handle
        let low   = cast(LONG) (offset & 0xFFFFFFFF)
        var high  = cast(LONG) (offset >> 32)

        var seekMode: DWORD
        switch origin
        {
        case .Begin:   seekMode = FILE_BEGIN
        case .Current: seekMode = FILE_CURRENT
        case .End:     seekMode = FILE_END
        }

        discard catch SetFilePointer(hFile, low, &high, seekMode) as err
        Errors.transformWinErrors(err)
    }

    // Advances by `count` bytes from the current position.
    mtd skip(count: u64) fail
    {
        .seek(.Current, count)
    }
}

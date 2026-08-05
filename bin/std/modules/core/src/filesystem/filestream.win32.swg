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
        let bytes = cast([*] u8) buffer!
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
        let bytes = cast(const [*] u8) buffer!
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

        var result: LARGE_INTEGER
        catch GetFileSizeEx(cast(HANDLE) .handle, &result) as err
        Errors.transformWinErrors(err, .name)
        return cast(u64) result
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

        var result: LARGE_INTEGER
        catch SetFilePointerEx(cast(HANDLE) .handle, 0, &result, FILE_CURRENT) as err
        Errors.transformWinErrors(err, .name)
        return cast(u64) result
    }

    // Moves to `offset` bytes from `origin`.
    mtd seek(origin: SeekOrigin, offset: u64) fail
    {
        Debug.assert(.isOpen())
        Debug.assert(.canSeek)

        var seekMode: DWORD
        switch origin
        {
        case .Begin:   seekMode = FILE_BEGIN
        case .Current: seekMode = FILE_CURRENT
        case .End:     seekMode = FILE_END
        }

        // `SetFilePointerEx` takes the whole distance as one signed 64-bit value; the split
        // `SetFilePointer` form truncates every offset with bit 31 set, so a file of 2 GB or more
        // cannot be addressed through it at all.
        catch SetFilePointerEx(cast(HANDLE) .handle, cast(LARGE_INTEGER) offset, null, seekMode) as err
        Errors.transformWinErrors(err, .name)
    }

    // Advances by `count` bytes from the current position.
    mtd skip(count: u64) fail
    {
        .seek(.Current, count)
    }
}

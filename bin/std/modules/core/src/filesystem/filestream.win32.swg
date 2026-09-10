#global if WINDOWS
#global public
#global namespace File

using Win32

impl FileStream
{
    // Reads up to `length` bytes into caller-owned writable storage and returns the number read.
    mtd readNative(buffer: *void, length: u32)->u32 fail
    {
        var read: DWORD
        if not ReadFile(.handle, buffer, length, &read, null) do
            failWinError(GetLastError())
        return read
    }

    // Writes up to `length` bytes from borrowed storage and returns the number written.
    mtd writeNative(buffer: const *void, length: u32)->u32 fail
    {
        var written: DWORD
        discard catch WriteFile(.handle, buffer, length, &written, null) as err
        Errors.transformWinErrors(err)
        return written
    }

    // Closes the underlying Windows handle; the caller must not reuse that handle.
    mtd closeNative()
    {
        CloseHandle(.handle)
    }

    // Returns the current file size in bytes.
    mtd sizeNative()->u64 fail
    {
        var result: LARGE_INTEGER
        catch GetFileSizeEx(cast(HANDLE) .handle, &result) as err
        Errors.transformWinErrors(err, .name)
        return cast(u64) result
    }

    // Truncates or extends the file at the current stream position.
    mtd resizeNative() fail
    {
        catch SetEndOfFile(cast(HANDLE) .handle) as err
        Errors.transformWinErrors(err, .name)
    }

    // Flushes buffered file data through the Windows file handle.
    mtd flushNative() fail
    {
        catch FlushFileBuffers(cast(HANDLE) .handle) as err
        Errors.transformWinErrors(err, .name)
    }

    // Returns the current byte offset from the beginning of the file.
    mtd positionNative()->u64 fail
    {
        var result: LARGE_INTEGER
        catch SetFilePointerEx(cast(HANDLE) .handle, 0, &result, FILE_CURRENT) as err
        Errors.transformWinErrors(err, .name)
        return cast(u64) result
    }

    // Moves the position by the signed 64-bit interpretation of `offset` relative to `origin`.
    mtd seekNative(origin: SeekOrigin, offset: u64) fail
    {
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
        catch SetFilePointerEx(cast(HANDLE) .handle, cast #bit (LARGE_INTEGER) offset, null, seekMode) as err
        Errors.transformWinErrors(err, .name)
    }
}

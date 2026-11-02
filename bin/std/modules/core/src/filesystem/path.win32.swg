#global if WINDOWS
#global public
#global namespace Path

using Win32

// Returns `path` as an absolute path, resolved against the current directory when it is relative.
func absolute(path: string)->String fail
{
    let winPath = Utf16.toZeroTerminated(path)

    var buffer: Array'u16
    buffer.reserve(100)
    var length: u64
    for
    {
        length = cast(u64, try GetFullPathNameW(winPath.buffer, cast(DWORD, buffer.capacity), buffer.buffer, null))
        if length < buffer.capacity do
            break

        // When the buffer is too small, the API returns the required size including its
        // terminator. Retry because the path or current directory may change between calls.
        buffer.reserve(length)
    }

    buffer.count = length
    var result = Utf8.fromUtf16(buffer.toSlice())
    normalize(&result)
    return result
}

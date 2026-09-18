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
    var length = cast(u64) try GetFullPathNameW(winPath.buffer, cast(DWORD) buffer.capacity, buffer.buffer, null)

    // The buffer was too small: the call returned the size it needs, terminator included.
    if length >= buffer.capacity
    {
        buffer.reserve(length)
        length = cast(u64) try GetFullPathNameW(winPath.buffer, cast(DWORD) buffer.capacity, buffer.buffer, null)
    }

    buffer.count = length
    var result = Utf8.fromUtf16(buffer.toSlice())
    normalize(&result)
    return result
}

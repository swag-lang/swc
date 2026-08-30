#global if WINDOWS
#global public
#global namespace Path

using Win32

// Transform 'fullname' to an absolute path
func absolute(fullname: string)->String fail
{
    var result: retval

    var tmpArr: Array'u16
    tmpArr.reserve(100)

    let winPath = Utf16.toZeroTerminated(fullname)
    var res     = cast(u64) try GetFullPathNameW(winPath.buffer, cast(DWORD) tmpArr.capacity, tmpArr.buffer, null)

    // No enough room in destination, give it another try
    if res >= 100
    {
        tmpArr.reserve(res + 1)
        res = cast(u64) try GetFullPathNameW(winPath.buffer, cast(DWORD) tmpArr.capacity, tmpArr.buffer, null)
    }

    tmpArr.count = res
    result       = Utf8.fromUtf16(tmpArr.toSlice())
    normalize(&result)
    return result
}

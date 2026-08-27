#global if WINDOWS
#global public
#global namespace Directory

using Win32

func createNative(dirname: string) fail
{
    let winPath = Utf16.toZeroTerminated(dirname)
    catch CreateDirectoryW(@dataof(winPath), null) as err
    Errors.transformWinErrors(err, dirname)
}

func deleteEmptyNative(dirName: string) fail
{
    let winPath = Utf16.toZeroTerminated(dirName)
    catch RemoveDirectoryW(@dataof(winPath)) as err
    Errors.transformWinErrors(err, dirName)
}

// Returns true if the given directory exists
func exists(dirName: string)->bool
{
    if @countof(dirName) == 0 do
        return false
    let winPath    = Utf16.toZeroTerminated(dirName)
    let attributes = catch GetFileAttributesW(@dataof(winPath)) as err
    if err != null do
        return false
    if attributes == 0xFFFFFFFF do
        return false
    if !(attributes & FILE_ATTRIBUTE_DIRECTORY) do
        return false
    return true
}

// Enumerates exactly one directory and returns normalized metadata for every native entry.
func enumerateOneNative(dirName: string)->Array'(File.FileInfo) fail
{
    using File
    var result:   retval
    var findfile: WIN32_FIND_DATAW
    var fileTime: SYSTEMTIME
    let dataof = cast(const [*] u16) @dataof(findfile.cFileName)
    var toScan = String.from(dirName)
    if toScan.back() == Path.VolumeSeparator do
        toScan += Path.DirectorySeparator
    let searchPath = Path.combine(toScan.toString(), "*")

    let winPath = Utf16.toZeroTerminated(searchPath)
    let handle  = try FindFirstFileExW(@dataof(winPath), .FindExInfoBasic, &findfile, .FindExSearchNameMatch, null, FIND_FIRST_EX_LARGE_FETCH)
    if handle == INVALID_HANDLE_VALUE do
        return result
    defer expect FindClose(handle)

    for
    {
        let fileName = Utf8.fromUtf16(@mkslice(dataof, Utf16.lengthUntilZero(findfile.cFileName)))
        var info: FileInfo
        info.fullname   = Path.combine(toScan.toString(), fileName.toString())
        info.attributes = FileAttributes.fromDWORD(findfile.dwFileAttributes)
        info.size       = findfile.nFileSizeLow + (cast(u64) findfile.nFileSizeHigh << 32)

        catch FileTimeToSystemTime(&findfile.ftCreationTime, &fileTime)
        info.creationTime.setWallClock(Time.wallClockFields(fileTime))
        catch FileTimeToSystemTime(&findfile.ftLastAccessTime, &fileTime)
        info.lastAccessTime.setWallClock(Time.wallClockFields(fileTime))
        catch FileTimeToSystemTime(&findfile.ftLastWriteTime, &fileTime)
        info.lastWriteTime.setWallClock(Time.wallClockFields(fileTime))
        result.add(#move info)

        let next = catch FindNextFileW(handle, &findfile)
        if !next do
            break
    }

    return result
}

// Returns the current directory
func currentPath()->String fail
{
    var result: retval
    let length = GetCurrentDirectoryW(0, null)

    var arr16: Array'u16
    arr16.reserve(cast(u64) length + 1)
    arr16.count = GetCurrentDirectoryW(length + 1, @dataof(arr16))

    result = Utf8.fromUtf16(arr16.toSlice())
    Path.normalize(&result)
    return result
}

// Set the current directory
func setCurrentPath(dirName: string) fail
{
    let winPath = Utf16.toZeroTerminated(dirName)
    catch SetCurrentDirectoryW(@dataof(winPath)) as err
    Errors.transformWinErrors(err, dirName)
}

// Get the list of logical drives
func drives()->Array'String fail
{
    var result:  retval
    var volName: [MAX_PATH] u8

    let slen = GetLogicalDriveStringsA(MAX_PATH, volName)
    if slen >= MAX_PATH do
        return result

    var ptr = cast([*] u8) &volName[0]
    while ptr[0]
    {
        let len = @countof(cast(cstring) ptr)
        result.add(@mkstring(ptr, len))
        ptr += len + 1
    }

    return result
}

// Get the list of volumes
func volumes()->Array'String fail
{
    var result: retval

    var volName:   [MAX_PATH] u8
    var driveName: [MAX_PATH] u8

    let h = FindFirstVolumeA(volName, MAX_PATH)
    if h == INVALID_HANDLE_VALUE do
        return result

    for
    {
        var ret: DWORD
        catch GetVolumePathNamesForVolumeNameA(volName, driveName, MAX_PATH, &ret) as err
        if err == null
        {
            let len = @countof(cast(cstring) driveName)
            if len
            {
                var str = String.from(@mkstring(&driveName[0], len))
                Path.normalize(&str)
                result.add(str)
            }
        }

        if !FindNextVolumeA(h, volName, MAX_PATH) do
            break
    }

    FindVolumeClose(h)
    return result
}

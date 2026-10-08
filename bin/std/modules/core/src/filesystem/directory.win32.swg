#global if WINDOWS
#global public
#global namespace Directory

using Win32

// Creates one directory on Windows; its parent must already exist.
internal func createNative(dirName: string) fail
{
    let winPath = Utf16.toZeroTerminated(dirName)
    catch CreateDirectoryW(winPath.buffer, null) as err
    try Errors.transformWinErrors(err, dirName)
}

// Removes an empty directory on Windows, failing if it cannot be removed.
internal func deleteEmptyNative(dirName: string) fail
{
    let winPath = Utf16.toZeroTerminated(dirName)
    catch RemoveDirectoryW(winPath.buffer) as err
    try Errors.transformWinErrors(err, dirName)
}

// Returns whether `dirName` names an existing directory.
//
// A file, an empty name, or a path the process cannot query reports false.
func exists(dirName: string)->bool
{
    if dirName.count == 0 do
        return false
    let winPath    = Utf16.toZeroTerminated(dirName)
    let attributes = catch GetFileAttributesW(winPath.buffer) as err
    if err != null or attributes == 0xFFFFFFFF do
        return false
    return (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0
}

// Enumerates exactly one directory and returns normalized metadata for every native entry.
internal func enumerateOneNative(dirName: string)->Array'(File.FileInfo) fail
{
    using File
    var result:   retval
    var findData: WIN32_FIND_DATAW
    var fileTime: SYSTEMTIME
    let fileNameBuffer = cast(const [*] u16, findData.cFileName.buffer)
    var scanPath       = String.from(dirName)
    if scanPath.back() == Path.VolumeSeparator do
        scanPath += Path.DirectorySeparator
    let searchPath = Path.combine(scanPath.toString(), "*")

    let winPath = Utf16.toZeroTerminated(searchPath)
    let handle  = try FindFirstFileExW(winPath.buffer,
                                       .FindExInfoBasic,
                                       &findData,
                                       .FindExSearchNameMatch,
                                       null,
                                       FIND_FIRST_EX_LARGE_FETCH)
    if handle == INVALID_HANDLE_VALUE do
        return result
    defer expect FindClose(handle)

    for
    {
        let fileName = Utf8.fromUtf16(Swag.makeSlice(fileNameBuffer, Utf16.lengthUntilZero(findData.cFileName)))
        with var info: FileInfo
        {
            .fullName   = Path.combine(scanPath.toString(), fileName.toString())
            .attributes = FileAttributes.fromDWORD(findData.dwFileAttributes)
            .size       = Math.make64(findData.nFileSizeHigh, findData.nFileSizeLow)
        }

        catch FileTimeToSystemTime(&findData.ftCreationTime, &fileTime)
        info.creationTime.setWallClock(Time.wallClockFields(fileTime))

        catch FileTimeToSystemTime(&findData.ftLastAccessTime, &fileTime)
        info.lastAccessTime.setWallClock(Time.wallClockFields(fileTime))

        catch FileTimeToSystemTime(&findData.ftLastWriteTime, &fileTime)
        info.lastWriteTime.setWallClock(Time.wallClockFields(fileTime))

        result.add(#move info)

        let next = catch FindNextFileW(handle, &findData)
        if not next do
            break
    }

    return result
}

// Returns the current directory of the process, with normalized separators.
func currentPath()->String fail
{
    let length = try GetCurrentDirectoryW(0, null)

    var arr16: Array'u16
    arr16.reserve(cast(u64, length) + 1)
    arr16.count = try GetCurrentDirectoryW(length + 1, arr16.buffer)

    var result = Utf8.fromUtf16(arr16.toSlice())
    Path.normalize(&result)
    return result
}

// Changes the current directory of the process to `dirName`.
func setCurrentPath(dirName: string) fail
{
    let winPath = Utf16.toZeroTerminated(dirName)
    catch SetCurrentDirectoryW(winPath.buffer) as err
    try Errors.transformWinErrors(err, dirName)
}

// Returns the root of every logical drive, such as `C:\`.
//
// The roots keep the native separator. Returns an empty array when the list does not fit the
// platform path limit.
func drives()->Array'String fail
{
    var result:     retval
    var volumeName: [MAX_PATH] u8

    let length = GetLogicalDriveStringsA(MAX_PATH, volumeName)
    if length >= MAX_PATH do
        return result

    var ptr = cast([*] u8, &volumeName[0])
    while ptr[0]
    {
        let len = cast(cstring, ptr).count
        result.add(Swag.makeString(ptr, len))
        ptr += len + 1
    }

    return result
}

// Returns the first mount point of every mounted volume, with normalized separators.
//
// A volume without a mount point is skipped.
func volumes()->Array'String fail
{
    var result: retval

    var volumeName: [MAX_PATH] u8
    var driveName:  [MAX_PATH] u8

    let handle = try FindFirstVolumeA(volumeName, MAX_PATH)
    if handle == INVALID_HANDLE_VALUE do
        return result
    defer discard catch FindVolumeClose(handle)

    for
    {
        var requiredLength: DWORD
        catch GetVolumePathNamesForVolumeNameA(volumeName, driveName, MAX_PATH, &requiredLength) as err
        if err == null
        {
            let length = cast(cstring, driveName).count
            if length
            {
                var mountPoint = String.from(Swag.makeString(&driveName[0], length))
                Path.normalize(&mountPoint)
                result.add(#move mountPoint)
            }
        }

        if not (try FindNextVolumeA(handle, volumeName, MAX_PATH)) do
            break
    }

    return result
}

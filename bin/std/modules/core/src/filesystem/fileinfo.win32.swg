#global if WINDOWS
#global public
#global namespace File

using Win32

// Returns metadata for a file or directory.
func info(fullName: string)->FileInfo fail
{
    var attributes: WIN32_FILE_ATTRIBUTE_DATA

    let winPath = Utf16.toZeroTerminated(fullName)
    catch GetFileAttributesExW(winPath.buffer, GET_FILEEX_INFO_LEVELS.GetFileExInfoStandard, &attributes)
    {
        try Errors.transformWinErrors(Swag.err, fullName)
        fail Swag.err
    }

    with var result: #returntype
    {
        .fullName   = fullName
        .attributes = FileAttributes.fromDWORD(attributes.dwFileAttributes)
        .size       = Math.make64(attributes.nFileSizeHigh, attributes.nFileSizeLow)
    }

    var fileTime: SYSTEMTIME
    catch FileTimeToSystemTime(&attributes.ftCreationTime, &fileTime)
    result.creationTime.setWallClock(Time.wallClockFields(fileTime))

    catch FileTimeToSystemTime(&attributes.ftLastAccessTime, &fileTime)
    result.lastAccessTime.setWallClock(Time.wallClockFields(fileTime))

    catch FileTimeToSystemTime(&attributes.ftLastWriteTime, &fileTime)
    result.lastWriteTime.setWallClock(Time.wallClockFields(fileTime))

    return result
}

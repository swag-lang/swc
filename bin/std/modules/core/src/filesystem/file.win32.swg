#global if WINDOWS
#global public
#global namespace File

using Win32

func deleteNative(fullName: string) fail
{
    let winPath = Utf16.toZeroTerminated(fullName)
    catch DeleteFileW(winPath.buffer) as err
    Errors.transformWinErrors(err, fullName)
}

func moveNative(newName, oldName: string) fail
{
    let winOld = Utf16.toZeroTerminated(oldName)
    let winNew = Utf16.toZeroTerminated(newName)
    catch MoveFileExW(winOld.buffer, winNew.buffer, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED) as err
    Errors.transformWinErrors(err, oldName)
}

func touchNative(fullName: string) fail
{
    let winPath = Utf16.toZeroTerminated(fullName)

    let hFile = catch CreateFileW(winPath.buffer, FILE_WRITE_ATTRIBUTES, 0, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null) as err
    Errors.transformWinErrors(err, fullName)
    defer CloseHandle(hFile)

    var ft: FILETIME
    var st: SYSTEMTIME
    GetSystemTime(&st)
    SystemTimeToFileTime(&st, &ft)
    SetFileTime(hFile, null, null, &ft)
}

// Returns true if the given file exists
func exists(fullName: string)->bool
{
    if fullName == null do
        return false
    let safeName   = fullName orelse ""
    let winPath    = Utf16.toZeroTerminated(safeName)
    let attributes = catch GetFileAttributesW(winPath.buffer) as err
    if err != null do
        return false
    if attributes == 0xFFFFFFFF do
        return false
    if attributes & FILE_ATTRIBUTE_DIRECTORY do
        return false
    return true
}

func openNative(fullName: string, mode: FileMode, access: FileAccess, share: FileShare)->FileHandle fail
{
    var wMode: DWORD
    switch mode
    {
    case .Append:       wMode = OPEN_ALWAYS
    case .Create:       wMode = CREATE_ALWAYS
    case .CreateNew:    wMode = CREATE_NEW
    case .Open:         wMode = OPEN_EXISTING
    case .OpenOrCreate: wMode = OPEN_ALWAYS
    case .Truncate:     wMode = TRUNCATE_EXISTING
    }

    var wAccess: DWORD
    if access & FileAccess.Read
    {
        wAccess |= GENERIC_READ
    }

    if access & FileAccess.Write
    {
        wAccess |= GENERIC_WRITE
    }

    // Share mode
    var wShare: DWORD
    if share & FileShare.Read do
        wShare |= FILE_SHARE_READ
    if share & FileShare.Write do
        wShare |= FILE_SHARE_WRITE
    if share & FileShare.Delete do
        wShare |= FILE_SHARE_DELETE

    var security:    SECURITY_ATTRIBUTES
    var securityPtr: *SECURITY_ATTRIBUTES?
    if share.has(.Inheritable)
    {
        security.nLength        = #sizeof(SECURITY_ATTRIBUTES)
        security.bInheritHandle = TRUE
        securityPtr             = &security
    }

    let winPath = Utf16.toZeroTerminated(fullName)
    let hFile   = catch CreateFileW(winPath.buffer, wAccess, wShare, securityPtr, wMode, FILE_ATTRIBUTE_NORMAL, null) as err
    Errors.transformWinErrors(err, fullName)
    return cast(FileHandle) hFile
}

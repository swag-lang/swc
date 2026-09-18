#global if WINDOWS
#global public
#global namespace File

using Win32

// Deletes a file on Windows, reporting an OS failure through a filesystem error.
internal func deleteNative(fullName: string) fail
{
    let winPath = Utf16.toZeroTerminated(fullName)
    catch DeleteFileW(winPath.buffer) as err
    try Errors.transformWinErrors(err, fullName)
}

// Moves `oldName` to `newName`, replacing an existing file and permitting a cross-volume copy.
internal func moveNative(newName, oldName: string) fail
{
    let winOld = Utf16.toZeroTerminated(oldName)
    let winNew = Utf16.toZeroTerminated(newName)
    catch MoveFileExW(winOld.buffer, winNew.buffer, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED) as err
    try Errors.transformWinErrors(err, oldName)
}

// Opens an existing file exclusively and sets its modification time to the current UTC time.
internal func touchNative(fullName: string) fail
{
    let winPath = Utf16.toZeroTerminated(fullName)

    let hFile = catch CreateFileW(winPath.buffer, FILE_WRITE_ATTRIBUTES, 0, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null) as err
    try Errors.transformWinErrors(err, fullName)
    defer CloseHandle(hFile)

    var ft: FILETIME
    var st: SYSTEMTIME
    GetSystemTime(&st)
    try SystemTimeToFileTime(&st, &ft)
    try SetFileTime(hFile, null, null, &ft)
}

// Returns whether `fullName` names an existing file.
//
// A directory, an empty name, or a path the process cannot query reports false.
func exists(fullName: string)->bool
{
    if fullName.count == 0 do
        return false
    let winPath    = Utf16.toZeroTerminated(fullName)
    let attributes = catch GetFileAttributesW(winPath.buffer) as err
    if err != null or attributes == 0xFFFFFFFF do
        return false
    return (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0
}

// Opens a Windows file handle with the requested mode, access, and sharing policy.
internal func openNative(fullName: string, mode: FileMode, access: FileAccess, share: FileShare)->FileHandle fail
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
    if access.has(.Read) do
        wAccess |= GENERIC_READ
    if access.has(.Write) do
        wAccess |= GENERIC_WRITE

    var wShare: DWORD
    if share.has(.Read) do
        wShare |= FILE_SHARE_READ
    if share.has(.Write) do
        wShare |= FILE_SHARE_WRITE
    if share.has(.Delete) do
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
    try Errors.transformWinErrors(err, fullName)
    return cast(FileHandle) hFile
}

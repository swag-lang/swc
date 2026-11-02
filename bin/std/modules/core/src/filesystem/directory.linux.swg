#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Directory

internal func createNative(dirName: string) fail
{
    let native = try Path.nativePath(dirName)
    for
    {
        // The process umask removes permissions from the usual directory creation mode.
        if Linux.mkdirat(Linux.AT_FDCWD, native.storage(), 0x1FF) == 0 do
            return
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, dirName)
    }
}

internal func deleteEmptyNative(dirName: string) fail
{
    let native = try Path.nativePath(dirName)
    for
    {
        if Linux.unlinkat(Linux.AT_FDCWD, native.storage(), Linux.AT_REMOVEDIR) == 0 do
            return
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, dirName)
    }
}

// Returns whether `dirName` names an existing directory, following symbolic links.
//
// An empty or invalid name, a missing target, or a path the process cannot query returns false.
func exists(dirName: string)->bool
{
    let info = catch File.nativePathInfo(dirName) { return false }
    return (info.st_mode & Linux.S_IFMT) == Linux.S_IFDIR
}

// Returns the absolute current directory of the process.
//
// Fails when the current directory has been removed or cannot be represented by the host.
func currentPath()->String fail
{
    var buffer: Array'u8
    buffer.reserve(256)
    for
    {
        if Linux.getcwd(buffer.storage(), buffer.capacity) do
            return String.from(cast(string, cast(cstring, buffer.storage())))
        let error = Linux.errno()
        if error == Linux.EINTR do
            continue
        if error != Linux.ERANGE do
            try Errors.failLinuxError(error)
        if buffer.capacity > Swag.U64.Max / 2 do
            fail Errors.OverflowError{}
        buffer.reserve(buffer.capacity * 2)
    }
}

// Changes the process current directory; the change affects every thread in the process.
func setCurrentPath(dirName: string) fail
{
    let native = try Path.nativePath(dirName)
    for
    {
        if Linux.chdir(native.storage()) == 0 do
            return
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, dirName)
    }
}

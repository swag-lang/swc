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
        if error == Linux.ENOTDIR
        {
            let metadata = try File.nativePathInfo(dirName, Linux.AT_SYMLINK_NOFOLLOW)
            if (metadata.st_mode & Linux.S_IFMT) == Linux.S_IFLNK
            {
                try File.deleteNative(dirName)
                return
            }
        }

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

internal func enumerateOneNative(dirName: string)->Array'(File.FileInfo) fail
{
    let native = try Path.nativePath(dirName)
    var directory: *void?
    for
    {
        directory = Linux.opendir(native.storage())
        if directory do
            break
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, dirName)
    }

    let opened = unwrap directory
    defer discard Linux.closedir(opened)
    let descriptor = Linux.dirfd(opened)
    if descriptor < 0 do
        try Errors.failLinuxError(Linux.errno(), dirName)
    var result: #returntype
    for
    {
        // A null result can mean EOF or failure; only this call's errno distinguishes them.
        Linux.errno(0)
        let entry = Linux.readdir(opened)
        if not entry
        {
            let error = Linux.errno()
            if error == Linux.EINTR do
                continue
            if error != 0 do
                try Errors.failLinuxError(error, dirName)
            return result
        }

        let name     = cast(string, cast(cstring, &entry.d_name[0]))
        let fullName = Path.combine(dirName, name)
        var info     = try File.nativeInfoAt(descriptor, name, fullName)
        result.add(#move info)
    }
}

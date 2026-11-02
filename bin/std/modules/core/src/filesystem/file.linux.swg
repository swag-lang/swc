#global if #os == Swag.TargetOs.Linux
#global public
#global namespace File

internal func nativePathInfo(path: string, flags: s32 = 0)->Linux.stat fail
{
    let native = try Path.nativePath(path)
    var result: #returntype
    for
    {
        if Linux.fstatat(Linux.AT_FDCWD, native.storage(), &result, flags) == 0 do
            return result
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, path)
    }
}

// Returns whether `fullName` names an existing entry other than a directory.
//
// Symbolic links are followed. An empty or invalid name, a missing target, or a path the
// process cannot query returns false.
func exists(fullName: string)->bool
{
    let info = catch nativePathInfo(fullName) { return false }
    return (info.st_mode & Linux.S_IFMT) != Linux.S_IFDIR
}

internal func deleteNative(fullName: string) fail
{
    let native = try Path.nativePath(fullName)
    for
    {
        if Linux.unlinkat(Linux.AT_FDCWD, native.storage(), 0) == 0 do
            return
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, fullName)
    }
}

internal func moveNative(newName, oldName: string) fail
{
    let source      = try Path.nativePath(oldName)
    let destination = try Path.nativePath(newName)
    for
    {
        if Linux.renameat(Linux.AT_FDCWD, source.storage(), Linux.AT_FDCWD, destination.storage()) == 0 do
            return
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, oldName)
    }
}

internal func touchNative(fullName: string) fail
{
    let native = try Path.nativePath(fullName)
    let times: [2] Linux.timespec = [{tv_nsec: Linux.UTIME_OMIT}, {tv_nsec: Linux.UTIME_NOW}]
    for
    {
        if Linux.utimensat(Linux.AT_FDCWD, native.storage(), times.buffer, 0) == 0 do
            return
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, fullName)
    }
}

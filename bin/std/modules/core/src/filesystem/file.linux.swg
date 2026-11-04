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

internal func openNative(fullName: string, mode: FileMode, access: FileAccess, share: FileShare)->FileHandle fail
{
    let native = try Path.nativePath(fullName)
    var flags  = Linux.O_NOCTTY
    switch access
    {
    case .Read:      flags |= Linux.O_RDONLY
    case .Write:     flags |= Linux.O_WRONLY
    case .ReadWrite: flags |= Linux.O_RDWR
    default:         fail Errors.BadParameterError{"file access must request reading, writing, or both"}
    }

    if (mode == .Create or mode == .Truncate) and not access.has(.Write) do
        fail Errors.BadParameterError{"creating or truncating a file requires write access"}
    let validShare = FileShare.ReadWrite | .Delete | .Inheritable
    if (share & ~validShare) != .Zero do
        fail Errors.BadParameterError{"file sharing contains an unknown flag"}
    if not share.has(.Inheritable) do
        flags |= Linux.O_CLOEXEC
    switch #complete mode
    {
    case .Append, .OpenOrCreate: flags |= Linux.O_CREAT
    case .Create:    flags |= Linux.O_CREAT | Linux.O_TRUNC
    case .CreateNew: flags |= Linux.O_CREAT | Linux.O_EXCL
    case .Open:      break
    case .Truncate:  flags |= Linux.O_TRUNC
    }

    // Append is an initial seek in the common API. O_APPEND would also force later writes
    // to the end, contradicting the caller's subsequent explicit seeks.
    var descriptor: s32
    for
    {
        descriptor = Linux.openat(Linux.AT_FDCWD, native.storage(), flags, 0x1B6'u32)
        if descriptor >= 0 do
            break
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, fullName)
    }

    var owned = false
    defer if not owned do
        discard Linux.close(descriptor)
    var info: Linux.stat
    for
    {
        if Linux.fstat(descriptor, &info) == 0 do
            break
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, fullName)
    }

    if (info.st_mode & Linux.S_IFMT) == Linux.S_IFDIR do
        try Errors.failLinuxError(Linux.EISDIR, fullName)
    owned = true
    return nativeFileHandle(descriptor)
}

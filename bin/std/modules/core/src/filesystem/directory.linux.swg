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

// Returns the accessible directory mount points in the process's Linux mount namespace.
//
// Each path is absolute and ends in `/`; the root is `/`. Duplicate mount points and
// mounts on individual files are omitted. This includes virtual filesystems and bind mounts,
// not only physical disks. Fails when `/proc/self/mountinfo` cannot be read or decoded.
func drives()->Array'String fail
{
    let mounts = try File.readAllText("/proc/self/mountinfo")
    var result: #returntype
    for line in Tokenize.splitLines(mounts)
    {
        var path = try mountPointNative(line)
        if not exists(path) do
            continue
        if path[path.length - 1] != '/' do
            path += '/'u8
        var duplicate = false
        for &previous in result where previous[] == path do
            duplicate = true
        if not duplicate do
            result.add(#move path)
    }

    return result
}

internal func mountPointNative(line: string)->String fail
{
    let fields = Tokenize.split(line, ' 'u8)
    if fields.count < 10 or fields[4].count == 0 or fields[4][0] != '/' do
        fail Errors.InvalidFormatError{"invalid Linux mount information"}
    let encoded = fields[4]
    var result: #returntype
    var index   = 0'u64
    while index < encoded.count
    {
        if encoded[index] != '\\'
        {
            result += encoded[index]
            index  += 1
            continue
        }

        if encoded.count - index < 4 do
            fail Errors.InvalidFormatError{"incomplete Linux mount path escape"}
        let escape = encoded[index + 1 until index + 4]
        switch escape
        {
        case "040": result += ' 'u8
        case "011": result += '\t'u8
        case "012": result += '\n'u8
        case "134": result += '\\'u8
        default:    fail Errors.InvalidFormatError{"invalid Linux mount path escape"}
        }

        index += 4
    }

    return result
}

// Returns whether the filesystem holding `path` is a recognized remote filesystem.
//
// Follows symbolic links and uses the closest existing ancestor when the final path does
// not yet exist. Mount IDs distinguish bind mounts and overlapping mount points. Recognized
// types include NFS, SMB/CIFS, AFS, Ceph, 9P and common network FUSE drivers. An invalid path,
// inaccessible ancestor, unreadable procfs, or unrecognized filesystem returns `false`.
// This is a storage classification, not a reachability check or an estimate of I/O latency.
func isRemote(path: string)->bool
{
    var candidate       = catch Path.absolute(path) { return false }
    var descriptor: s32 = -1
    for
    {
        descriptor = Linux.openat(Linux.AT_FDCWD, candidate.storage(), Linux.O_PATH | Linux.O_CLOEXEC)
        if descriptor >= 0 do
            break
        let error = Linux.errno()
        if error == Linux.EINTR do
            continue
        if error != Linux.ENOENT do
            return false
        let parent = Path.directoryName(candidate)
        if not parent do
            return false
        candidate = String.from(parent)
    }

    defer discard Linux.close(descriptor)
    let infoPath = Format.toString("/proc/self/fdinfo/%", descriptor)
    let info     = catch File.readAllText(infoPath) { return false }
    var mountId  = 0'u64
    for line in Tokenize.splitLines(info) where Utf8.startsWith(line, "mnt_id:")
    {
        mountId = catch StrConv.toU64(Latin1.trim(line[7 to])) { return false }
        break
    }

    if mountId == 0 do
        return false
    let mounts = catch File.readAllText("/proc/self/mountinfo") { return false }
    return remoteMountNative(mounts, mountId)
}

internal func remoteMountNative(mounts: string, mountId: u64)->bool
{
    for line in Tokenize.splitLines(mounts)
    {
        let fields = Tokenize.split(line, ' 'u8)
        if fields.count < 10 do
            continue
        let id = catch StrConv.toU64(fields[0]) { continue }
        if id != mountId do
            continue
        for index in 6'u64 until fields.count where fields[index] == "-"
        {
            if index + 3 >= fields.count do
                return false
            let kind = fields[index + 1]
            switch kind
            {
            case "nfs", "nfs4", "cifs", "smb3", "smbfs", "afs", "coda", "ncpfs",
                 "ceph", "9p", "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.gcsfuse",
                 "fuse.glusterfs", "fuse.curlftpfs", "fuse.davfs", "fuse.gvfsd-fuse":
                return true

            default: return false
            }
        }

        return false
    }

    return false
}

// Returns the free bytes reported as available to unprivileged users on this filesystem.
//
// `dirName` must name an existing directory; symbolic links are followed. Fails for a file,
// missing or inaccessible path, a failed filesystem query, or a byte count exceeding `u64`.
// The filesystem's available-block count need not account for every per-user quota; allocation
// can still fail because of quotas or concurrent writes after this snapshot.
func freeSpace(dirName: string)->u64 fail
{
    let native = try Path.nativePath(dirName)
    var descriptor: s32 = -1
    for
    {
        descriptor = Linux.openat(Linux.AT_FDCWD, native.storage(), Linux.O_PATH | Linux.O_DIRECTORY | Linux.O_CLOEXEC)
        if descriptor >= 0 do
            break
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, dirName)
    }

    defer discard Linux.close(descriptor)
    var space: Linux.statvfs
    for
    {
        if Linux.fstatvfs(descriptor, &space) == 0 do
            break
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error, dirName)
    }

    if space.f_frsize == 0 do
        try Errors.failLinuxError(Linux.EIO, dirName)
    if space.f_bavail > Swag.U64.Max / space.f_frsize do
        fail Errors.OverflowError{}
    return space.f_bavail * space.f_frsize
}

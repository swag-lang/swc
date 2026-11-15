#global if #os == Swag.TargetOs.Linux
#global namespace Env

internal impl SessionInstance
{
    mtd acquireNative(id: string)->bool fail
    {
        let userDirectory = getSpecialDirectory(.UserAppData)
        if not Path.isRooted(userDirectory) do
            fail Errors.BadParameterError{}
        let root = Path.combine(userDirectory, "swag", "instances")
        try Directory.create(root, recurse: true)
        let session    = Format.toString("%:%", variable("XDG_SESSION_ID"), variable("DISPLAY"))
        let path       = Path.combine(root, Format.toString("%.%.lock", id, Hash.hash64(session)))
        let descriptor = Linux.openat(Linux.AT_FDCWD, path.storage(), Linux.O_RDWR | Linux.O_CREAT | Linux.O_CLOEXEC | Linux.O_NOFOLLOW, 0x180)
        if descriptor < 0 do
            try Errors.failLinuxError(Linux.errno())
        defer if not .handle do
            discard Linux.close(descriptor)
        var info: Linux.stat
        if Linux.fstat(descriptor, &info) != 0 do
            try Errors.failLinuxError(Linux.errno())
        if info.st_uid != Linux.getuid() or (info.st_mode & Linux.S_IFMT) != Linux.S_IFREG do
            fail Errors.BadParameterError{}
        if Linux.flock(descriptor, Linux.LOCK_EX | Linux.LOCK_NB) != 0
        {
            if Linux.errno() == Linux.EAGAIN do
                return false
            try Errors.failLinuxError(Linux.errno())
        }

        .handle = cast(*void, cast(u64, descriptor) + 1)
        return true
    }

    mtd closeNative()
    {
        discard Linux.close(cast(s32, cast(u64, .handle) - 1))
        .handle = null
    }
}

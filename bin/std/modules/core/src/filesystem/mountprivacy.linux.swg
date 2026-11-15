#global if #os == Swag.TargetOs.Linux
#global public
#global namespace File

internal func mountPrivacyPathNative(path: string)->String => Env.absolutePath(path)

internal func mountPrivacyProtectedRootNative(path: string)->String
{
    let mounts = catch File.readAllText("/proc/self/mountinfo") { return {} }
    var result: String
    for line in Tokenize.splitLines(mounts)
    {
        let fields = Tokenize.split(line, ' 'u8)
        var vault  = false
        for index in 6'u64 until fields.count where fields[index] == "-" and index + 1 < fields.count do
            vault = fields[index + 1] == "fuse.swagvault"
        if not vault do
            continue
        let root = catch Directory.mountPointNative(line) { continue }
        if (path == root or Utf8.startsWith(path, Format.toString("%/", root))) and root.count > result.count do
            result = root
    }

    return result
}

internal func privacySharedName(channel: string)->String => Format.toString("/%.%", channel, Linux.getuid())

internal impl MountPrivacyPublisher
{
    mtd openNative() fail
    {
        let name       = privacySharedName(.channel)
        let descriptor = Linux.shm_open(name.storage(), Linux.O_RDWR | Linux.O_CREAT | Linux.O_CLOEXEC, 0x180)
        if descriptor < 0 do
            try Errors.failLinuxError(Linux.errno())
        defer if not .handle do
            discard Linux.close(descriptor)
        var info: Linux.stat
        if Linux.fstat(descriptor, &info) != 0 do
            try Errors.failLinuxError(Linux.errno())
        if info.st_uid != Linux.getuid() or (info.st_mode & 0x3F) != 0 do
            fail Errors.BadParameterError{}

        // The kernel releases ownership after a crash. A new owner can safely reinitialize
        // an abandoned object, including a crash before its first snapshot was committed.
        if Linux.flock(descriptor, Linux.LOCK_EX | Linux.LOCK_NB) != 0 do
            try Errors.failLinuxError(Linux.errno())
        if Linux.ftruncate(descriptor, #sizeof(MountPrivacyData)) != 0 do
            try Errors.failLinuxError(Linux.errno())
        let view = Linux.mmap(null, #sizeof(MountPrivacyData), Linux.PROT_READ | Linux.PROT_WRITE, Linux.MAP_SHARED, descriptor, 0)
        if not view or cast(s64, view) == -1 do
            try Errors.failLinuxError(Linux.errno())
        .data   = assume cast(*MountPrivacyData, view)
        .handle = cast(*void, cast(u64, descriptor) + 1)
        Atomic.exchange(&.data.sequence, 0)
    }

    mtd closeNative()
    {
        let name = privacySharedName(.channel)
        discard Linux.shm_unlink(name.storage())
        discard Linux.munmap(.data, #sizeof(MountPrivacyData))
        .data = null
        discard Linux.close(cast(s32, cast(u64, .handle) - 1))
        .handle = null
    }
}

internal func readMountPrivacyNative(channel: string, result: *MountPrivacy)->bool
{
    let name       = privacySharedName(channel)
    let descriptor = Linux.shm_open(name.storage(), Linux.O_RDONLY | Linux.O_CLOEXEC, 0)
    if descriptor < 0 do
        return false
    var attached = false
    defer if not attached do
        discard Linux.close(descriptor)
    var info: Linux.stat
    if Linux.fstat(descriptor, &info) != 0 or
       info.st_size != #sizeof(MountPrivacyData) or
       info.st_uid != Linux.getuid() or
       (info.st_mode & 0x3F) != 0 do
        return false
    let view = Linux.mmap(null, #sizeof(MountPrivacyData), Linux.PROT_READ, Linux.MAP_SHARED, descriptor, 0)
    if not view or cast(s64, view) == -1 do
        return false
    defer if not attached do
        discard Linux.munmap(view, #sizeof(MountPrivacyData))
    let data = assume cast(*MountPrivacyData, view)

    // An unlocked object has no live publisher, even if its last committed flags were public.
    if Linux.flock(descriptor, Linux.LOCK_SH | Linux.LOCK_NB) == 0 do
        return false
    if Linux.errno() != Linux.EAGAIN do
        return false
    if (Atomic.get(&data.flags) & 2) == 0 or not readMountPrivacyData(data, result) do
        return false
    let reader = Memory.new'MountPrivacyReader()
    reader.handle = cast(*void, cast(u64, descriptor) + 1)
    reader.data   = data
    result.reader = reader
    attached      = true
    return true
}

internal func closeMountPrivacyReaderNative(reader: *MountPrivacyReader)
{
    discard Linux.munmap(reader.data, #sizeof(MountPrivacyData))
    discard Linux.close(cast(s32, cast(u64, reader.handle) - 1))
}

#global if #os == Swag.TargetOs.Linux
#global namespace File

internal impl MappedRegion
{
    mtd mapNative(sourceHandle: FileHandle, offset, length: u64, access: MapAccess) fail
    {
        let pageSize      = cast(u64, Linux.getpagesize())
        let alignedOffset = offset / pageSize * pageSize
        let prefix        = offset - alignedOffset
        if length > Swag.U64.Max - prefix or alignedOffset > cast(u64, Swag.S64.Max) do
            fail Errors.OverflowError{}
        let mappedLength = length + prefix

        var descriptor = -1's32
        for
        {
            descriptor = Linux.fcntl(nativeFileDescriptor(sourceHandle), Linux.F_DUPFD_CLOEXEC, 0's32)
            if descriptor >= 0 do
                break
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error)
        }

        defer if not .fileHandle do
            discard Linux.close(descriptor)

        var protection = Linux.PROT_READ
        if access != .Read do
            protection |= Linux.PROT_WRITE
        let flags = access == .CopyOnWrite ? Linux.MAP_PRIVATE : Linux.MAP_SHARED
        let view  = Linux.mmap(null, mappedLength, protection, flags, descriptor, cast(s64, alignedOffset))
        if cast(s64, view) == -1 do
            try Errors.failLinuxError(Linux.errno())
        if not view
        {
            discard Linux.munmap(view, mappedLength)
            fail Swag.SystemError{"the mapped file has an unusable null address"}
        }

        .fileHandle = nativeFileHandle(descriptor)
        .nativeView = view
        .view       = cast([*] u8, view) + prefix
    }

    mtd closeNative()
    {
        if .nativeView
        {
            let prefix = cast(u64, .view) - cast(u64, .nativeView)
            discard Linux.munmap(.nativeView, .length + prefix)
            .nativeView = null
            .view       = null
        }

        if .fileHandle
        {
            discard Linux.close(nativeFileDescriptor(.fileHandle))
            .fileHandle = null
        }

        .mapHandle = null
        .length    = 0
        .offset    = 0
        .valid     = false
    }

    mtd flushNative() fail
    {
        let prefix = cast(u64, .view) - cast(u64, .nativeView)
        for
        {
            if Linux.msync(unwrap .nativeView, .length + prefix, Linux.MS_SYNC) == 0 do
                break
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error)
        }

        for
        {
            if Linux.fsync(nativeFileDescriptor(.fileHandle)) == 0 do
                return
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error)
        }
    }

    func releasePagesNative(bytes: const [..] u8)
    {
        let pageSize = cast(u64, Linux.getpagesize())
        let address  = cast(u64, bytes.buffer)
        let start    = address / pageSize * pageSize
        let prefix   = address - start
        if bytes.count > Swag.U64.Max - prefix do
            return

        // Unlike MADV_DONTNEED, PAGEOUT preserves private dirty and anonymous bytes.
        // Unsupported or pinned pages may remain resident: this is only an accounting hint.
        discard Linux.madvise(cast(*void, start), prefix + bytes.count, Linux.MADV_PAGEOUT)
    }
}

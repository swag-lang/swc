#global if #os == Swag.TargetOs.Linux

using Core

namespace Fuse
{
    // The container records Windows attributes and security descriptors, not Unix ownership
    // or mode bits. Linux projects them for the mounting user: directories 0700, files 0600,
    // with owner write removed for read-only files. Existing security records remain intact.
    // Unsupported chmod/chown requests fail instead of claiming to have persisted metadata.
    const UnixEpoch = 116_444_736_000_000_000'u64

    func statusFromError(err: any?)->s32
    {
        if err is Error as error
        {
            switch error.kind
            {
            case .InvalidInput, .PasswordRequired, .SizeTooSmall, .SparseContainer: return -Linux.EINVAL
            case .NotFound: return -Linux.ENOENT
            case .AlreadyExists: return -Linux.EEXIST
            case .AccessDenied: return -Linux.EACCES
            case .HiddenProtected, .WriteProtected: return -Linux.EROFS
            case .NotDirectory: return -Linux.ENOTDIR
            case .IsDirectory: return -Linux.EISDIR
            case .DirectoryNotEmpty: return -Linux.ENOTEMPTY
            case .DiskFull: return -Linux.ENOSPC
            }
        }
        return -Linux.EIO
    }

    func pathString(path: const [*] u8?)->string fail
    {
        if not path do fail volumeError(.InvalidInput)
        var length = 0'u64
        while path[length] do length += 1
        let result = Swag.makeString(path, length)
        if not Utf8.isValid(result) do fail volumeError(.InvalidInput)
        // Volume paths also recognize backslashes; they cannot represent this POSIX name.
        for byte in result where byte == '\\' do fail volumeError(.InvalidInput)
        return result
    }

    func lookup(owner: *MountedVolume, path: const [*] u8?, info: *Linux.fuse_file_info?)->*Node fail
    {
        var node: *Node?
        if info and info.fh do node = owner.volume.nodeById(info.fh)
        else do node = owner.volume.resolve(try pathString(path))
        if not node do fail volumeError(.NotFound)
        return node
    }

    func mode(node: const *Node)->u32
    {
        let base = node.isDirectory() ? Linux.S_IFDIR | 0x1C0 : Linux.S_IFREG | 0x180
        return (node.attributes & FileAttributeReadOnly) != 0 ? base & ~Linux.S_IWUSR : base
    }

    func unixTime(value: u64)->Linux.timespec
    {
        let seconds = cast(s64, value / 10_000_000) - 11_644_473_600
        return {tv_sec: seconds, tv_nsec: cast(s64, value % 10_000_000) * 100}
    }

    func volumeTime(value: Linux.timespec, previous: u64)->u64 fail
    {
        if value.tv_nsec == Linux.UTIME_OMIT do return previous
        if value.tv_nsec == Linux.UTIME_NOW do return volumeTimeNow()
        if value.tv_nsec < 0 or value.tv_nsec >= 1_000_000_000 or value.tv_sec < -11_644_473_600 or
           value.tv_sec > cast(s64, (Swag.U64.Max - UnixEpoch - 9_999_999) / 10_000_000) do
            fail volumeError(.InvalidInput)
        return cast(u64, value.tv_sec + 11_644_473_600) * 10_000_000 + cast(u64, value.tv_nsec / 100)
    }

    func fillStat(owner: *MountedVolume, node: *Node, output: *Linux.stat)->s32
    {
        if node.size > cast(u64, Swag.S64.Max) do return -Linux.EOVERFLOW
        output[] = {}
        output.st_ino = node.id
        output.st_mode = mode(node)
        output.st_nlink = node.isDirectory() ? 2 : 1
        if node.isDirectory()
        {
            var child = owner.volume.firstChild(node.id)
            while child
            {
                if child.isDirectory() do output.st_nlink += 1
                child = owner.volume.nextSibling(child.id)
            }
        }
        output.st_uid = owner.uid
        output.st_gid = owner.gid
        output.st_size = cast(s64, node.size)
        output.st_blksize = cast(s64, BlockSize)
        var allocated = 0'u64
        for mapping in node.blocks do allocated += mapping.count
        output.st_blocks = cast(s64, allocated * (BlockSize / 512))
        output.st_atim = unixTime(node.lastAccessTime)
        output.st_mtim = unixTime(node.lastWriteTime)
        output.st_ctim = unixTime(node.changeTime)
        return 0
    }

    func writable(owner: *MountedVolume, node: *Node)->s32
    {
        if owner.volume.readOnly do return -Linux.EROFS
        if node.attributes & FileAttributeReadOnly do return -Linux.EACCES
        return 0
    }

    func commit(owner: *MountedVolume)->s32
    {
        if not owner.volume.readOnly and owner.volume.dirty
        {
            catch owner.volume.commit() { return statusFromError(Swag.err) }
        }
        return 0
    }

    func callbackGetattr(owner: *MountedVolume, path: const [*] u8, output: *Linux.stat, info: *Linux.fuse_file_info?)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        return fillStat(owner, node, output)
    }

    #[Swag.CallingConvention(.C)]
    private func getattr(path: const [*] u8, output: *Linux.stat, info: *Linux.fuse_file_info?)->s32
        => callbackGetattr(current(), path, output, info)

    func callbackMkdir(owner: *MountedVolume, path: const [*] u8, permissions: u32)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let value = catch pathString(path) { return statusFromError(Swag.err) }
        // Creation projects the requested mode into the documented private owner namespace.
        let attributes = (permissions & Linux.S_IWUSR) == 0 ? FileAttributeReadOnly : 0'u32
        discard catch owner.volume.createNode(value, true, attributes, "") { return statusFromError(Swag.err) }
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func mkdir(path: const [*] u8, permissions: u32)->s32
        => callbackMkdir(current(), path, permissions)

    func callbackCreate(owner: *MountedVolume, path: const [*] u8, permissions: u32, info: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let value = catch pathString(path) { return statusFromError(Swag.err) }
        let attributes = (permissions & Linux.S_IWUSR) == 0 ? FileAttributeReadOnly : 0'u32
        info.fh = catch owner.volume.createNode(value, false, attributes, "") { return statusFromError(Swag.err) }
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func create(path: const [*] u8, permissions: u32, info: *Linux.fuse_file_info)->s32
        => callbackCreate(current(), path, permissions, info)

    func callbackOpen(owner: *MountedVolume, path: const [*] u8, info: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        let node = catch lookup(owner, path, null) { return statusFromError(Swag.err) }
        if node.isDirectory() do return -Linux.EISDIR
        if (info.flags & 3) != Linux.O_RDONLY
        {
            let status = writable(owner, node)
            if status do return status
        }
        info.fh = node.id
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func open(path: const [*] u8, info: *Linux.fuse_file_info)->s32
        => callbackOpen(current(), path, info)

    func callbackOpendir(owner: *MountedVolume, path: const [*] u8, info: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        let node = catch lookup(owner, path, null) { return statusFromError(Swag.err) }
        if not node.isDirectory() do return -Linux.ENOTDIR
        if (info.flags & 3) != Linux.O_RDONLY
        {
            let status = writable(owner, node)
            if status do return status
        }
        info.fh = node.id
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func opendir(path: const [*] u8, info: *Linux.fuse_file_info)->s32
        => callbackOpendir(current(), path, info)

    func callbackRead(owner: *MountedVolume, path: const [*] u8?, buffer: [*] u8, size: u64, offset: s64, info: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if offset < 0 or size > cast(u64, Swag.S32.Max) do return -Linux.EINVAL
        if node.isDirectory() do return -Linux.EISDIR
        let count = catch owner.volume.readNode(node.id, cast(u64, offset), Swag.makeSlice(buffer, size)) { return statusFromError(Swag.err) }
        return cast(s32, count)
    }

    #[Swag.CallingConvention(.C)]
    private func read(path: const [*] u8?, buffer: [*] u8, size: u64, offset: s64, info: *Linux.fuse_file_info)->s32
        => callbackRead(current(), path, buffer, size, offset, info)

    func callbackWrite(owner: *MountedVolume, path: const [*] u8?, buffer: const [*] u8, size: u64, offset: s64, info: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if offset < 0 or size > cast(u64, Swag.S32.Max) do return -Linux.EINVAL
        if node.isDirectory() do return -Linux.EISDIR
        let count = catch owner.volume.writeNode(node.id, cast(u64, offset), Swag.makeSlice(buffer, size), (info.flags & 0x400) != 0, false) { return statusFromError(Swag.err) }
        return cast(s32, count)
    }

    #[Swag.CallingConvention(.C)]
    private func write(path: const [*] u8?, buffer: const [*] u8, size: u64, offset: s64, info: *Linux.fuse_file_info)->s32
        => callbackWrite(current(), path, buffer, size, offset, info)

    func callbackTruncate(owner: *MountedVolume, path: const [*] u8?, size: s64, info: *Linux.fuse_file_info?)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if size < 0 do return -Linux.EINVAL
        if node.isDirectory() do return -Linux.EISDIR
        let status = writable(owner, node)
        if status do return status
        catch owner.volume.resizeNode(node.id, cast(u64, size)) { return statusFromError(Swag.err) }
        return commit(owner)
    }

    #[Swag.CallingConvention(.C)]
    private func truncate(path: const [*] u8?, size: s64, info: *Linux.fuse_file_info?)->s32
        => callbackTruncate(current(), path, size, info)

    func callbackUnlink(owner: *MountedVolume, path: const [*] u8)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, null) { return statusFromError(Swag.err) }
        if node.isDirectory() do return -Linux.EISDIR
        catch owner.volume.deleteNode(node.id) { return statusFromError(Swag.err) }
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func unlink(path: const [*] u8)->s32
        => callbackUnlink(current(), path)

    func callbackRmdir(owner: *MountedVolume, path: const [*] u8)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, null) { return statusFromError(Swag.err) }
        if not node.isDirectory() do return -Linux.ENOTDIR
        catch owner.volume.deleteNode(node.id) { return statusFromError(Swag.err) }
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func rmdir(path: const [*] u8)->s32
        => callbackRmdir(current(), path)

    func callbackRename(owner: *MountedVolume, path: const [*] u8, destination: const [*] u8, flags: u32)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        if flags & ~1'u32 do return -Linux.EINVAL
        let node = catch lookup(owner, path, null) { return statusFromError(Swag.err) }
        let value = catch pathString(destination) { return statusFromError(Swag.err) }
        catch owner.volume.renameNode(node.id, value, (flags & 1) == 0) { return statusFromError(Swag.err) }
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func rename(path: const [*] u8, destination: const [*] u8, flags: u32)->s32
        => callbackRename(current(), path, destination, flags)

    func callbackFlush(owner: *MountedVolume, _: const [*] u8?, _: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        return commit(owner)
    }

    #[Swag.CallingConvention(.C)]
    private func flush(path: const [*] u8?, info: *Linux.fuse_file_info)->s32
        => callbackFlush(current(), path, info)

    func callbackFsync(owner: *MountedVolume, _: const [*] u8?, _: s32, _: *Linux.fuse_file_info)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        return commit(owner)
    }

    #[Swag.CallingConvention(.C)]
    private func fsync(path: const [*] u8?, dataOnly: s32, info: *Linux.fuse_file_info)->s32
        => callbackFsync(current(), path, dataOnly, info)

    func callbackStatfs(owner: *MountedVolume, _: const [*] u8, output: *Linux.statvfs)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        output[] = {}
        output.f_bsize = BlockSize
        output.f_frsize = BlockSize
        output.f_blocks = owner.volume.totalBytes() / BlockSize
        output.f_bfree = owner.volume.freeBytes() / BlockSize
        output.f_bavail = output.f_bfree
        output.f_namemax = MaximumNameSize
        output.f_flag = owner.volume.readOnly ? 1 : 0
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func statfs(path: const [*] u8, output: *Linux.statvfs)->s32
        => callbackStatfs(current(), path, output)

    func callbackAccess(owner: *MountedVolume, path: const [*] u8, requested: s32)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        let node = catch lookup(owner, path, null) { return statusFromError(Swag.err) }
        if (requested & 2) != 0
        {
            let status = writable(owner, node)
            if status do return status
        }
        if (requested & 1) != 0 and not node.isDirectory() do return -Linux.EACCES
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func access(path: const [*] u8, requested: s32)->s32
        => callbackAccess(current(), path, requested)

    func callbackChmod(owner: *MountedVolume, path: const [*] u8?, permissions: u32, info: *Linux.fuse_file_info?)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if owner.volume.readOnly do return -Linux.EROFS
        // Only the persisted Windows read-only bit can change. Other POSIX bits are unsupported.
        if (permissions & 0xFFF & ~Linux.S_IWUSR) != (mode(node) & 0xFFF & ~Linux.S_IWUSR) do return -Linux.ENOTSUP
        if permissions & Linux.S_IWUSR do node.attributes &= ~FileAttributeReadOnly
        else do node.attributes |= FileAttributeReadOnly
        node.changeTime = volumeTimeNow()
        owner.volume.touchMetadata(node.id)
        return commit(owner)
    }

    #[Swag.CallingConvention(.C)]
    private func chmod(path: const [*] u8?, permissions: u32, info: *Linux.fuse_file_info?)->s32
        => callbackChmod(current(), path, permissions, info)

    func callbackChown(owner: *MountedVolume, path: const [*] u8?, uid: u32, gid: u32, info: *Linux.fuse_file_info?)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        discard catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if owner.volume.readOnly do return -Linux.EROFS
        if (uid != Swag.U32.Max and uid != owner.uid) or (gid != Swag.U32.Max and gid != owner.gid) do return -Linux.EPERM
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func chown(path: const [*] u8?, uid: u32, gid: u32, info: *Linux.fuse_file_info?)->s32
        => callbackChown(current(), path, uid, gid, info)

    func callbackUtimens(owner: *MountedVolume, path: const [*] u8?, times: const [*] Linux.timespec?, info: *Linux.fuse_file_info?)->s32
    {
        owner.volume.accessLock.lock()
        defer owner.volume.accessLock.unlock()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if owner.volume.readOnly do return -Linux.EROFS
        let now = volumeTimeNow()
        let accessTime = times ? catch volumeTime(times[0], node.lastAccessTime) { return statusFromError(Swag.err) } : now
        let writeTime = times ? catch volumeTime(times[1], node.lastWriteTime) { return statusFromError(Swag.err) } : now
        if times and times[0].tv_nsec == Linux.UTIME_OMIT and times[1].tv_nsec == Linux.UTIME_OMIT do return 0
        node.lastAccessTime = accessTime
        node.lastWriteTime = writeTime
        node.changeTime = now
        owner.volume.touchMetadata(node.id)
        return commit(owner)
    }

    #[Swag.CallingConvention(.C)]
    private func utimens(path: const [*] u8?, times: const [*] Linux.timespec?, info: *Linux.fuse_file_info?)->s32
        => callbackUtimens(current(), path, times, info)

    func callbackReaddir(owner: *MountedVolume, path: const [*] u8, buffer: *void, fill: Linux.fuse_fill_dir_fn, offset: s64, info: *Linux.fuse_file_info, _: s32)->s32
    {
        owner.volume.accessLock.lockShared()
        defer owner.volume.accessLock.unlockShared()
        let node = catch lookup(owner, path, info) { return statusFromError(Swag.err) }
        if not node.isDirectory() do return -Linux.ENOTDIR
        if offset < 0 do return -Linux.EINVAL
        var attributes: Linux.stat
        discard fillStat(owner, node, &attributes)
        if offset < 1 and fill(buffer, ".".buffer, &attributes, 1, 0) != 0 do return 0
        let parent = owner.volume.nodeById(node.parentId)
        if parent do discard fillStat(owner, parent, &attributes)
        if offset < 2 and fill(buffer, "..".buffer, &attributes, 2, 0) != 0 do return 0
        // Node ids are stable across sibling insertion/deletion; cookies are not array positions.
        var cookie = cast(u64, Math.max(offset, 2's64))
        for
        {
            var next: *Node?
            var child = owner.volume.firstChild(node.id)
            while child
            {
                if child.id + 2 > cookie and (not next or child.id < next.id) do next = child
                child = owner.volume.nextSibling(child.id)
            }
            if not next do break
            cookie = next.id + 2
            if cookie > cast(u64, Swag.S64.Max) do return -Linux.EOVERFLOW
            discard fillStat(owner, next, &attributes)
            if fill(buffer, unwrap next.name.buffer, &attributes, cast(s64, cookie), 0) != 0 do break
        }
        return 0
    }

    #[Swag.CallingConvention(.C)]
    private func readdir(path: const [*] u8, buffer: *void, fill: Linux.fuse_fill_dir_fn, offset: s64, info: *Linux.fuse_file_info, flags: s32)->s32
        => callbackReaddir(current(), path, buffer, fill, offset, info, flags)

    #[Swag.CallingConvention(.C)]
    private func initialize(_: *void, _: *void)->*void?
    {
        let context = (g_Runtime!.context)()
        if not context.private_data do return null
        let owner = cast(*MountedVolume, context.private_data)
        Atomic.exchange(&owner.ready, 1)
        return owner
    }

    func makeOperations()->Linux.fuse_operations
    {
        var result: #returntype
        result.getattr = &getattr
        result.mkdir = &mkdir
        result.create = &create
        result.open = &open
        result.opendir = &opendir
        result.read = &read
        result.write = &write
        result.truncate = &truncate
        result.unlink = &unlink
        result.rmdir = &rmdir
        result.rename = &rename
        result.flush = &flush
        result.fsync = &fsync
        result.statfs = &statfs
        result.access = &access
        result.chmod = &chmod
        result.chown = &chown
        result.utimens = &utimens
        result.readdir = &readdir
        result.fsyncdir = &fsync
        result.init = &initialize
        return result
    }
}

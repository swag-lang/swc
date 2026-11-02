#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global private
using Core

// Tests the adapter at the same typed callback boundary used by libfuse, without a mount.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-fuse-%.bin", Guid64.random()))
    defer discard catch File.delete(path)
    var owner: Fuse.MountedVolume
    owner.uid = Linux.geteuid()
    owner.gid = Linux.getegid()
    owner.volume = expect Volume.create(path, "fuse test password", MinimumSize)
    owner.volumeOpen = true
    var info: Linux.fuse_file_info
    Swag.assert(Fuse.callbackMkdir(&owner, "/dir".buffer, 0x1C0) == 0)
    Swag.assert(Fuse.callbackCreate(&owner, "/dir/data".buffer, 0x180, &info) == 0)
    Swag.assert(Fuse.callbackWrite(&owner, null, "hello".buffer, 5, 0, &info) == 5)
    Swag.assert(Fuse.callbackFsync(&owner, null, 0, &info) == 0)
    var bytes: [8] u8
    Swag.assert(Fuse.callbackRead(&owner, null, bytes.buffer, 8, 0, &info) == 5)
    Swag.assert(Slice.equals(bytes[until 5], cast(const [..] u8, "hello")))
    Swag.assert(Fuse.callbackRename(&owner, "/dir/data".buffer, "/renamed".buffer, 0) == 0)
    var attributes: Linux.stat
    Swag.assert(Fuse.callbackGetattr(&owner, "/renamed".buffer, &attributes, null) == 0)
    Swag.assert(attributes.st_size == 5 and attributes.st_uid == owner.uid and (attributes.st_mode & 0xFFF) == 0x180)
    Swag.assert(Fuse.callbackChmod(&owner, null, 0x1A4, &info) == -Linux.ENOTSUP)
    Swag.assert(Fuse.callbackChown(&owner, null, owner.uid + 1, owner.gid, &info) == -Linux.EPERM)
    Swag.assert(Fuse.callbackChmod(&owner, null, 0x100, &info) == 0)
    Swag.assert(Fuse.callbackWrite(&owner, null, "x".buffer, 1, 0, &info) == -Linux.EACCES)
    Swag.assert(Fuse.callbackChmod(&owner, null, 0x180, &info) == 0)
    Swag.assert(Fuse.callbackTruncate(&owner, null, 3, &info) == 0)
    var times: [2] Linux.timespec = [{tv_sec: 1_234_567_890, tv_nsec: 123_456_700}, {tv_sec: 1_234_567_891, tv_nsec: 987_654_300}]
    Swag.assert(Fuse.callbackUtimens(&owner, null, times.buffer, &info) == 0)
    Swag.assert(Fuse.callbackGetattr(&owner, "/renamed".buffer, &attributes, null) == 0)
    Swag.assert(attributes.st_mtim.tv_sec == times[1].tv_sec and attributes.st_mtim.tv_nsec == times[1].tv_nsec)
    Swag.assert(Fuse.callbackCreate(&owner, "/bad\\name".buffer, 0x180, &info) == -Linux.EINVAL)
    Swag.assert(Fuse.callbackRmdir(&owner, "/renamed".buffer) == -Linux.ENOTDIR)
    Swag.assert(Fuse.callbackUnlink(&owner, "/dir".buffer) == -Linux.EISDIR)
    expect owner.close()
    owner.volume = expect Volume.open(path, "fuse test password", true)
    owner.volumeOpen = true
    Swag.assert(Fuse.callbackGetattr(&owner, "/renamed".buffer, &attributes, null) == 0 and attributes.st_size == 3)
    Swag.assert(Fuse.callbackCreate(&owner, "/forbidden".buffer, 0x180, &info) == -Linux.EROFS)
    Swag.assert(Fuse.callbackOpen(&owner, "/renamed".buffer, &info) == 0)
    Swag.assert(Fuse.callbackRead(&owner, null, bytes.buffer, 8, 0, &info) == 3)
    Swag.assert(Slice.equals(bytes[until 3], cast(const [..] u8, "hel")))
    expect owner.close()
}

// The host inode lock protects actual concurrent Volume handles, independently of FUSE.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-fuse-lock-%.bin", Guid64.random()))
    defer discard catch File.delete(path)
    var first = expect Volume.create(path, "inode lock password", MinimumSize)
    var error: Swag.Error
    discard catch Volume.open(path, "inode lock password") as error
    Swag.assert(error.value() is Error)
    if error.value() is Error as typed do Swag.assert(typed.kind == .AccessDenied)
    discard catch Volume.open(path, "inode lock password", true) as error
    Swag.assert(error.value() is Error)
    first.close()
    var reader = expect Volume.open(path, "inode lock password", true)
    var secondReader = expect Volume.open(path, "inode lock password", true)
    discard catch Volume.open(path, "inode lock password") as error
    Swag.assert(error.value() is Error)
    reader.close()
    secondReader.close()
    first = expect Volume.open(path, "inode lock password")
    first.close()
}

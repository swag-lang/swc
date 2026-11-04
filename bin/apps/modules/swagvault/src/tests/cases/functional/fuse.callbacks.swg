#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global private

using Core

// Tests the adapter at the same typed callback boundary used by libfuse, without a mount.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-fuse-%.bin", Guid64.random()))
    defer discard catch File.delete(path)
    var owner: Fuse.MountedVolume
    owner.uid        = Linux.geteuid()
    owner.gid        = Linux.getegid()
    owner.volume     = expect Volume.create(path, "fuse test password", MinimumSize)
    owner.volumeOpen = true
    var info: Linux.fuse_file_info
    Swag.require(Fuse.callbackMkdir(&owner, "/dir".buffer, 0x1C0) == 0)
    Swag.require(Fuse.callbackCreate(&owner, "/dir/data".buffer, 0x180, &info) == 0)
    Swag.require(Fuse.callbackWrite(&owner, null, "hello".buffer, 5, 0, &info) == 5)
    Swag.require(Fuse.callbackFsync(&owner, null, 0, &info) == 0)
    var bytes: [8] u8
    Swag.require(Fuse.callbackRead(&owner, null, bytes.buffer, 8, 0, &info) == 5)
    Swag.require(Slice.equals(bytes[until 5], cast(const [..] u8, "hello")))
    Swag.require(Fuse.callbackRename(&owner, "/dir/data".buffer, "/renamed".buffer, 0) == 0)
    Swag.require(Fuse.callbackRename(&owner, "/renamed".buffer, "/renamed".buffer, 1) == -Linux.EEXIST)
    Swag.require(Fuse.callbackRename(&owner, "/renamed".buffer, "/dir".buffer, 0) == -Linux.EISDIR)
    var attributes: Linux.stat
    Swag.require(Fuse.callbackGetattr(&owner, "/renamed".buffer, &attributes, null) == 0)
    Swag.require(attributes.st_size == 5 and
                attributes.st_uid == owner.uid and
                (attributes.st_mode & 0xFFF) == 0x180)
    Swag.require(Fuse.callbackChmod(&owner, null, 0x1A4, &info) == -Linux.ENOTSUP)
    Swag.require(Fuse.callbackChown(&owner, null, owner.uid + 1, owner.gid, &info) == -Linux.EPERM)
    Swag.require(Fuse.callbackChmod(&owner, null, 0x100, &info) == 0)
    Swag.require(Fuse.callbackWrite(&owner, null, "x".buffer, 1, 0, &info) == -Linux.EACCES)
    Swag.require(Fuse.callbackChmod(&owner, null, 0x180, &info) == 0)
    Swag.require(Fuse.callbackTruncate(&owner, null, 3, &info) == 0)
    var times: [2] Linux.timespec = [{tv_sec: 1_234_567_890, tv_nsec: 123_456_700}, {tv_sec: 1_234_567_891, tv_nsec: 987_654_300}]
    Swag.require(Fuse.callbackUtimens(&owner, null, times.buffer, &info) == 0)
    Swag.require(Fuse.callbackGetattr(&owner, "/renamed".buffer, &attributes, null) == 0)
    Swag.require(attributes.st_mtim.tv_sec == times[1].tv_sec and attributes.st_mtim.tv_nsec == times[1].tv_nsec)
    Swag.require(Fuse.callbackCreate(&owner, "/bad\\name".buffer, 0x180, &info) == -Linux.EINVAL)
    Swag.require(Fuse.callbackRmdir(&owner, "/renamed".buffer) == -Linux.ENOTDIR)
    Swag.require(Fuse.callbackUnlink(&owner, "/dir".buffer) == -Linux.EISDIR)
    expect owner.close()
    owner.volume     = expect Volume.open(path, "fuse test password", true)
    owner.volumeOpen = true
    Swag.require(Fuse.callbackGetattr(&owner, "/renamed".buffer, &attributes, null) == 0 and attributes.st_size == 3)
    Swag.require(Fuse.callbackCreate(&owner, "/forbidden".buffer, 0x180, &info) == -Linux.EROFS)
    Swag.require(Fuse.callbackOpen(&owner, "/renamed".buffer, &info) == 0)
    Swag.require(Fuse.callbackRead(&owner, null, bytes.buffer, 8, 0, &info) == 3)
    Swag.require(Slice.equals(bytes[until 3], cast(const [..] u8, "hel")))
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
    Swag.require(error.value() is Error)
    if error.value() is Error as typed do
        Swag.require(typed.kind == .AccessDenied)
    discard catch Volume.open(path, "inode lock password", true) as error
    Swag.require(error.value() is Error)
    first.close()
    var reader       = expect Volume.open(path, "inode lock password", true)
    var secondReader = expect Volume.open(path, "inode lock password", true)
    discard catch Volume.open(path, "inode lock password") as error
    Swag.require(error.value() is Error)
    reader.close()
    secondReader.close()
    first = expect Volume.open(path, "inode lock password")
    first.close()
}

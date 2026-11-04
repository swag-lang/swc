#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("filesystem.mountinfo")]
#test
{
    let root = expect Directory.mountPointNative("36 25 0:32 / / rw,relatime shared:1 - overlay overlay rw")
    Swag.require(root == "/")
    let path = expect Directory.mountPointNative("37 25 8:1 / /media/a\\040b\\011c\\012d\\134e rw - ext4 /dev/sda1 rw")
    Swag.require(path == "/media/a b\tc\nd\\e")
    for line in ["", "37 25 8:1 / relative rw - ext4 /dev/sda1 rw", "37 25 8:1 / /bad\\04 rw - ext4 /dev/sda1 rw", "37 25 8:1 / /bad\\000 rw - ext4 /dev/sda1 rw"]
    {
        var error: Swag.Error
        discard catch Directory.mountPointNative(line) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let mounts    = expect Directory.drives()
    var foundRoot = false
    for &mount, index in mounts
    {
        Swag.require(mount.length > 0 and mount[0] == '/' and mount[mount.length - 1] == '/')
        Swag.require(Directory.exists(mount[]))
        if mount[] == "/" do
            foundRoot = true
        for previous in 0'u64 until index do
            Swag.require(mounts[previous] != mount[])
    }

    Swag.require(foundRoot)
}

// Mount identity, rather than a lexical path prefix, selects the visible filesystem.
#[Swag.TestTag("filesystem.mountinfo")]
#test
{
    const Mounts = "10 1 0:1 / / rw - ext4 /dev/root rw\n20 10 0:2 / /same rw shared:7 - nfs4 server:/share rw\n21 10 0:3 / /same rw - tmpfs tmpfs rw\n"
    Swag.require(not Directory.remoteMountNative(Mounts, 10))
    Swag.require(Directory.remoteMountNative(Mounts, 20))
    Swag.require(not Directory.remoteMountNative(Mounts, 21))
    Swag.require(not Directory.remoteMountNative(Mounts, 99))
    for kind in ["nfs", "nfs4", "cifs", "smb3", "afs", "ceph", "9p", "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.glusterfs"]
    {
        let record = Format.toString("90 1 0:1 / /remote rw - % source rw", kind)
        Swag.require(Directory.remoteMountNative(record, 90))
    }

    Swag.require(not Directory.remoteMountNative("90 1 0:1 / /local rw - fuse.swagvault vault rw", 90))
    Swag.require(not Directory.remoteMountNative("90 1 0:1 / /bad rw shared:2 master:3 -", 90))
}

// Requires a local temporary filesystem; exercises real fdinfo/mountinfo resolution and symlinks.
#[Swag.TestTag("integration.filesystem")]
#test
{
    let root = Env.getSpecialDirectory(.Temp)
    Swag.require(not Directory.isRemote(root))
    Swag.require(not Directory.isRemote(Path.combine(root, "not-created-yet/volume.svlt")))
    Swag.require(not Directory.isRemote(""))
    Swag.require(not Directory.isRemote("/tmp\0not-a-path"))
    let link   = Path.combine(root, Format.toString("remote-query-%", Guid64.random()))
    let linked = Linux.symlinkat(root.storage(), Linux.AT_FDCWD, link.storage())
    Swag.require(linked == 0)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, link.storage(), 0)
    Swag.require(not Directory.isRemote(link))
    Swag.require(not Directory.isRemote(Path.combine(link, "not-created-yet")))
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let root      = Env.getSpecialDirectory(.Temp)
    let available = expect Directory.freeSpace(root)
    Swag.require(available > 0, "filesystem integration requires free temporary storage")
    let procAvailable = expect Directory.freeSpace("/proc")
    Swag.require(procAvailable == 0)
    let file = Path.combine(root, Format.toString("space-query-%", Guid64.random()))
    expect File.writeAllText(file, "content")
    defer expect File.delete(file)
    let notDirectory = Path.combine(file, "not-a-directory")
    for path in ["", file.toString(), notDirectory.toString()]
    {
        var outcome: Swag.Error
        discard catch Directory.freeSpace(path) as outcome
        Swag.require(not outcome.isEmpty())
    }

    let missing = Path.combine(root, Format.toString("missing-space-query-%", Guid64.random()))
    var missingOutcome: Swag.Error
    discard catch Directory.freeSpace(missing) as missingOutcome
    Swag.require(not missingOutcome.isEmpty())
}

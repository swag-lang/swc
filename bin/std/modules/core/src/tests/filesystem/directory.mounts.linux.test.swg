#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("filesystem.mountinfo")]
#test
{
    let root = expect Directory.mountPointNative("36 25 0:32 / / rw,relatime shared:1 - overlay overlay rw")
    Swag.assert(root == "/")
    let path = expect Directory.mountPointNative("37 25 8:1 / /media/a\\040b\\011c\\012d\\134e rw - ext4 /dev/sda1 rw")
    Swag.assert(path == "/media/a b\tc\nd\\e")
    for line in ["", "37 25 8:1 / relative rw - ext4 /dev/sda1 rw", "37 25 8:1 / /bad\\04 rw - ext4 /dev/sda1 rw", "37 25 8:1 / /bad\\000 rw - ext4 /dev/sda1 rw"]
    {
        var error: Swag.Error
        discard catch Directory.mountPointNative(line) as error
        Swag.assert(error.value() is Errors.InvalidFormatError)
    }
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let mounts    = expect Directory.drives()
    var foundRoot = false
    for &mount, index in mounts
    {
        Swag.assert(mount.length > 0 and mount[0] == '/' and mount[mount.length - 1] == '/')
        Swag.assert(Directory.exists(mount[]))
        if mount[] == "/" do
            foundRoot = true
        for previous in 0'u64 until index do
            Swag.assert(mounts[previous] != mount[])
    }

    Swag.assert(foundRoot)
}

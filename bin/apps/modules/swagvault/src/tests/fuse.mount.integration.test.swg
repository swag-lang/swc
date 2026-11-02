#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global if #hastag("vault.fuse.integration")
#global private
using Core

// Requires libfuse3, fusermount3 and access to /dev/fuse. Owns only generated scratch paths.
#[Swag.TestTag("integration.filesystem.fuse")]
#test
{
    let base = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-fuse-mount-%", Guid64.random()))
    expect Directory.create(base)
    defer expect Directory.delete(base)
    let container = Path.combine(base, "container.bin")
    defer discard catch File.delete(container)
    let destination = Path.combine(base, "mounted")
    scope
    {
        var volume = expect Volume.create(container, "mounted fuse password", MinimumSize)
        volume.close()
    }
    var mount: MountedVault
    expect mount.open(container, "mounted fuse password", destination)
    let filePath = Path.combine(destination, "original")
    let renamed = Path.combine(destination, "renamed")
    discard expect File.writeAllText(filePath, "mounted data")
    Swag.assert(expect File.readAllText(filePath) == "mounted data")
    expect File.move(renamed, filePath)
    Swag.assert(not File.exists(filePath) and File.exists(renamed))
    let entries = expect Directory.enumerate(destination, {})
    Swag.assert(entries.count == 1)
    scope
    {
        var openFile = expect File.open(renamed, .Open, .ReadWrite, .ReadWrite)
        expect File.delete(renamed)
        Swag.assert(not File.exists(renamed))
        var buffer: [12] u8
        Swag.assert(expect openFile.readExact(buffer))
        Swag.assert(Slice.equals(buffer, cast(const [..] u8, "mounted data")))
        expect openFile.writeAllAt(0, "kept until close")
        expect openFile.flush()
    }
    let durable = Path.combine(destination, "durable")
    discard expect File.writeAllText(durable, "survives remount")
    let space = mount.space()
    Swag.assert(space.total > 0 and space.available <= space.total)
    expect mount.close()
    Swag.assert(not Directory.exists(destination))
    expect mount.open(container, "mounted fuse password", destination, true)
    Swag.assert(expect File.readAllText(durable) == "survives remount")
    var error: Swag.Error
    discard catch File.writeAllText(durable, "forbidden") as error
    Swag.assert(error.value() != null)
    expect mount.close()
    expect mount.close()
    Swag.assert(not Directory.exists(destination))
}

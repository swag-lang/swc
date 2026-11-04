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
    let renamed  = Path.combine(destination, "renamed")
    discard expect File.writeAllText(filePath, "mounted data")
    Swag.require(expect File.readAllText(filePath) == "mounted data")
    expect File.move(renamed, filePath)
    Swag.require(not File.exists(filePath) and File.exists(renamed))
    let entries = expect Directory.enumerate(destination, {})
    Swag.require(entries.count == 1)
    scope
    {
        var openFile = expect File.open(renamed, .Open, .ReadWrite, .ReadWrite)
        expect File.delete(renamed)
        Swag.require(not File.exists(renamed))
        var buffer: [12] u8
        Swag.require(expect openFile.readExact(buffer))
        Swag.require(Slice.equals(buffer, cast(const [..] u8, "mounted data")))
        expect openFile.writeAllAt(0, "kept until close")
        expect openFile.flush()
    }

    let durable = Path.combine(destination, "durable")
    discard expect File.writeAllText(durable, "survives remount")
    let space = mount.space()
    Swag.require(space.total > 0 and space.available <= space.total)
    expect mount.close()
    Swag.require(not Directory.exists(destination))
    expect mount.open(container, "mounted fuse password", destination, true)
    Swag.require(expect File.readAllText(durable) == "survives remount")
    var error: Swag.Error
    discard catch File.writeAllText(durable, "forbidden") as error
    Swag.require(error.value() != null)
    expect mount.close()
    expect mount.close()
    Swag.require(not Directory.exists(destination))
}

// Mounts share the loaded library but retain independent callback state and lifetime.
#[Swag.TestTag("integration.filesystem.fuse")]
#test
{
    let base = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-fuse-mount-%", Guid64.random()))
    expect Directory.create(base)
    defer expect Directory.delete(base)
    let firstPath = Path.combine(base, "first.bin")
    let secondPath = Path.combine(base, "second.bin")
    defer discard catch File.delete(firstPath)
    defer discard catch File.delete(secondPath)
    for path, index in [firstPath, secondPath]
    {
        var volume = expect Volume.create(path[], "shared runtime password", MinimumSize)
        let node = expect volume.createNode("/value", false, 0, "")
        let text = index == 0 ? "first" : "second"
        discard expect volume.writeNode(node, 0, cast(const [..]u8, text), false, false)
        expect volume.commit()
        volume.close()
    }
    let firstDestination = Path.combine(base, "first")
    let secondDestination = Path.combine(base, "second")
    var first, second: MountedVault
    var error: Swag.Error
    catch first.open(firstPath, "wrong password", firstDestination) as error
    Swag.require(error.value() != null and not Directory.exists(firstDestination))
    expect Directory.create(firstDestination)
    let sentinel = Path.combine(firstDestination, "keep")
    discard expect File.writeAllText(sentinel, "existing file")
    catch first.open(firstPath, "shared runtime password", firstDestination) as error
    Swag.require(error.value() != null and (expect File.readAllText(sentinel)) == "existing file")
    expect File.delete(sentinel)
    expect Directory.delete(firstDestination)
    expect first.open(firstPath, "shared runtime password", firstDestination, true)
    expect second.open(secondPath, "shared runtime password", secondDestination, true)
    Swag.require(expect File.readAllText(Path.combine(firstDestination, "value")) == "first")
    Swag.require(expect File.readAllText(Path.combine(secondDestination, "value")) == "second")
    expect first.close()
    Swag.require(expect File.readAllText(Path.combine(secondDestination, "value")) == "second")
    expect second.close()
    Swag.require(not Directory.exists(firstDestination) and not Directory.exists(secondDestination))
}

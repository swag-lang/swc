#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Swag

// Recursive deletion removes a directory symlink without walking into its target.
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("core-symlink-root-%", Guid64.random()))
    let target = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("core-symlink-target-%", Guid64.random()))
    let link   = Path.combine(root, "linked")
    let marker = Path.combine(target, "keep.txt")
    expect Directory.create(root)
    expect Directory.create(target)
    defer
    {
        discard catch Directory.delete(root, recurse: true)
        discard catch Directory.delete(target, recurse: true)
    }

    expect File.writeAllText(marker, "keep")
    for suffix in ["", "/", "/./"]
    {
        Swag.require(Linux.symlinkat(target.storage(), Linux.AT_FDCWD, link.storage()) == 0)
        var requested = String.from(link)
        requested.append(suffix)

        expect Directory.delete(requested, recurse: true)
        Swag.require(not Directory.exists(link))
        Swag.require(Directory.exists(target))
        Swag.require(File.exists(marker))
        Swag.require((expect File.readAllText(marker)) == "keep")
    }
}

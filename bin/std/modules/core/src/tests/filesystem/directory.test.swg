#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let dirName = CoreTests.makeFilesystemTestPath("core_invalid?dir")

    discard catch Directory.create(dirName) as err
    Swag.assert(err != null)
    Swag.assert(err is Errors.InvalidFileNameError)
    Swag.assert(not Directory.exists(dirName))
}

#test
{
    let root = CoreTests.makeFilesystemTestPath("core_recursive_dir")
    defer discard catch Directory.delete(root, recurse: true)

    // Every missing level is created, and asking again for a directory that exists succeeds.
    let leaf = Path.combine(root, "a", "b")
    expect Directory.create(leaf, recurse: true)
    Swag.assert(Directory.exists(leaf))
    expect Directory.create(leaf, recurse: true)

    discard catch Directory.create(leaf) as err
    Swag.assert(err != null)
}

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

// Selection does not prevent traversal, and special entries have their own option.
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_directory_selection")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)

    let child = Path.combine(root, "child")
    expect Directory.create(child)
    discard expect File.writeAllText(Path.combine(root, "first.txt"), "first")
    discard expect File.writeAllText(Path.combine(root, "second.bin"), "second")
    discard expect File.writeAllText(Path.combine(child, "nested.txt"), "nested")

    let files = expect Directory.enumerateFiles(root)
    Swag.assert(files.count == 2)
    for entry in files do
        Swag.assert(not entry.isDirectory())

    let directories = expect Directory.enumerateDirectories(root)
    Swag.assert(directories.count == 1 and directories[0].fullName == child)

    let nested = expect Directory.enumerateFiles(root, ".txt", recurse: true)
    Swag.assert(nested.count == 2)
    for entry in nested do
        Swag.assert(not entry.isDirectory() and Path.hasExtension(entry.fullName, ".txt"))

    let either = expect Directory.enumerate(root, {matchExtension: ".txt", matchFileName: "second.bin"})
    Swag.assert(either.count == 2)

    let special = expect Directory.enumerate(root, {wantFiles: false, wantDirectories: false, wantSpecialDirectories: true})
    Swag.assert(special.count == 2)
    for entry in special
    {
        let name = Path.fileName(entry.fullName)
        Swag.assert(name == "." or name == "..")
    }
}

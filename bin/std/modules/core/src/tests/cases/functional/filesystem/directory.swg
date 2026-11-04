#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

// Creates a directory junction when the host supports it.
func createDirectoryJunction(link, target: string)->bool
{
    let fontsDir   = Env.realSpecialDirectory(.Font)
    let windowsDir = Path.directoryName(fontsDir.toString())
    let shell      = Path.combine(windowsDir, "System32", "cmd.exe")
    let arguments  = Format.toString("/c mklink /J \"%\" \"%\"", link, target)
    let process    = catch Env.runProcess(Env.StartInfo{fileName: shell.toString(), nativeArguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe}) { return false }
    return process.exitCode() == 0
}

// The free space of a volume is read through any directory on it, and a missing one says so.
#test
{
    let temp = Env.getSpecialDirectory(.Temp)
    Swag.require(expect Directory.freeSpace(temp) > 0)

    let missing = CoreTests.makeFilesystemTestPath("core_free_space_missing")
    var errOutcome: Swag.Error
    discard catch Directory.freeSpace(missing) as errOutcome
    let err = errOutcome.value()
    Swag.require(err is Errors.FileNotFoundError)
}

#test
{
    let dirName = CoreTests.makeFilesystemTestPath("core_invalid?dir")

    var errOutcome: Swag.Error
    discard catch Directory.create(dirName) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)

    // Invalid names retain their filesystem error even when the sandbox rejects them first.
    Swag.require(err is Errors.InvalidFileNameError)
    Swag.require(not Directory.exists(dirName))
}

#test
{
    let root = CoreTests.makeFilesystemTestPath("core_recursive_dir")
    defer discard catch Directory.delete(root, recurse: true)

    // Every missing level is created, and asking again for a directory that exists succeeds.
    let leaf = Path.combine(root, "a", "b")
    expect Directory.create(leaf, recurse: true)
    Swag.require(Directory.exists(leaf))
    expect Directory.create(leaf, recurse: true)

    var errOutcome: Swag.Error
    discard catch Directory.create(leaf) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
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
    Swag.require(files.count == 2)
    for entry in files do
        Swag.require(not entry.isDirectory())

    let directories = expect Directory.enumerateDirectories(root)
    Swag.require(directories.count == 1 and directories[0].fullName == child)

    let nested = expect Directory.enumerateFiles(root, ".txt", recurse: true)
    Swag.require(nested.count == 2)
    for entry in nested do
        Swag.require(not entry.isDirectory() and Path.hasExtension(entry.fullName, ".txt"))

    let either = expect Directory.enumerate(root, {matchExtension: ".txt", matchFileName: "second.bin"})
    Swag.require(either.count == 2)

    let special = expect Directory.enumerate(root, {wantFiles: false, wantDirectories: false, wantSpecialDirectories: true})
    Swag.require(special.count == 2)
    for entry in special
    {
        let name = Path.fileName(entry.fullName)
        Swag.require(name == "." or name == "..")
    }
}

// A directory that cannot be opened reports an error instead of looking empty.
#test
{
    let dirName = Path.combine(CoreTests.makeFilesystemTestPath("core_directory_missing"), Guid64.random().toString())
    Swag.require(not Directory.exists(dirName))

    var errOutcome: Swag.Error
    discard catch Directory.enumerate(dirName, {}) as errOutcome
    Swag.require(errOutcome.value() != null)
}

// A drive letter without a mounted root is rejected before its path is queried.
#test
{
    let drives = expect Directory.drives()
    var missingRoot: String
    for letter in 'A'u8 until 'Z'u8 + 1
    {
        var candidate = String.from("A:\\")
        candidate[0] = cast(u8, letter)
        var mounted = false
        for &drive in drives where Utf8.compare(drive.toSlice(), candidate.toSlice(), .Latin1NoCase) == 0 do
            mounted = true
        if not mounted
        {
            missingRoot = #move candidate
            break
        }
    }

    if not missingRoot.isEmpty() do
        Swag.require(not Directory.exists(missingRoot.toString()))
}

// Empty paths are rejected before they can act like the current directory.
#test
{
    var createError: Swag.Error
    discard catch Directory.create("", recurse: true) as createError
    Swag.require(createError.value() is Errors.BadParameterError)

    var deleteError: Swag.Error
    discard catch Directory.delete("", recurse: true) as deleteError
    Swag.require(deleteError.value() is Errors.BadParameterError)

    var enumerateError: Swag.Error
    discard catch Directory.enumerate("", {}) as enumerateError
    Swag.require(enumerateError.value() is Errors.BadParameterError)
}

// Recursive deletion removes a directory link without walking into its target.
#test
{
    let root       = CoreTests.makeFilesystemTestPath("core_directory_link_root")
    let target     = CoreTests.makeFilesystemTestPath("core_directory_link_target")
    let link       = Path.combine(root, "linked")
    let targetFile = Path.combine(target, "keep.txt")
    expect Directory.create(root)
    expect Directory.create(target)
    defer
    {
        discard catch Directory.delete(root, recurse: true)
        discard catch Directory.delete(target, recurse: true)
    }

    discard expect File.writeAllText(targetFile.toString(), "keep")

    Swag.require(createDirectoryJunction(link.toString(), target.toString()))
    expect Directory.delete(root, recurse: true)
    Swag.require(File.exists(targetFile.toString()))
}

// A UNC path names a share; a local temporary folder and a relative path do not.
#test
{
    Swag.require(Directory.isRemote("\\\\server\\share\\films"))
    Swag.require(Directory.isRemote("//server/share"))
    Swag.require(Directory.isRemote(#raw "\\?\UNC\server\share\films"))
    Swag.require(not Directory.isRemote(#raw "\\?\C:\films"))
    Swag.require(not Directory.isRemote(#raw "\\.\C:\films"))
    Swag.require(not Directory.isRemote(Env.getSpecialDirectory(.Temp)))
    Swag.require(not Directory.isRemote("films"))
}

// Removing a junction supplied as the root must not delete anything inside its target.
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_root_junction")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let target = Path.combine(root, "target")
    expect Directory.create(target)
    let marker = Path.combine(target, "keep.txt")
    discard expect File.writeAllText(marker, "keep")
    let link = Path.combine(root, "link")
    for suffix in ["", "/", "/./"]
    {
        Swag.require(createDirectoryJunction(link, target))
        var requested = String.from(link)
        requested.append(suffix)
        expect Directory.delete(requested, recurse: true)
        Swag.require(not Directory.exists(link))
        Swag.require(Directory.exists(target) and File.exists(marker))
        Swag.require((expect File.readAllText(marker)) == "keep")
    }
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.filesystem")]
#test
{
    const Template = "/tmp/swag-core-directory-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = Linux.mkdtemp(temporary.buffer)
    Swag.assert(created == temporary.buffer)
    let root = cast(string, cast(cstring, temporary.buffer))
    defer expect Directory.deleteEmptyNative(root)

    let child = Path.combine(root, "child?\\name")
    expect Directory.createNative(child)
    defer expect Directory.deleteEmptyNative(child)
    Swag.assert(Directory.exists(child))
    Swag.assert(not File.exists(child))
    Swag.assert(not Directory.exists(""))
    Swag.assert(not File.exists(""))

    // Reject an embedded zero rather than accidentally querying the valid prefix.
    var truncated = String.from(child)
    truncated += "\0ignored"
    Swag.assert(not Directory.exists(truncated))
    var invalidName: Swag.Error
    discard catch Directory.createNative(truncated) as invalidName
    Swag.assert((invalidName.value() is Errors.InvalidFileNameError))

    let link   = Path.combine(root, "link")
    let linked = Linux.symlinkat(child.storage(), Linux.AT_FDCWD, link.storage())
    Swag.assert(linked == 0)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, link.storage(), 0)
    Swag.assert(Directory.exists(link))
    let linkInfo = expect File.nativePathInfo(link, Linux.AT_SYMLINK_NOFOLLOW)
    Swag.assert((linkInfo.st_mode & Linux.S_IFMT) == Linux.S_IFLNK)

    let source     = Path.combine(root, "source")
    let target     = Path.combine(root, "target")
    let descriptor = Linux.openat(Linux.AT_FDCWD, source.storage(), Linux.O_RDWR | Linux.O_CREAT | Linux.O_EXCL | Linux.O_CLOEXEC, 0x180'u32)
    Swag.assert(descriptor >= 0)
    defer discard Linux.close(descriptor)
    defer if File.exists(source) do
        expect File.deleteNative(source)
    defer if File.exists(target) do
        expect File.deleteNative(target)
    Swag.assert(File.exists(source) and not Directory.exists(source))
    let written = Linux.write(descriptor, "abc".buffer, 3)
    Swag.assert(written == 3)
    let before = expect File.nativePathInfo(source)
    expect File.moveNative(target, source)
    Swag.assert(not File.exists(source) and File.exists(target))
    let moved = expect File.nativePathInfo(target)
    Swag.assert(moved.st_ino == before.st_ino and moved.st_size == 3)
    expect File.touchNative(target)
    let touched = expect File.nativePathInfo(target)
    Swag.assert(touched.st_atim.tv_sec == moved.st_atim.tv_sec and touched.st_atim.tv_nsec == moved.st_atim.tv_nsec)
    expect File.deleteNative(target)
    Swag.assert(not File.exists(target))

    let current  = expect Directory.currentPath()
    let relative = expect Path.absolute("missing/../entry")
    Swag.assert(relative == Path.combine(current, "missing/../entry"))
    let absolute = expect Path.absolute(child)
    Swag.assert(absolute == child)
}

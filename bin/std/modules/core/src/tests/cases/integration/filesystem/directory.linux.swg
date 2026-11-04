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
    Swag.require(created == temporary.buffer)
    let root = cast(string, cast(cstring, temporary.buffer))
    defer expect Directory.deleteEmptyNative(root)

    let child = Path.combine(root, "child?\\name")
    expect Directory.createNative(child)
    defer expect Directory.deleteEmptyNative(child)
    Swag.require(Directory.exists(child))
    Swag.require(not File.exists(child))
    Swag.require(not Directory.exists(""))
    Swag.require(not File.exists(""))

    // Reject an embedded zero rather than accidentally querying the valid prefix.
    var truncated = String.from(child)
    truncated += "\0ignored"
    Swag.require(not Directory.exists(truncated))
    var invalidName: Swag.Error
    discard catch Directory.createNative(truncated) as invalidName
    Swag.require((invalidName.value() is Errors.InvalidFileNameError))

    let link   = Path.combine(root, "link")
    let linked = Linux.symlinkat(child.storage(), Linux.AT_FDCWD, link.storage())
    Swag.require(linked == 0)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, link.storage(), 0)
    Swag.require(Directory.exists(link))
    let linkInfo = expect File.nativePathInfo(link, Linux.AT_SYMLINK_NOFOLLOW)
    Swag.require((linkInfo.st_mode & Linux.S_IFMT) == Linux.S_IFLNK)

    let linkMetadata = expect File.info(link)
    Swag.require(linkMetadata.isDirectory() and linkMetadata.attributes.has(.ReparsePoint))
    Swag.require(linkMetadata.size == 0)
    Swag.require(linkMetadata.lastAccessTime.isValid() and linkMetadata.lastWriteTime.isValid())
    Swag.require(Time.dateTimeFromUnix(-1, 123_456_789) == Time.DateTime{1969, 12, 31, 23, 59, 59, 123})
    Swag.require(Time.dateTimeFromUnix(Swag.S64.Max, 0) == Time.DateTime{})
    let entries = expect Directory.enumerate(root, {})
    Swag.require(entries.count == 2)
    var sawLink = false
    for entry in entries where entry.attributes.has(.ReparsePoint)
    {
        sawLink = true
        Swag.require(entry.fullName == link and entry.isDirectory())
    }

    Swag.require(sawLink)

    let source     = Path.combine(root, "source")
    let target     = Path.combine(root, "target")
    let descriptor = Linux.openat(Linux.AT_FDCWD, source.storage(), Linux.O_RDWR | Linux.O_CREAT | Linux.O_EXCL | Linux.O_CLOEXEC, 0x180'u32)
    Swag.require(descriptor >= 0)
    defer discard Linux.close(descriptor)
    defer if File.exists(source) do
        expect File.deleteNative(source)
    defer if File.exists(target) do
        expect File.deleteNative(target)
    Swag.require(File.exists(source) and not Directory.exists(source))
    let written = Linux.write(descriptor, "abc".buffer, 3)
    Swag.require(written == 3)
    let before = expect File.nativePathInfo(source)
    expect File.moveNative(target, source)
    Swag.require(not File.exists(source) and File.exists(target))
    let moved = expect File.nativePathInfo(target)
    Swag.require(moved.st_ino == before.st_ino and moved.st_size == 3)
    expect File.touchNative(target)
    let touched = expect File.nativePathInfo(target)
    Swag.require(touched.st_atim.tv_sec == moved.st_atim.tv_sec and touched.st_atim.tv_nsec == moved.st_atim.tv_nsec)
    expect File.deleteNative(target)
    Swag.require(not File.exists(target))

    let current  = expect Directory.currentPath()
    let relative = expect Path.absolute("missing/../entry")
    Swag.require(relative == Path.combine(current, "missing/../entry"))
    let absolute = expect Path.absolute(child)
    Swag.require(absolute == child)
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let root = CoreTests.makeFilesystemTestPath("linux_root_symlink")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let target = Path.combine(root, "target")
    expect Directory.create(target)
    let marker = Path.combine(target, "keep.txt")
    discard expect File.writeAllText(marker, "keep")
    let link = Path.combine(root, "link")
    for suffix in ["", "/", "/./"]
    {
        let linked = Linux.symlinkat(target.storage(), Linux.AT_FDCWD, link.storage())
        Swag.require(linked == 0)
        var requested = String.from(link)
        requested.append(suffix)
        expect Directory.delete(requested, recurse: true)
        Swag.require(not Directory.exists(link))
        Swag.require(Directory.exists(target) and File.exists(marker))
        Swag.require((expect File.readAllText(marker)) == "keep")
    }
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.sandbox")]
#test
{
    if not Env.isSandboxed() do
        return
    let root = CoreTests.makeFilesystemTestPath("linux-sandbox-links")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    Swag.require(Env.isInsideDirectory("/", root))
    Swag.require(Env.isInsideDirectory(root, Path.combine(root, "missing/../child")))
    Swag.require(not Env.isInsideDirectory(root, Path.combine(root, "../other")))

    // A task-owned native fixture outside the sandbox lets the test detect an escaped write
    // without risking unrelated files. Only the public operations below exercise the guard.
    const Template = "/tmp/swag-sandbox-outside-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = Linux.mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, temporary.buffer, Linux.AT_REMOVEDIR)
    let outside    = cast(string, cast(cstring, temporary.buffer))
    let marker     = Path.combine(outside, "marker")
    let descriptor = Linux.openat(Linux.AT_FDCWD, marker.storage(), Linux.O_RDWR | Linux.O_CREAT | Linux.O_EXCL | Linux.O_CLOEXEC, 0x180'u32)
    Swag.require(descriptor >= 0)
    defer discard Linux.close(descriptor)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, marker.storage(), 0)
    let written = Linux.write(descriptor, "keep".buffer, 4)
    Swag.require(written == 4)

    let directoryLink   = Path.combine(root, "directory-link")
    let fileLink        = Path.combine(root, "file-link")
    let linkedDirectory = Linux.symlinkat(temporary.buffer, Linux.AT_FDCWD, directoryLink.storage())
    let linkedFile      = Linux.symlinkat(marker.storage(), Linux.AT_FDCWD, fileLink.storage())
    Swag.require(linkedDirectory == 0 and linkedFile == 0)
    Swag.require(not Env.isInsideDirectory(root, Path.combine(directoryLink, "marker")))
    Swag.require(Env.absolutePath(Path.combine(directoryLink, "..")) == Env.absolutePath("/tmp"))
    var denied: Swag.Error
    discard catch File.writeAllText(Path.combine(directoryLink, "marker"), "escaped") as denied
    Swag.require(denied.value() is Errors.SandboxError)
    discard catch File.delete(Path.combine(directoryLink, "marker")) as denied
    Swag.require(denied.value() is Errors.SandboxError)
    expect File.delete(fileLink)
    expect Directory.delete(directoryLink, recurse: true)
    let retained = expect File.readAllText(marker)
    Swag.require(retained == "keep" and Directory.exists(outside))
}

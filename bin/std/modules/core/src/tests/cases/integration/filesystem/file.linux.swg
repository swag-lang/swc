#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.filesystem")]
#test
{
    let path = CoreTests.makeFilesystemTestPath("linux-open-modes")
    defer if File.exists(path) do
        expect File.delete(path)
    scope
    {
        var stream = expect File.open(path, .CreateNew, .ReadWrite, .Zero)
        expect stream.writeAll([11'u8, 22, 33])
        let flags = Linux.fcntl(File.nativeFileDescriptor(stream.handle), Linux.F_GETFD)
        Swag.require(flags >= 0 and (flags & Linux.FD_CLOEXEC) != 0)
        var collision: Swag.Error
        discard catch File.open(path, .CreateNew, .Write, .Zero) as collision
        let collisionError = assume cast(const *Swag.SystemError, collision.value())
        Swag.require(collisionError.errorID == cast(u64, Linux.EEXIST))
        let size = expect stream.size()
        Swag.require(size == 3)
    }

    scope
    {
        var stream   = expect File.open(path, .Append, .ReadWrite, .Zero)
        let position = expect stream.position()
        Swag.require(position == 3)
        expect stream.seek(.Begin, 1)
        expect stream.writeAll([44'u8])
    }

    let bytes = expect File.readAllBytes(path)
    Swag.require(bytes.count == 3 and bytes[0] == 11 and bytes[1] == 44 and bytes[2] == 33)
    for mode in [File.FileMode.Create, .Truncate]
    {
        var invalid: Swag.Error
        discard catch File.open(path, mode, .Read, .Read) as invalid
        Swag.require(invalid.value() is Errors.BadParameterError)
    }

    let preserved = expect File.readAllBytes(path)
    Swag.require(Slice.equals(bytes.toSlice(), preserved.toSlice()))
    scope
    {
        var stream = expect File.open(path, .Truncate, .Write, .Inheritable)
        let flags  = Linux.fcntl(File.nativeFileDescriptor(stream.handle), Linux.F_GETFD)
        Swag.require(flags >= 0 and (flags & Linux.FD_CLOEXEC) == 0)
        let size = expect stream.size()
        Swag.require(size == 0)
    }
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let path  = CoreTests.makeFilesystemTestPath("linux-posix-sharing")
    var first = expect File.open(path, .CreateNew, .ReadWrite, .Zero)
    defer if File.exists(path) do
        expect File.delete(path)
    var second = expect File.open(path, .Open, .ReadWrite, .Zero)
    expect first.writeAll([71'u8, 73])
    expect File.delete(path)
    Swag.require(not File.exists(path))
    var bytes: [2] u8
    let read = expect second.readExact(bytes)
    Swag.require(read and bytes[0] == 71 and bytes[1] == 73)
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let path = CoreTests.makeFilesystemTestPath("linux-open-directory")
    expect Directory.create(path)
    defer expect Directory.delete(path)
    var failure: Swag.Error
    discard catch File.openRead(path) as failure
    let nativeError = assume cast(const *Swag.SystemError, failure.value())
    Swag.require(nativeError.errorID == cast(u64, Linux.EISDIR))
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    let path = CoreTests.makeFilesystemTestPath("linux-create-modes")
    defer if File.exists(path) do
        expect File.delete(path)
    for mode in [File.FileMode.Open, .Truncate]
    {
        var missing: Swag.Error
        discard catch File.open(path, mode, .ReadWrite, .Zero) as missing
        Swag.require(missing.value() is Errors.FileNotFoundError)
        Swag.require(not File.exists(path))
    }

    for mode in [File.FileMode.Append, .Create, .CreateNew, .OpenOrCreate]
    {
        var stream   = expect File.open(path, mode, .ReadWrite, .Zero)
        let position = expect stream.position()
        Swag.require(position == 0)
        expect stream.writeAll([19'u8, 23])
        stream.close()
        var replacement = expect File.open(path, .Create, .ReadWrite, .Zero)
        let size        = expect replacement.size()
        Swag.require(size == 0)
        replacement.close()
        expect File.delete(path)
    }
}

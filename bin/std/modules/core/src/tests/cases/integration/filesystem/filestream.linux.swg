#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.filesystem")]
#test
{
    let descriptor = Linux.memfd_create("swag-core-stream".buffer, Linux.MFD_CLOEXEC)
    Swag.require(descriptor >= 0)
    var stream: File.FileStream
    stream.open("swag-core-stream", File.nativeFileHandle(descriptor), true, true, true)
    Swag.require(stream.isOpen())
    Swag.require(File.nativeFileHandle(0) != null)
    Swag.require(File.nativeFileDescriptor(File.nativeFileHandle(0)) == 0)

    const LargeOffset = 4_294_967_297'u64
    expect stream.resize(LargeOffset)
    let initialSize     = expect stream.size()
    let initialPosition = expect stream.position()
    Swag.require(initialSize == LargeOffset and initialPosition == 0)
    expect stream.seek(.End, 0)
    let payload: [3] u8 = [11, 22, 33]
    expect stream.writeAll(payload)
    expect stream.flush()
    let size = expect stream.size()
    Swag.require(size == LargeOffset + payload.count)
    expect stream.seek(.Current, cast #bit (u64, -3's64))
    var recovered: [4] u8
    recovered[3] = 47
    let count = expect stream.read(recovered)
    Swag.require(count == 3 and
                recovered[0] == 11 and
                recovered[1] == 22 and
                recovered[2] == 33 and
                recovered[3] == 47)
    expect stream.resize(2)
    let truncatedSize     = expect stream.size()
    let truncatedPosition = expect stream.position()
    Swag.require(truncatedSize == 2 and truncatedPosition == 2)

    stream.close()
    Swag.require(not stream.isOpen())
    var info: Linux.stat
    let closed     = Linux.fstat(descriptor, &info)
    let closeError = Linux.errno()
    Swag.require(closed == -1 and closeError == Linux.EBADF)
    stream.close()
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    var failure: Swag.Error
    discard catch Errors.failLinuxError(Linux.ENOENT, "missing") as failure
    Swag.require((failure.value() is Errors.FileNotFoundError))
    discard catch Errors.failLinuxError(Linux.EBADF) as failure
    let nativeError = assume cast(const *Swag.SystemError, failure.value())
    Swag.require(nativeError.errorID == cast(u64, Linux.EBADF))
    Swag.require(Errors.message(failure.value()).count > 0)
}

// A descriptor is borrowed from the stream; closing the owner invalidates it.
#[Swag.TestTag("integration.filesystem")]
#test
{
    var closed: File.FileStream
    var error:  Swag.Error
    discard catch closed.nativeFileDescriptor() as error
    Swag.require(error.value() is Errors.BadParameterError)
    let path = CoreTests.makeFilesystemTestPath("linux-borrowed-descriptor")
    defer discard catch File.delete(path)
    var stream     = expect File.open(path, .CreateNew, .ReadWrite, .Read)
    let descriptor = expect stream.nativeFileDescriptor()
    var info: Linux.stat
    Swag.require(Linux.fstat(descriptor, &info) == 0)
    expect stream.writeAll("owned by stream")
    stream.close()
    Swag.require(Linux.fstat(descriptor, &info) == -1 and Linux.errno() == Linux.EBADF)
    var live = expect File.openReadLive(path)
    discard catch live.nativeFileDescriptor() as error
    Swag.require(error.value() is Errors.BadParameterError)
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.filesystem")]
#test
{
    let descriptor = Linux.memfd_create("swag-core-stream".buffer, Linux.MFD_CLOEXEC)
    Swag.assert(descriptor >= 0)
    var stream: File.FileStream
    stream.open("swag-core-stream", File.nativeFileHandle(descriptor), true, true, true)
    Swag.assert(stream.isOpen())
    Swag.assert(File.nativeFileHandle(0) != null)
    Swag.assert(File.nativeFileDescriptor(File.nativeFileHandle(0)) == 0)

    const LargeOffset = 4_294_967_297'u64
    expect stream.resize(LargeOffset)
    let initialSize     = expect stream.size()
    let initialPosition = expect stream.position()
    Swag.assert(initialSize == LargeOffset and initialPosition == 0)
    expect stream.seek(.End, 0)
    let payload: [3] u8 = [11, 22, 33]
    expect stream.writeAll(payload)
    expect stream.flush()
    let size = expect stream.size()
    Swag.assert(size == LargeOffset + payload.count)
    expect stream.seek(.Current, cast #bit (u64, -3's64))
    var recovered: [4] u8
    recovered[3] = 47
    let count = expect stream.read(recovered)
    Swag.assert(count == 3 and
                recovered[0] == 11 and
                recovered[1] == 22 and
                recovered[2] == 33 and
                recovered[3] == 47)
    expect stream.resize(2)
    let truncatedSize     = expect stream.size()
    let truncatedPosition = expect stream.position()
    Swag.assert(truncatedSize == 2 and truncatedPosition == 2)

    stream.close()
    Swag.assert(not stream.isOpen())
    var info: Linux.stat
    let closed     = Linux.fstat(descriptor, &info)
    let closeError = Linux.errno()
    Swag.assert(closed == -1 and closeError == Linux.EBADF)
    stream.close()
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    var failure: Swag.Error
    discard catch Errors.failLinuxError(Linux.ENOENT, "missing") as failure
    Swag.assert((failure.value() is Errors.FileNotFoundError))
    discard catch Errors.failLinuxError(Linux.EBADF) as failure
    let nativeError = assume cast(const *Swag.SystemError, failure.value())
    Swag.assert(nativeError.errorID == cast(u64, Linux.EBADF))
    Swag.assert(Errors.message(failure.value()).count > 0)
}

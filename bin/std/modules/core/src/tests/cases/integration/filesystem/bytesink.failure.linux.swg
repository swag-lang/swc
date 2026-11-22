#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Swag, Core.Errors

func openFullByteSink()->ByteSink
{
    let descriptor = Linux.openat(Linux.AT_FDCWD, "/dev/full".buffer, Linux.O_RDWR | Linux.O_CLOEXEC)
    Swag.require(descriptor >= 0)
    var stream: File.FileStream
    stream.open("/dev/full", File.nativeFileHandle(descriptor), true, true, true)
    with var result: #returntype
    {
        .stream   = #move stream
        .fileName = "/dev/full"
        .isFile   = true
    }

    return result
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    // Linux provides /dev/full, whose writes fail with ENOSPC without changing the filesystem.
    var sink = openFullByteSink()
    expect sink.writeByte(0x5A)
    var originalFailure: Swag.Error
    discard catch sink.flush() as originalFailure
    Swag.require(originalFailure.value() is Swag.SystemError)
    let systemError = assume cast(const *Swag.SystemError, originalFailure.value())
    Swag.require(systemError.errorID == cast(u64, Linux.ENOSPC))
    Swag.require(sink.position() == 1 and not sink.stream.isOpen())

    var rejected: Swag.Error
    discard catch sink.writeByte(0x33) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch sink.patch(0, cast(const [..] u8, "x")) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch sink.flush() as rejected
    Swag.require(rejected.value() is BadParameterError)
    expect sink.close()
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    // A direct write failure must not advance the logical position or allow reuse.
    var sink = openFullByteSink()
    var bytes: [ByteSink.WindowSize] u8
    var originalFailure: Swag.Error
    discard catch sink.write(bytes) as originalFailure
    Swag.require(originalFailure.value() is Swag.SystemError)
    let systemError = assume cast(const *Swag.SystemError, originalFailure.value())
    Swag.require(systemError.errorID == cast(u64, Linux.ENOSPC))
    Swag.require(sink.position() == 0 and not sink.stream.isOpen())
    expect sink.close()
}

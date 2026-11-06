#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

struct PartialPipeWriter
{
    readDescriptor:  s32
    writeDescriptor: s32
    sentSecond:      bool
}

func writeAfterShortRead(thread: const *Threading.Thread)
{
    let state = cast(*PartialPipeWriter, unwrap thread.userParam)
    var clock: Time.Stopwatch
    clock.start()
    while clock.elapsedMilliseconds() < 2000
    {
        var pending: s32
        if Linux.ioctl(state.readDescriptor, Linux.FIONREAD, &pending) != 0 do
            break
        if pending == 0
        {
            state.sentSecond = Linux.write(state.writeDescriptor, "cd".buffer, 2) == 2
            break
        }
        Threading.Thread.sleep(1'ms)
    }
    discard Linux.close(state.writeDescriptor)
}

#[Swag.TestTag("integration.filesystem")]
#test
{
    var descriptors: [2] s32
    Swag.require(Linux.pipe2(descriptors.buffer, Linux.O_CLOEXEC) == 0)
    Swag.require(Linux.write(descriptors[1], "ab".buffer, 2) == 2)

    var reader: File.FileStream
    reader.open("chunked pipe", File.nativeFileHandle(descriptors[0]), true, false, true)
    var writerState = PartialPipeWriter{readDescriptor: descriptors[0], writeDescriptor: descriptors[1]}
    var writer: Threading.Thread
    expect writer.init(&writeAfterShortRead, &writerState)
    expect writer.start()
    var bytes: [4] u8
    let complete = expect reader.readExact(bytes)
    writer.wait()
    reader.close()
    Swag.require(writerState.sentSecond and complete and cast(string, bytes) == "abcd")
}

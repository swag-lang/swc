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

struct InterruptedPipeWrite
{
    stream: File.FileStream
    total:  u64
}

var g_pipeWriteSignals: Swag.AtomicValue'u32

#[Swag.CallingConvention(.C)]
func interruptPipeWrite(_: s32)
{
    // Atomic bookkeeping only: the handler must not allocate or enter the runtime.
    g_pipeWriteSignals.add(1)
}

func writeLargePipe(thread: const *Threading.Thread)
{
    let state = cast(*InterruptedPipeWrite, unwrap thread.userParam)
    var bytes: [131072]u8
    for i in bytes.count do
        bytes[i] = 0x5A
    state.total = expect state.stream.write(bytes)
    state.stream.close()
}

// An interrupted blocking write can return a positive short count. The public stream must
// continue from that offset and deliver every byte exactly once.
#[Swag.TestTag("integration.filesystem")]
#test
{
    var descriptors: [2]s32
    Swag.require(Linux.pipe2(descriptors.buffer, Linux.O_CLOEXEC) == 0)
    var state: InterruptedPipeWrite
    state.stream.open("interrupted pipe", File.nativeFileHandle(descriptors[1]), false, true, false)
    defer state.stream.close()
    defer discard Linux.close(descriptors[0])

    var previous, action: Linux.sigaction_t
    action.handler = cast(*void, &interruptPipeWrite)
    Swag.require(Linux.sigemptyset(&action.mask) == 0)
    Swag.require(Linux.sigaction(Linux.SIGUSR1, &action, &previous) == 0)
    defer Swag.require(Linux.sigaction(Linux.SIGUSR1, &previous, null) == 0)
    g_pipeWriteSignals.store(0)

    var writer: Threading.Thread
    expect writer.init(&writeLargePipe, &state)
    expect writer.start()
    let deadline = Time.monotonicMilliseconds() + 3000
    var pending: s32
    while pending == 0 and Time.monotonicMilliseconds() < deadline
    {
        Swag.require(Linux.ioctl(descriptors[0], Linux.FIONREAD, &pending) == 0)
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(pending > 0 and pending < 131072)
    Threading.Thread.sleep(5'ms)
    Swag.require(Linux.tgkill(Linux.getpid(), cast(s32, writer.id), Linux.SIGUSR1) == 0)
    var received = 0'u64
    var chunk: [4096]u8
    for
    {
        let count = Linux.read(descriptors[0], &chunk[0], chunk.count)
        Swag.require(count >= 0)
        if count == 0 do
            break
        for i in cast(u64, count) do
            Swag.require(chunk[i] == 0x5A)
        received += cast(u64, count)
    }

    writer.wait()
    Swag.require(g_pipeWriteSignals.load() == 1 and state.total == 131072 and received == 131072)
}

#global if #os == Swag.TargetOs.Linux

using Swag, Core

private const MaxParallelFontReads = 4'u32
private const MinParallelFontBytes = 8'u64 * 1024 * 1024

func fontReadWorkers(length: u64)->u32 =>
    length >= MinParallelFontBytes ? Math.min(Swag.workerCount(), MaxParallelFontReads) : 0

private struct FontReadPart
{
    count: u64
    ok:    bool
}

private func readPositionalPart(fd: s32, offset: u64, destination: [*] u8, length: u64)->FontReadPart
{
    var position = 0'u64
    while position < length
    {
        let read = Linux.pread(fd, destination + position, length - position, cast(s64, offset + position))
        if read > 0
        {
            position += cast(u64, read)
            continue
        }

        if not read do
            break
        if Linux.errno() != Linux.EINTR do
            return {}
    }

    return {count: position, ok: true}
}

// Positional reads share the descriptor and write disjoint ranges of an owned buffer.
// A read error requests the ordinary stream path and its platform diagnostics.
func readParallelFontRange(stream: *File.FileStream, offset: u64, buffer: [..] u8, workers: u32)->{count: u64, ok: bool} fail
{
    let fd          = try stream.nativeFileDescriptor()
    let destination = buffer.buffer
    let length      = buffer.count
    let partSize    = Memory.align(length / workers, 4096)
    var parts: [MaxParallelFontReads] FontReadPart
    var group: Swag.TaskGroup
    for index in 1 until workers
    {
        let start = index * partSize
        let size  = index + 1 == workers ? length - start : partSize
        group.spawn(func|fd, offset, destination, start, size, index, &parts|()
        {
            parts[index] = readPositionalPart(fd, offset + start, destination + start, size)
        })
    }

    parts[0] = readPositionalPart(fd, offset, destination, partSize)
    group.wait()

    // Return the contiguous prefix in file order, as a single stream read does.
    var result = 0'u64
    for index in workers
    {
        if not parts[index].ok do
            return {count: 0, ok: false}
        result += parts[index].count
        if parts[index].count != partSize do
            break
    }

    return {count: result, ok: true}
}

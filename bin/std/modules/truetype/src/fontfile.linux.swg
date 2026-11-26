#global if #os == Swag.TargetOs.Linux

using Swag, Core

private const MaxParallelFontReads = 4'u32
private const MinParallelFontBytes = 8'u64 * 1024 * 1024

func fontReadWorkers(length: u64)->u32 =>
    length >= MinParallelFontBytes ? Math.min(Swag.workerCount(), MaxParallelFontReads) : 0

// Positional reads share the descriptor and write disjoint ranges of an owned buffer.
// A read error requests the ordinary stream path and its platform diagnostics.
func readParallelFontRange(stream: *File.FileStream, offset: u64, buffer: [..] u8, workers: u32)->{count: u64, ok: bool} fail
{
    let fd          = try stream.nativeFileDescriptor()
    let destination = buffer.buffer
    let length      = buffer.count
    let partSize    = Memory.align(length / workers, 4096)
    var counts: [MaxParallelFontReads] u64
    var errors: [MaxParallelFontReads] bool
    parallel for |fd, offset, destination, length, partSize, workers, &counts, &errors| index in workers
    {
        let start    = index * partSize
        let end      = index + 1 == workers ? length : start + partSize
        var position = start
        while position < end
        {
            let read = Linux.pread(fd, destination + position, end - position, cast(s64, offset + position))
            if read > 0
            {
                position += cast(u64, read)
                continue
            }

            if not read do
                break
            if Linux.errno() != Linux.EINTR
            {
                errors[index] = true
                break
            }
        }

        counts[index] = position - start
    }

    // Return the contiguous prefix in file order, as a single stream read does.
    var result = 0'u64
    for index in workers
    {
        if errors[index] do
            return {count: 0, ok: false}
        result += counts[index]
        if counts[index] != partSize do
            break
    }

    return {count: result, ok: true}
}

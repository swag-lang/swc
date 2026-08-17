#global public

using Core, Core.Errors

// Writes the bytes of an encoded video stream, to a file or to memory.
//
// An encoder receives one of these and appends to it frame by frame. A file sink holds one
// small write window and never accumulates the encoded stream, so writing a long video
// costs the memory of one frame rather than the memory of the result.
//
// A memory sink borrows its destination buffer: it must stay valid until the sink is
// closed, and it holds the whole encoded stream, which only a bounded clip should ask for.
#[Swag.NoCopy]
struct Sink
{
    internal
    {
        stream:       File.FileStream         // Open file, when the sink writes to a file.
        buffer:       #null *ConcatBuffer     // Borrowed destination, when the sink writes to memory.
        path:         String                  // File the sink writes, empty for a memory sink.
        pending:      Array'u8                // Write window holding bytes not yet handed to the file.
        pendingCount: u64                     // Number of valid bytes in the write window.
        written:      u64                     // Total number of bytes accepted by this sink.
        isFile:       bool                    // Whether the sink writes to `stream`.
    }
}

impl Sink
{
    // Size of the write window of a file sink.
    //
    // Frame markers and text headers are a few bytes each and would otherwise be one write
    // call apiece; a payload larger than this goes straight to the file instead.
    private const WindowSize = 64 * 1024'u64

    // Creates `fileName`, replacing any existing file.
    func createFile(fileName: string)->Sink fail
    {
        var result: retval
        result.stream = File.openWrite(fileName)
        result.path   = fileName
        result.isFile = true
        return result
    }

    // Appends the encoded stream to `buffer`.
    func createMemory(buffer: *ConcatBuffer)->Sink
    {
        var result: retval
        result.buffer = buffer
        return result
    }

    // Returns the file this sink writes, or an empty string for a memory sink.
    mtd const sourcePath()->string => .path

    // Returns the number of bytes written so far.
    mtd const position()->u64 => .written

    // Appends `bytes` to the stream.
    mtd write(bytes: const [..] u8) fail
    {
        let count = @countof(bytes)
        if !count do
            return

        .written += count
        if !.isFile
        {
            .buffer!.addBytes(bytes, contiguous: false)
            return
        }

        // A frame payload is written once and is larger than the window, so it goes straight
        // to the file rather than through a buffer that would copy it a second time.
        if count >= WindowSize
        {
            .flush()
            .stream.writeAll(bytes)
            return
        }

        if .pendingCount + count > WindowSize do
            .flush()
        if .pending.count != WindowSize do
            .pending.resize(WindowSize)
        Memory.copy(.pending.buffer! + .pendingCount, @dataof(bytes)!, count)
        .pendingCount += count
    }

    // Appends the bytes of `text` to the stream.
    mtd writeText(text: string) fail
    {
        .write(cast(const [..] u8) text)
    }

    // Hands every buffered byte to the file.
    mtd flush() fail
    {
        if !.pendingCount do
            return
        .stream.writeAll(.pending.toSlice()[0 until .pendingCount])
        .pendingCount = 0
    }

    // Flushes the stream and releases the file. Repeated calls do nothing.
    //
    // This is the operation whose failure decides whether the encoded stream is complete, so
    // it is called explicitly by [[Video.Writer.end]] rather than left to destruction.
    mtd close() fail
    {
        if !.isFile do
            return
        .flush()
        .stream.close()
    }
}

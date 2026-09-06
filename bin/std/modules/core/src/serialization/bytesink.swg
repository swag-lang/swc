#global public

using Core.Errors

// Writes the bytes of a stream to a file or to memory, through one cursor and one window.
//
// An encoder receives one of these and appends to it piece by piece. A file sink holds one
// small write window and never accumulates the stream, so writing a long one costs the memory
// of one piece rather than the memory of the result; a piece larger than the window goes
// straight to the file.
//
// A memory sink borrows its destination buffer: it must stay valid until the sink is closed,
// and it holds the whole stream, which only a bounded result should ask for.
#[Swag.NoCopy]
struct ByteSink
{
    internal
    {
        stream:       File.FileStream          // Open file, when the sink writes to a file.
        buffer:       *ConcatBuffer?           // Borrowed destination, when the sink writes to memory.
        origin:       ConcatBufferPosition     // Cursor the borrowed buffer held when the sink took it.
        fileName:     String                   // File the sink writes, empty for a memory sink.
        pending:      Array'u8                 // Write window holding bytes not yet handed to the file.
        pendingCount: u64                      // Number of valid bytes in the write window.
        written:      u64                      // Total number of bytes accepted by this sink.
        isFile:       bool                     // Whether the sink writes to `stream`.
    }
}

impl ByteSink
{
    // Size of the write window of a file sink, in bytes.
    //
    // Markers and headers are a few bytes each and would otherwise be one write call apiece; a
    // piece of at least this size goes straight to the file instead.
    const WindowSize = 64 * 1024'u64

    // Creates `fileName`, replacing any existing file.
    func createFile(fileName: string)->ByteSink fail
    {
        var result: retval
        result.stream   = File.openWrite(fileName)
        result.fileName = fileName
        result.isFile   = true
        return result
    }

    // Appends the stream to `buffer`.
    //
    // Whatever `buffer` already holds stays untouched, and stream offsets remain relative to the
    // first byte this sink writes, so a codec computes them the same way on both backings.
    func createMemory(buffer: *ConcatBuffer)->ByteSink
    {
        var result: retval
        result.buffer = buffer
        result.origin = buffer.position()
        return result
    }

    // Returns the file this sink writes, or an empty string for a memory sink.
    mtd const path()->string => .fileName

    // Returns the number of bytes written so far, which is where the next write lands.
    mtd const position()->u64 => .written

    // Appends `bytes` to the stream.
    mtd write(bytes: const [..] u8) fail
    {
        let count = bytes.count
        if !count do
            return

        .written += count
        if !.isFile
        {
            .buffer!.addBytes(bytes, contiguous: false)
            return
        }

        // A payload larger than the window is written once, so it goes straight to the file
        // rather than through a buffer that would copy it a second time.
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
        Memory.copy(.pending.buffer! + .pendingCount, bytes.buffer!, count)
        .pendingCount += count
    }

    // Appends the bytes of `text` to the stream.
    mtd writeText(text: string) fail
    {
        .write(cast(const [..] u8) text)
    }

    // Appends one byte.
    mtd writeByte(value: u8) fail
    {
        var stored = value
        .write(Swag.makeSlice(&stored, 1))
    }

    // Appends one value of type `T` laid out as the host stores it.
    //
    // This is the write for a binary layout declared as a struct, or for an integer whose byte
    // order is the host's. Use [[Core.ByteSink.writeLittleEndian]] or
    // [[Core.ByteSink.writeBigEndian]] for a persisted or transmitted integer.
    mtd(T) writeNative(value: T) fail
    {
        var stored = value
        .write(Swag.makeSlice(cast(const [*] u8) &stored, #sizeof(T)))
    }

    // Appends an integer of type `T` in little-endian byte order.
    mtd(T) writeLittleEndian(value: T) fail
    {
        .writeNative(Math.nativeToLittleEndian(value))
    }

    // Appends an integer of type `T` in big-endian byte order.
    mtd(T) writeBigEndian(value: T) fail
    {
        .writeNative(Math.nativeToBigEndian(value))
    }

    // Rewrites bytes this sink already accepted, at `offset` bytes from the start of its stream.
    //
    // A container header carries totals a codec only learns once the last piece is written: a
    // file size, a frame count, the size of the chunk holding the frames. Patching is how those
    // fields are filled without holding the stream: the encoder writes a placeholder in the
    // header, remembers where it went, and overwrites it here.
    //
    // The patched range must lie entirely inside what the sink already wrote; a range reaching
    // past the end fails rather than extending the stream. The write position is unchanged, so
    // appending resumes exactly where it stopped.
    mtd patch(offset: u64, bytes: const [..] u8) fail
    {
        let count = bytes.count
        if !count do
            return
        if offset > .written or count > .written - offset do
            fail BadParameterError{"byte sink patch runs past the end of the written stream"}

        if !.isFile
        {
            let target = .buffer!
            let resume = target.position()
            target.setPosition(.origin)
            target.advance(offset)
            target.addBytes(bytes, contiguous: false)
            target.setPosition(resume)
            return
        }

        // The window can still hold bytes covering the patched range, so what is buffered reaches
        // the file first; the patch would otherwise be overwritten by the next flush.
        .flush()
        .stream.writeAllAt(offset, bytes)
        .stream.seek(.Begin, .written)
    }

    // Hands every buffered byte to the file. A memory sink has nothing to flush.
    mtd flush() fail
    {
        if !.pendingCount do
            return
        .stream.writeAll(.pending.toSlice()[0 until .pendingCount])
        .pendingCount = 0
    }

    // Flushes the stream and releases the file. Repeated calls do nothing.
    //
    // This is the operation whose failure decides whether the stream is complete, so an
    // encoder calls it explicitly rather than leaving it to destruction: a sink that leaves
    // scope unclosed drops whatever its window still holds.
    mtd close() fail
    {
        if !.isFile do
            return
        .flush()
        .stream.close()
    }
}

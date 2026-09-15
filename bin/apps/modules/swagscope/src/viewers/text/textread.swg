#global internal

using Core

// A single immutable read request. The GUI only consumes its result after the task finishes.
struct TextRead
{
    using operation: Viewer.BackgroundOperation
    fileName:        String
    encoding:        Text.Encoding
    start:           u64
    end:             u64
    limit:           u64
    contentStart:    u64
    replace:         bool
    cancelled:       u32
    error:           String
    failed:          bool
    invalidUtf8:     bool
    text:            String
}

impl TextRead
{
    mtd read() fail
    {
        var stream = try File.openReadLive(.fileName.toString())
        defer stream.close()
        if .replace
        {
            var head: [4] u8
            let count = try stream.read(head)
            .contentStart = Text.hasBom(head[0 until count], .encoding) ? Text.bomLength(.encoding) : 0
            .start        = Math.max(.start, .contentStart)
            .start        -= (.start - .contentStart) % Text.unitSize(.encoding)
        }

        // Only a random seek may begin in a multibyte character. Retry its boundary, never
        // reinterpret a malformed chunk in the middle of an otherwise continuous read.
        for adjustment in (.replace ? 4'u64 : 1'u64)
        {
            if Atomic.get(&.cancelled) do
                return
            discard try stream.seek(.Begin, .start)
            var chunk = catch stream.readTextChunk(.limit, .encoding) as readError
            if readError == null
            {
                .end  = try stream.position()
                .text = #move chunk
                return
            }

            .error = Errors.message(readError)
            if cast #try (*Errors.InvalidFormatError) readError == null
            {
                .failed = true
                return
            }

            if not .replace or .start == .contentStart or adjustment == 3
            {
                .invalidUtf8 = .encoding == .Utf8 and not .contentStart
                .failed      = true
                return
            }

            .start += Text.unitSize(.encoding)
        }
    }

    mtd startRead(fileName: string, encoding: Text.Encoding, start, limit: u64, replace: bool)
    {
        Swag.assert(not .started)
        .fileName  = fileName
        .encoding  = encoding
        .start     = start
        .limit     = limit
        .replace   = replace
        .cancelled = 0
        .error.clear()
        .failed      = false
        .invalidUtf8 = false
        .text.clear()
        .started = true
        let request = me
        .task.submit(func|request|()
        {
            catch request.read() as readError
            if readError != null
            {
                request.failed = true
                request.error  = Errors.message(readError)
            }
        })
    }

    mtd opDrop() { .wait() }
}

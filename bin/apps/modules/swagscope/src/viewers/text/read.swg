#global internal
#global namespace Viewers.PlainText

using Core

// One background read of part of a text file. The GUI consumes its result only once the task has finished.
struct Read
{
    using operation: Viewer.BackgroundOperation
    fileName:        String
    encoding:        Text.Encoding
    start:           u64
    end:             u64
    limit:           u64
    contentStart:    u64
    replace:         bool
    error:           String
    failed:          bool
    invalidUtf8:     bool
    text:            String
}

impl Read
{
    // Reads the requested chunk on the worker, moving a random seek off a split character.
    mtd read() fail
    {
        var stream = try File.openReadLive(.fileName)
        if .replace
        {
            var head: [4] u8
            let count = try stream.read(head)
            .contentStart = Text.hasBom(head[until count], .encoding) ? Text.bomLength(.encoding) : 0
            .start        = Math.max(.start, .contentStart)
            .start        -= (.start - .contentStart) % Text.unitSize(.encoding)
        }

        // Only a random seek may begin in a multibyte character. Retry its boundary, never
        // reinterpret a malformed chunk in the middle of an otherwise continuous read.
        for adjustment in (.replace ? 4'u64 : 1'u64)
        {
            if Swag.isCancelled() do
                return
            discard try stream.seek(.Begin, .start)
            var readErrorOutcome: Swag.Error
            var chunk: #decltype(expect stream.readTextChunk(.limit, .encoding))
            catch { chunk = try stream.readTextChunk(.limit, .encoding) } as readErrorOutcome
            let readError = readErrorOutcome.value()
            if readError == null
            {
                .end  = try stream.position()
                .text = #move chunk
                return
            }

            .error = Viewer.failureText(readError)
            if not (readError is Errors.InvalidFormatError)
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

    // Starts reading about `limit` bytes of `fileName` from `start` on a worker; `owner` receives a
    // [[Gui.TaskEvent]] when the chunk is ready.
    //
    // `replace` asks for a new resident window, which may begin inside a character; otherwise the
    // chunk continues the text already shown.
    mtd startRead(fileName: string, encoding: Text.Encoding, start, limit: u64, replace: bool, owner: *Wnd? = null)
    {
        Swag.assert(not .started)
        .fileName = fileName
        .encoding = encoding
        .start    = start
        .limit    = limit
        .replace  = replace
        .error.clear()
        .failed      = false
        .invalidUtf8 = false
        .text.clear()

        let request = me
        .submit(func|request|()
        {
            catch request.read()
            {
                request.failed = true
                request.error  = Viewer.failureText(Swag.err)
            }
        },
                owner)
    }

    // Asks the read in flight to stop; its result is then discarded.
    mtd cancel() => .task.cancel()

    // Returns whether the last read was asked to stop.
    mtd const wasCancelled()->bool => .task.isCancelled()

    mtd opDrop() { .wait() }
}

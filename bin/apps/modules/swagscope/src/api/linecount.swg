#global public
#global namespace Viewer

using Core

const LineCountScanLimit = 64 * 1024 * 1024'u64     // Bytes one answer of [[Viewer.LineCounter]] may read.

// Numbers the lines of a text file a viewer shows one window at a time, so a line-number gutter
// keeps counting the lines of the whole file whichever window is resident.
//
// Each answer counts line feeds from the closest line start already numbered, so walking through a
// file reads every byte about once.
struct LineCounter
{
    numberedOffset: u64     // Byte offset at the start of `numberedLine`.
    numberedLine:   u64 = 1 // Exact whole-file line number at `numberedOffset`.
}

impl LineCounter
{
    // Forgets every offset already numbered, for a file whose bytes or encoding changed.
    mtd reset()
    {
        .numberedOffset = 0
        .numberedLine   = 1
    }

    // Returns the number of the line holding byte `offset` of `fileName`, whose text is encoded as
    // `encoding` from byte `contentStart` on, or zero when the file cannot be read there or the
    // answer would read more than `scanLimit` bytes.
    //
    // `offset` must lie on a unit boundary of `encoding` counted from `contentStart`, as any
    // window a text reader decodes from does.
    mtd lineAt(fileName: string, offset: u64, encoding = Text.Encoding.Utf8, contentStart = 0'u64, scanLimit = LineCountScanLimit)->u64
    {
        var start = contentStart
        var line  = 1'u64
        if offset >= .numberedOffset and .numberedOffset >= contentStart
        {
            start = .numberedOffset
            line  = .numberedLine
        }

        if offset < start do
            return offset == 0 ? 1 : 0
        if offset - start > scanLimit do
            return 0

        let scan = .scan(fileName, encoding, start, line, offset, Swag.U64.Max)
        if scan.failed or scan.atEnd do
            return 0

        .numberedOffset = scan.lineStart
        .numberedLine   = scan.line
        return scan.line
    }

    // Returns the offset of the first byte of line `line` of `fileName`, whose text is encoded as
    // `encoding` from byte `contentStart` on. A line past the last one answers the start of the
    // last line, as a typed position past the end names the end.
    //
    // Returns `Swag.U64.Max` when `line` is zero, the file cannot be read, or the answer would read
    // more than [[Viewer.LineCountScanLimit]] past the closest line already numbered.
    mtd offsetOfLine(fileName: string, line: u64, encoding = Text.Encoding.Utf8, contentStart = 0'u64)->u64
    {
        if not line do
            return Swag.U64.Max
        if line == 1 do
            return contentStart

        var start     = contentStart
        var startLine = 1'u64
        if line >= .numberedLine and .numberedOffset >= contentStart
        {
            start     = .numberedOffset
            startLine = .numberedLine
        }

        if line == startLine do
            return start

        let scan = .scan(fileName, encoding, start, startLine, start + LineCountScanLimit, line)
        if scan.failed or (scan.line != line and not scan.atEnd) do
            return Swag.U64.Max

        .numberedOffset = scan.lineStart
        .numberedLine   = scan.line
        return scan.lineStart
    }
}

// Where a line-feed count of a [[Viewer.LineCounter]] stopped.
private struct LineScan
{
    line:      u64      // Number of the line the scan stopped in.
    lineStart: u64      // Offset of the first byte of that line.
    atEnd:     bool     // Whether the scan stopped because the file ended.
    failed:    bool     // Whether the file could not be read.
}

impl LineCounter
{
    // Counts the line feeds of `fileName` from `start`, which begins line `line`, and stops at
    // byte `limit`, at the end of the file, or as soon as line `target` begins, whichever comes
    // first.
    //
    // A line feed is one unit holding 10 in the encoding's byte order, never a byte that happens
    // to be 10 inside a wider character.
    private mtd const scan(fileName: string, encoding: Text.Encoding, start, line, limit, target: u64)->LineScan
    {
        var result: #returntype
        result.line      = line
        result.lineStart = start

        var file = catch File.openReadLive(fileName)
        {
            result.failed = true
            return result
        }

        defer file.close()
        discard catch file.seek(.Begin, start)

        let unit      = Text.unitSize(encoding)
        let feedIndex = encoding == .Utf16Be or encoding == .Utf32Be ? unit - 1 : 0

        let chunkSize = 64 * 1024'u64
        var buffer: Array'u8
        buffer.resize(chunkSize)
        var position = start
        while position < limit and result.line < target
        {
            let wanted = Math.min(limit - position, chunkSize)
            let count  = catch file.read(buffer.toSlice()[until wanted])
            {
                result.failed = true
                return result
            }

            if not count
            {
                result.atEnd = true
                return result
            }

            if count % unit
            {
                result.failed = true
                return result
            }

            var index = 0'u64
            while index < count and result.line < target
            {
                if buffer[index + feedIndex] == '\n'
                {
                    var feed = true
                    for byte in unit where byte != feedIndex and buffer[index + byte] != 0 do
                        feed = false
                    if feed
                    {
                        result.line      += 1
                        result.lineStart = position + index + unit
                    }
                }

                index += unit
            }

            position += count
        }

        return result
    }
}

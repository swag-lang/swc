#global public
#global namespace Viewer

using Core

const LineCountScanLimit = 64 * 1024 * 1024'u64     // Bytes one answer of [[Viewer.LineCounter]] may read.
private const LineEstimateSampleCount = 16'u64
private const LineEstimateSampleSize  = 4 * 1024'u64

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
    // CR, LF, and CRLF each end one line; bytes in a line ending belong to the preceding line.
    // `offset` must lie on a unit boundary of `encoding` counted from `contentStart`, as any window
    // a text reader decodes from does.
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

        let readLimit = start > Swag.U64.Max - scanLimit ? Swag.U64.Max : start + scanLimit
        let scan = .scan(fileName, encoding, start, line, offset, Swag.U64.Max, readLimit)
        if scan.failed or scan.atEnd do
            return 0

        .numberedOffset = scan.lineStart
        .numberedLine   = scan.line
        return scan.line
    }

    // Returns the offset of the first byte of line `line` of `fileName`, whose text is encoded as
    // `encoding` from byte `contentStart` on. A line past the last one answers the start of the
    // last line, as a typed position past the end names the end. CR, LF, and CRLF each end one
    // line, and the returned offset follows the complete line ending.
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

        let readLimit = start > Swag.U64.Max - LineCountScanLimit ? Swag.U64.Max : start + LineCountScanLimit
        let scan = .scan(fileName, encoding, start, startLine, readLimit, line, readLimit)
        if scan.failed or (scan.line != line and not scan.atEnd) do
            return Swag.U64.Max

        .numberedOffset = scan.lineStart
        .numberedLine   = scan.line
        return scan.lineStart
    }

    // Estimates a byte offset for a line when an exact scan is too costly.
    //
    // The estimate samples at most 64 KiB in sixteen evenly spaced windows. It does not change
    // the exact line anchor. Returns [[Swag.U64.Max]] when the file cannot be sampled or the
    // samples contain no line breaks, so the caller can distinguish an unavailable estimate.
    mtd estimateOffsetOfLine(fileName: string, line: u64, encoding = Text.Encoding.Utf8, contentStart = 0'u64)->u64
    {
        if not line do
            return Swag.U64.Max
        if line == 1 do
            return contentStart

        var file = catch File.openReadLive(fileName) { return Swag.U64.Max }
        defer file.close()
        let fileSize = catch file.size() { return Swag.U64.Max }
        if fileSize <= contentStart do
            return Swag.U64.Max

        let available = fileSize - contentStart
        let unit = Text.unitSize(encoding)
        let sampleSize = Math.min(LineEstimateSampleSize, available / unit * unit)
        if not sampleSize do
            return Swag.U64.Max

        let feedIndex = encoding == .Utf16Be or encoding == .Utf32Be ? unit - 1 : 0
        let lastStart = fileSize - sampleSize
        let intervals = LineEstimateSampleCount - 1
        var sampledBytes = 0'u64
        var sampledLineBreaks = 0'u64
        var buffer: Array'u8
        buffer.resize(sampleSize)

        for sample in LineEstimateSampleCount
        {
            let span = lastStart - contentStart
            let relative = span / intervals * sample + span % intervals * sample / intervals
            let start = contentStart + relative / unit * unit
            discard catch file.seek(.Begin, start) { return Swag.U64.Max }
            let count = catch file.read(buffer.toSlice()) { return Swag.U64.Max }
            if count % unit do
                return Swag.U64.Max
            sampledBytes += count

            var at = 0'u64
            var previousCr = false
            while at < count
            {
                let marker = encodedLineBreak(buffer, at, unit, feedIndex)
                if marker == '\r' or (marker == '\n' and not previousCr) do
                    sampledLineBreaks += 1
                previousCr = marker == '\r'

                at += unit
            }
        }

        if not sampledLineBreaks do
            return Swag.U64.Max
        let bytesPerLine = Math.max(sampledBytes / sampledLineBreaks, unit)
        let countedLines = available / bytesPerLine
        let estimatedLines = countedLines == Swag.U64.Max ? countedLines : countedLines + 1
        let uncertainty = Math.max(8, estimatedLines / 20)
        if line > estimatedLines and line - estimatedLines > uncertainty do
            return Swag.U64.Max

        let lineDelta = line - 1
        let lastOffset = available - 1
        let relativeOffset = lineDelta > lastOffset / bytesPerLine ? lastOffset : lineDelta * bytesPerLine
        let offset = contentStart + relativeOffset
        return contentStart + (offset - contentStart) / unit * unit
    }
}

// Where a line-break count of a [[Viewer.LineCounter]] stopped.
private struct LineScan
{
    line:      u64      // Number of the line the scan stopped in.
    lineStart: u64      // Offset of the first byte of that line.
    atEnd:     bool     // Whether the scan stopped because the file ended.
    failed:    bool     // Whether the file could not be read.
}

impl LineCounter
{
    // Counts the line breaks of `fileName` from `start`, which begins line `line`, and stops at
    // byte `limit`, at the end of the file, or as soon as line `target` begins, whichever comes
    // first.
    //
    // CR, LF, and CRLF each end one line. A marker is one encoded unit, never a byte that happens
    // to be 10 or 13 inside a wider character.
    private mtd const scan(fileName: string, encoding: Text.Encoding, start, line, limit, target, readLimit: u64)->LineScan
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
        let fileSize  = catch file.size()
        {
            result.failed = true
            return result
        }

        let chunkSize = 64 * 1024'u64
        var buffer: Array'u8
        buffer.resize(chunkSize)
        var position = start
        var pendingCr = false
        var pendingCrEnd = start
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
                break
            }

            if count % unit
            {
                result.failed = true
                return result
            }

            var index = 0'u64
            while index < count and result.line < target
            {
                let marker = encodedLineBreak(buffer, index, unit, feedIndex)
                if pendingCr
                {
                    if marker == '\n'
                    {
                        result.line      += 1
                        result.lineStart = position + index + unit
                        pendingCr = false
                        index += unit
                        continue
                    }

                    result.line      += 1
                    result.lineStart = pendingCrEnd
                    pendingCr = false
                    if result.line >= target do
                        break
                }

                if marker == '\r'
                {
                    pendingCr = true
                    pendingCrEnd = position + index + unit
                }
                elif marker == '\n'
                {
                    result.line      += 1
                    result.lineStart = position + index + unit
                }

                index += unit
            }

            position += count
        }

        // A CR starts a line break unless the next encoded unit is LF. At a requested byte
        // boundary, inspect the following unit so offsets between CR and LF remain on the old line.
        if pendingCr and result.line < target
        {
            var pairedWithLf = false
            if pendingCrEnd == limit and limit < fileSize
            {
                if readLimit - limit < unit
                {
                    result.failed = true
                    return result
                }
                discard catch file.seek(.Begin, limit)
                var lookahead: Array'u8
                lookahead.resize(unit)
                let lookaheadCount = catch file.read(lookahead.toSlice())
                {
                    result.failed = true
                    return result
                }
                pairedWithLf = lookaheadCount == unit and encodedLineBreak(lookahead, 0, unit, feedIndex) == '\n'
            }

            if not pairedWithLf
            {
                result.line      += 1
                result.lineStart = pendingCrEnd
            }
        }

        return result
    }
}

// Returns the ASCII CR or LF marker in one encoded text unit, or zero for any other unit.
private func encodedLineBreak(bytes: Array'u8, at, unit, markerIndex: u64)->u8
{
    let marker = bytes[at + markerIndex]
    if marker != '\r' and marker != '\n' do
        return 0

    for byte in unit where byte != markerIndex and bytes[at + byte] != 0 do
        return 0
    return marker
}

#global public
#global namespace Viewer

using Core

const LineCountScanLimit = 64 * 1024 * 1024'u64     // Bytes one answer of [[Viewer.LineCounter]] may read.

// Numbers the lines of a text file a viewer shows one window at a time, so a line-number gutter
// keeps counting the lines of the whole file whichever window is resident.
//
// Each answer counts line feeds from the closest offset already numbered, so walking through a
// file reads every byte about once.
struct LineCounter
{
    numberedOffset: u64
    numberedLine:   u64 = 1
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
    // answer would read more than [[Viewer.LineCountScanLimit]].
    //
    // `offset` must lie on a unit boundary of `encoding` counted from `contentStart`, as any
    // window a text reader decodes from does.
    mtd lineAt(fileName: string, offset: u64, encoding = Text.Encoding.Utf8, contentStart = 0'u64)->u64
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
        if offset - start > LineCountScanLimit do
            return 0

        var file = catch File.openReadLive(fileName) { return 0 }
        defer file.close()
        discard catch file.seek(.Begin, start)

        // A line feed is one unit holding 10 in the encoding's byte order, never a byte that
        // happens to be 10 inside a wider character.
        let unit      = Text.unitSize(encoding)
        let feedIndex = encoding == .Utf16Be or encoding == .Utf32Be ? unit - 1 : 0

        let chunkSize = 64 * 1024'u64
        var buffer: Array'u8
        buffer.resize(chunkSize)
        var remaining = offset - start
        while remaining
        {
            let wanted = Math.min(remaining, chunkSize)
            let count  = catch file.read(buffer.toSlice()[until wanted]) { return 0 }
            if not count or count % unit do
                return 0

            var index = 0'u64
            while index < count
            {
                if buffer[index + feedIndex] == '\n'
                {
                    var feed = true
                    for byte in unit where byte != feedIndex and buffer[index + byte] != 0 do
                        feed = false
                    if feed do
                        line += 1
                }

                index += unit
            }

            remaining -= count
        }

        .numberedOffset = offset
        .numberedLine   = line
        return line
    }
}

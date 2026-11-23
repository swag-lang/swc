#global internal

using Core

enum TextStatisticsExtent
{
    Unknown
    Exact
    Sampled
}

// Byte, line, word, and decoded Unicode scalar counts of one text, and how its lines end.
struct TextStatistics
{
    bytes:      u64
    lines:      u64
    words:      u64
    characters: u64
    lf:         u64      // Lines ended by a lone line feed.
    crlf:       u64      // Lines ended by a carriage return and a line feed.
    cr:         u64      // Lines ended by a lone carriage return.
    unended:    bool     // Whether the text stops on a line with no line break after it.
    longest:    u64      // Characters of the longest line, its line break left out.
    longestLine: u64     // First line with the longest content, one-based; zero when there is none.
    controls:   u64      // Control characters other than a tabulation and the line breaks.
    replaced:   u64      // U+FFFD characters, which is what bytes the encoding cannot read become.
    extent:     TextStatisticsExtent
}

impl TextStatistics
{
    // Names how the lines end: one convention alone, `LF`, or each one with its count, the most
    // frequent first, `CRLF 12 · LF 3`. Empty for a text without a line break.
    mtd const lineEnds()->String
    {
        var ends: [3] {name: string, count: u64} = [{name: "LF", count: .lf}, {name: "CRLF", count: .crlf}, {name: "CR", count: .cr}]
        var kinds = 0'u32
        for end in ends where end.count do
            kinds += 1
        var result: #returntype
        if kinds == 0 do
            return result

        // The three counts are sorted by hand: a selection over three entries reads plainly.
        for 3
        {
            var best = Swag.U64.Max
            for end, index in ends where end.count and (best == Swag.U64.Max or end.count > ends[best].count) do
                best = index
            if best == Swag.U64.Max do
                break
            if result.count do
                result += " · "
            result += ends[best].name
            if kinds > 1 do
                result += Format.toString(" %", ends[best].count)
            ends[best].count = 0
        }

        return result
    }
}

// Counts lines, words, and Unicode scalars across chunks, keeping word boundaries and CRLF pairs intact.
struct TextStatisticsCounter
{
    totals:             TextStatistics
    inWord:             bool
    sawRune:            bool
    previousCr:         bool
    endedWithLineBreak: bool
    lineLength:         u64     // Characters of the line being read so far.
    lineNumber:         u64 = 1
}

impl TextStatisticsCounter
{
    // Counts `text`, the next chunk of the stream.
    mtd append(text: string, sourceBytes: u64 = 0)
    {
        .totals.bytes += sourceBytes
        var scan = 0'u64
        while scan < text.count
        {
            let {c, eat} = Utf8.decodeRune(text[scan to])
            scan += eat
            if not .sawRune and c == '\uFEFF' do
                continue
            .sawRune = true
            .totals.characters += 1
            if c == '\r' or c == '\n'
            {
                if .lineLength > .totals.longest
                {
                    .totals.longest     = .lineLength
                    .totals.longestLine = .lineNumber
                }
                .lineLength     = 0
                let startsNextLine = c == '\r' or not .previousCr
                if startsNextLine
                {
                    .totals.lines += 1
                    .lineNumber  += 1
                }

                // A carriage return counts alone until the line feed that pairs it arrives,
                // possibly in the next chunk.
                if c == '\r'
                {
                    .totals.cr += 1
                }
                elif .previousCr
                {
                    .totals.cr   -= 1
                    .totals.crlf += 1
                }
                else
                {
                    .totals.lf += 1
                }

                .previousCr         = c == '\r'
                .endedWithLineBreak = true
                .inWord             = false
                continue
            }

            .previousCr         = false
            .endedWithLineBreak = false
            .lineLength         += 1
            if c == 0xFFFD do
                .totals.replaced += 1
            elif c != '\t' and (c < 0x20 or (c >= 0x7F and c < 0xA0)) do
                .totals.controls += 1
            if Unicode.isSpace(c)
            {
                .inWord = false
                continue
            }

            if not .inWord do
                .totals.words += 1
            .inWord = true
        }
    }

    // Returns the counts, closing a last line that does not end with a line break.
    mtd const finish(extent: TextStatisticsExtent = .Unknown)->TextStatistics
    {
        var result = .totals
        if .lineLength > result.longest
        {
            result.longest     = .lineLength
            result.longestLine = .lineNumber
        }
        result.extent = extent
        if .sawRune and not .endedWithLineBreak
        {
            result.lines   += 1
            result.unended = true
        }

        return result
    }

    // Counts the bytes, lines, and words of a UTF-8 file, read in chunks.
    //
    // A count asked to stop returns what it has so far; its owner no longer shows it.
    func loadUtf8(fileName: string)->TextStatistics fail
    {
        var stream = try File.openReadLive(fileName)
        var counter: TextStatisticsCounter
        while not Swag.isCancelled()
        {
            let previousPosition = try stream.position()
            let chunk = try stream.readTextChunk(256 * 1024, .Utf8)
            if chunk.isEmpty() do
                return counter.finish(.Exact)
            let position = try stream.position()
            counter.append(chunk, position - previousPosition)
        }

        return counter.finish()
    }
}

#global internal

using Core

// Line, word, and decoded Unicode scalar counts of one text, and how its lines end.
struct TextStatistics
{
    lines:      u64
    words:      u64
    characters: u64
    lf:         u64     // Lines ended by a lone line feed.
    crlf:       u64     // Lines ended by a carriage return and a line feed.
    cr:         u64     // Lines ended by a lone carriage return.
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
}

impl TextStatisticsCounter
{
    // Counts `text`, the next chunk of the stream.
    mtd append(text: string)
    {
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
                if c == '\r' or not .previousCr do
                    .totals.lines += 1

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
    mtd const finish()->TextStatistics
    {
        var result = .totals
        if .sawRune and not .endedWithLineBreak do
            result.lines += 1
        return result
    }

    // Counts the lines and words of a UTF-8 file, read in chunks.
    //
    // A count asked to stop returns what it has so far; its owner no longer shows it.
    func loadUtf8(fileName: string)->TextStatistics fail
    {
        var stream = try File.openReadLive(fileName)
        var counter: TextStatisticsCounter
        while not Swag.isCancelled()
        {
            let chunk = try stream.readTextChunk(256 * 1024, .Utf8)
            if chunk.isEmpty() do
                return counter.finish()
            counter.append(chunk)
        }

        return counter.finish()
    }
}

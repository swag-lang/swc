#global internal

using Core

// Line and word counts of one text.
struct TextStatistics
{
    lines: u64
    words: u64
}

// Counts lines and words across streamed chunks, keeping Unicode word boundaries and CRLF pairs intact.
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
            if c == '\r' or c == '\n'
            {
                if c == '\r' or not .previousCr do
                    .totals.lines += 1
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
    func loadUtf8(fileName: string)->TextStatistics fail
    {
        var stream = try File.openReadLive(fileName)
        defer stream.close()
        var counter: TextStatisticsCounter
        while true
        {
            let chunk = try stream.readTextChunk(256 * 1024, .Utf8)
            if chunk.isEmpty() do
                return counter.finish()
            counter.append(chunk.toString())
        }
    }
}

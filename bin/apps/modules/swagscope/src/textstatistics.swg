#global internal

using Core

struct TextStatistics
{
    lines: u64
    words: u64
}

// Keeps Unicode word boundaries and CRLF pairs intact across streamed chunks.
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

    mtd const finish()->TextStatistics
    {
        var result = .totals
        if .sawRune and not .endedWithLineBreak do
            result.lines += 1
        return result
    }

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

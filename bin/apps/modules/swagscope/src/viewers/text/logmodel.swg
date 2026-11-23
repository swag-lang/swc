#global internal
#global namespace Viewers.PlainText

using Core

// The severity a log prefix spells without guessing from its message.
enum LogSeverity
{
    Unknown,
    Trace,
    Debug,
    Info,
    Warning,
    Error,
    Fatal,
}

// One source event and its exact byte range in the original text.
struct LogEvent
{
    startOffset: u64
    endOffset:   u64
    timestamp:   String
    severity:    LogSeverity
    recognized:  bool
}

// A conservative event grouping over a text snapshot. Unrecognized lines remain source text.
struct LogDocument
{
    source: String
    events: Array'LogEvent
}

impl LogDocument
{
    // Returns the source bytes owned by `event`, without normalizing line endings or spelling.
    mtd const eventText(event: const *LogEvent)->string
    {
        return .source[event.startOffset until event.endOffset]
    }

    // Groups only lines with a strong timestamp/severity prefix; indented and stack-trace lines
    // remain attached to the preceding event. Every stored range points into the exact source.
    func parse(text: string)->LogDocument
    {
        func digit(value: u8)->bool => value >= '0' and value <= '9'

        func severityAt(line: string, offset: *u64)->LogSeverity
        {
            var at = offset[]
            while at < line.count and (line[at] == '[' or line[at] == ' ' or line[at] == '\t') do
                at += 1

            // A severity may follow a timestamp, a bracket, or begin the line.
            if at < line.count and line[at] == '[' do
                at += 1
            while at < line.count and (digit(line[at]) or line[at] == '-' or line[at] == ':' or line[at] == 'T' or line[at] == 'Z' or line[at] == '.' or line[at] == '+' or line[at] == ' ' or line[at] == '/') do
                at += 1
            while at < line.count and (line[at] == ']' or line[at] == ' ' or line[at] == '\t' or line[at] == '-' or line[at] == ':' or line[at] == '|') do
                at += 1

            let tokenStart = at
            while at < line.count and ((line[at] >= 'A' and line[at] <= 'Z') or (line[at] >= 'a' and line[at] <= 'z')) do
                at += 1
            if at == tokenStart do
                return .Unknown

            let token = line[tokenStart until at]
            if at < line.count and line[at] != ':' and line[at] != ']' and line[at] != ' ' and line[at] != '\t' and line[at] != '|' do
                return .Unknown

            offset[] = at
            let lowerToken = String.toLower(token)
            switch lowerToken.toString()
            {
            case "trace", "verbose": return .Trace
            case "debug": return .Debug
            case "info", "notice": return .Info
            case "warn", "warning": return .Warning
            case "error", "err": return .Error
            case "fatal", "critical", "crit", "panic": return .Fatal
            default: return .Unknown
            }
        }

        func timestampEnd(line: string)->u64
        {
            // ISO-like dates and times are recognized only at the start of a line (or inside
            // one opening bracket), and only when the complete date/time shape is present.
            var at = line.count and line[0] == '[' ? 1'u64 : 0'u64
            if at + 10 <= line.count and digit(line[at]) and digit(line[at + 1]) and digit(line[at + 2]) and digit(line[at + 3]) and
               line[at + 4] == '-' and digit(line[at + 5]) and digit(line[at + 6]) and line[at + 7] == '-' and digit(line[at + 8]) and digit(line[at + 9])
            {
                at += 10
                if at < line.count and (line[at] == 'T' or line[at] == ' ')
                {
                    at += 1
                    if at + 8 <= line.count and digit(line[at]) and digit(line[at + 1]) and line[at + 2] == ':' and digit(line[at + 3]) and digit(line[at + 4]) and line[at + 5] == ':' and digit(line[at + 6]) and digit(line[at + 7])
                    {
                        at += 8
                        if at < line.count and line[at] == '.'
                        {
                            at += 1
                            while at < line.count and digit(line[at]) do
                                at += 1
                        }
                        if at < line.count and (line[at] == 'Z' or line[at] == 'z') do
                            at += 1
                    }
                    else do
                        return 0
                }

                return at
            }

            // Common syslog month/day/time prefix, for example "Nov 23 08:15:30".
            var month: String
            if at + 3 <= line.count
            {
                month = String.toLower(line[at until at + 3])
            }
            if month != "jan" and month != "feb" and month != "mar" and month != "apr" and month != "may" and month != "jun" and month != "jul" and month != "aug" and month != "sep" and month != "oct" and month != "nov" and month != "dec" do
                return 0
            at += 3
            if at >= line.count or line[at] != ' ' do
                return 0
            while at < line.count and line[at] == ' ' do
                at += 1
            if at >= line.count or not digit(line[at]) do
                return 0
            at += 1
            if at < line.count and digit(line[at]) do
                at += 1
            if at >= line.count or line[at] != ' ' do
                return 0
            at += 1
            if at + 8 > line.count or not digit(line[at]) or not digit(line[at + 1]) or line[at + 2] != ':' or not digit(line[at + 3]) or not digit(line[at + 4]) or line[at + 5] != ':' or not digit(line[at + 6]) or not digit(line[at + 7]) do
                return 0
            return at + 8
        }

        func isContinuation(line: string)->bool
        {
            if line.count == 0 do
                return false
            if line[0] == ' ' or line[0] == '\t' do
                return true

            let lower = String.toLower(line)
            return Utf8.startsWith(lower, "at ") or
                   Utf8.startsWith(lower, "caused by:") or
                   Utf8.startsWith(lower, "suppressed:") or
                   Utf8.startsWith(lower, "traceback ") or
                   Utf8.startsWith(lower, "... ")
        }

        var result: LogDocument
        result.source = text
        var lineStart = 0'u64
        while lineStart < text.count
        {
            var lineEnd = lineStart
            while lineEnd < text.count and text[lineEnd] != '\n' do
                lineEnd += 1

            var contentEnd = lineEnd
            if contentEnd > lineStart and text[contentEnd - 1] == '\r' do
                contentEnd -= 1
            let line = text[lineStart until contentEnd]
            var levelOffset = 0'u64
            let severity = severityAt(line, &levelOffset)
            let timestampLength = timestampEnd(line)
            let recognized = severity != .Unknown or timestampLength > 0

            if recognized
            {
                var timestamp: String
                if timestampLength do
                    timestamp = line[0 until timestampLength]
                result.events.add({startOffset: lineStart, endOffset: contentEnd, timestamp: timestamp, severity: severity, recognized: true})
            }
            elif isContinuation(line) and not result.events.isEmpty()
            {
                result.events.back().endOffset = contentEnd
            }
            else
            {
                result.events.add({startOffset: lineStart, endOffset: contentEnd, timestamp: {}, severity: LogSeverity.Unknown, recognized: false})
            }

            lineStart = lineEnd + (lineEnd < text.count ? 1'u64 : 0'u64)
        }

        return result
    }
}

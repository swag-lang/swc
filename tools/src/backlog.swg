#global namespace Tool

using Core

private struct BacklogEntry
{
    heading:      String
    line:         u64
    nextAction:   bool
    completeWhen: bool
    current:      bool
}

private func parseDecimal(text: string, start: u64)->{value: u32, end: u64}
{
    var value: u32
    var pos = start
    while pos < @countof(text) and Latin1.isDigit(text[pos])
    {
        value = value * 10 + cast(u32) (text[pos] - '0')
        pos   += 1
    }

    return {value, pos}
}

private func reportBacklogFields(fileName: string, entry: *BacklogEntry)->u32
{
    var errors: u32
    if !entry.nextAction
    {
        Console.println("error: ", fileName, ":", entry.line, ": ", entry.heading, " has no '- Next:' field")
        errors += 1
    }

    if !entry.completeWhen
    {
        Console.println("error: ", fileName, ":", entry.line, ": ", entry.heading, " has no '- Complete when:' field")
        errors += 1
    }

    return errors
}

private func auditBacklogFile(fileName: string, seen: *HashSet'String, maxBacklog: *u32)->u32 fail
{
    let content    = try File.readAllText(fileName)
    var errors: u32
    var entry:  BacklogEntry
    var haveEntry  = false
    var lineNumber = 0'u64

    for line in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        if !Utf8.startsWith(cast(const [..] u8) line, "### ")
        {
            if haveEntry and entry.current
            {
                entry.nextAction   = entry.nextAction or Utf8.startsWith(cast(const [..] u8) line, "- Next:")
                entry.completeWhen = entry.completeWhen or Utf8.startsWith(cast(const [..] u8) line, "- Complete when:")
            }

            continue
        }

        if haveEntry and entry.current do
            errors += reportBacklogFields(fileName, &entry)

        if @countof(line) < 7 or (line[4] != 'B' and line[4] != 'F' and line[4] != 'T') or line[5] != '-'
        {
            Console.println("error: ", fileName, ":", lineNumber, ": backlog entry heading has no permanent identifier")
            errors    += 1
            haveEntry = false
            continue
        }

        let parsed = parseDecimal(line, 6)
        if parsed.end == 6 or !Utf8.startsWith(cast(const [..] u8) line[parsed.end until @countof(line)], " — ")
        {
            Console.println("error: ", fileName, ":", lineNumber, ": malformed backlog identifier heading")
            errors    += 1
            haveEntry = false
            continue
        }

        if (line[4] == 'F' and parsed.value >= 203) or (line[4] == 'T' and parsed.value >= 572)
        {
            Console.println("error: ", fileName, ":", lineNumber, ": new backlog entries must use the B identifier family")
            errors    += 1
            haveEntry = false
            continue
        }

        let key = String.from(line[4 until parsed.end])
        if seen.contains(key)
        {
            Console.println("error: ", fileName, ":", lineNumber, ": duplicate backlog identifier ", key)
            errors += 1
        }
        else do
            seen.add(key)

        if line[4] == 'B' do
            maxBacklog[] = Math.max(maxBacklog[], parsed.value)

        entry     = BacklogEntry{heading: key, line: lineNumber, current: line[4] == 'B'}
        haveEntry = true
    }

    if haveEntry and entry.current do
        errors += reportBacklogFields(fileName, &entry)
    return errors
}

private func readCounter(readme: string)->u32
{
    let prefix = "Next identifier: B-"

    let start = Utf8.indexOf(cast(const [..] u8) readme, prefix)
    if start == Swag.U64.Max do
        return 0
    return parseDecimal(readme, start + @countof(prefix)).value
}

private func markdownHeadingAnchor(line: string)->String
{
    var result: retval
    var start:  u64
    while start < @countof(line) and start < 6 and line[start] == '#' do
        start += 1
    if start == 0 or start >= @countof(line) or line[start] != ' ' do
        return result

    start += 1
    Utf8.visitRunes(cast(const [..] u8) line[start until @countof(line)]) #code(c, charIndex, byteIndex)
    {
        discard charIndex
        discard byteIndex
        if Unicode.isLetterOrDigit(c) do
            result += Unicode.toLower(c)
        elif c == '-' or c == '_' do
            result += c
        elif c == ' ' do
            result += '-'
    }

    return result
}

private func hasMarkdownHeading(fileName: string, anchor: string)->bool fail
{
    let content = try File.readAllText(fileName)
    for line in Tokenize.splitLines(content.toString())
    {
        if markdownHeadingAnchor(line) == anchor do
            return true
    }

    return false
}

private func auditBacklogLink(fileName: string, lineNumber: u64, destination: string)->u32 fail
{
    if Utf8.startsWith(cast(const [..] u8) destination, "https://") or Utf8.startsWith(cast(const [..] u8) destination, "http://") or Utf8.startsWith(cast(const [..] u8) destination, "mailto:") do
        return 0

    let hash = Utf8.indexOf(cast(const [..] u8) destination, "#")
    let path = hash == Swag.U64.Max ? destination : destination[0 until hash]

    var target = @countof(path) == 0 ? String.from(fileName) : Path.combine(Path.directoryName(fileName) orelse "", path)
    Path.normalize(&target)
    if !File.exists(target.toString()) and !Directory.exists(target.toString())
    {
        Console.println("error: ", fileName, ":", lineNumber, ": backlog link target '", destination, "' is missing")
        return 1
    }

    if hash == Swag.U64.Max do
        return 0

    var anchor = String.from(destination[hash + 1 until @countof(destination)])
    anchor = anchor.toLower()
    let sourceLineAnchor = @countof(anchor.toString()) > 1 and anchor[0] == 'l' and Latin1.isDigit(anchor[1])
    if anchor.isEmpty() or sourceLineAnchor or (Path.extension(target.toString()) orelse "") != ".md" do
        return 0
    if try hasMarkdownHeading(target.toString(), anchor.toString()) do
        return 0

    Console.println("error: ", fileName, ":", lineNumber, ": backlog link fragment '", anchor.toString(), "' has no matching heading in '", path, "'")
    return 1
}

// Reports whether the byte at `index` sits inside an inline code span of `line`.
//
// A backlog entry quotes Markdown syntax in backticks — `![alt](url)` — and quoted syntax is
// prose being discussed, not a link whose target must exist.
private func isInsideCodeSpan(line: string, index: u64)->bool
{
    var ticks = 0'u64
    for i in index where line[i] == '`' do
        ticks += 1
    return (ticks & 1) == 1
}

private func auditBacklogLinks(fileName: string)->u32 fail
{
    let content    = try File.readAllText(fileName)
    var errors: u32
    var lineNumber = 0'u64

    for line in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        var offset = 0'u64
        while offset < @countof(line)
        {
            let marker = Utf8.indexOf(cast(const [..] u8) line[offset until @countof(line)], "](")
            if marker == Swag.U64.Max do
                break

            let start = offset + marker + 2
            if isInsideCodeSpan(line, offset + marker)
            {
                offset = start
                continue
            }

            let close = Utf8.indexOf(cast(const [..] u8) line[start until @countof(line)], ")")
            if close == Swag.U64.Max do
                break

            let end = start + close
            errors += try auditBacklogLink(fileName, lineNumber, line[start until end])
            offset = end + 1
        }
    }

    return errors
}

// Checks the permanent backlog contract before every repository test campaign.
public func auditBacklog(context: *Context)->s32 fail
{
    let backlogDir = Path.combine(context.root.toString(), "backlog")
    let readmeFile = Path.combine(backlogDir.toString(), "README.md")
    let readme     = try File.readAllText(readmeFile.toString())

    var seen:       HashSet'String
    var maxBacklog: u32
    var errors:     u32

    let files = try Directory.enumerateFiles(backlogDir.toString(), ".md")
    for file in files
    {
        let name = Path.fileName(file.fullname.toString()) orelse ""
        errors += try auditBacklogLinks(file.fullname.toString())

        if name == "README.md" or name == "prompts.md" do
            continue

        if Utf8.indexOf(cast(const [..] u8) readme.toString(), name) == Swag.U64.Max
        {
            Console.println("error: backlog/README.md does not document ", name)
            errors += 1
        }

        errors += try auditBacklogFile(file.fullname.toString(), &seen, &maxBacklog)
    }

    let nextBacklog = readCounter(readme.toString())
    if nextBacklog <= maxBacklog
    {
        Console.println("error: the next backlog identifier must be greater than B-", maxBacklog)
        errors += 1
    }

    if errors != 0
    {
        Console.println("error: backlog validation found ", errors, errors == 1 ? " problem" : " problems")
        return 1
    }

    return 0
}

#global namespace Tool

using Core

private func parseDecimal(text: string, start: u64)->{value: u32, end: u64}
{
    var value: u32
    var pos = start
    while pos < text.count and Latin1.isDigit(text[pos])
    {
        value = value * 10 + cast(u32) (text[pos] - '0')
        pos   += 1
    }

    return {value, pos}
}

private func auditBacklogFile(fileName: string, seen: *HashSet'String)->u32 fail
{
    let content = try File.readAllText(fileName)
    let stem    = Path.fileNameWithoutExtension(fileName) orelse ""

    var headingPrefix = String.from("### ")
    headingPrefix += stem
    headingPrefix += "."

    var errors: u32
    var lineNumber = 0'u64

    for line in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        if !Utf8.startsWith(cast(const [..] u8) line, "### ") do
            continue

        if !Utf8.startsWith(cast(const [..] u8) line, headingPrefix.toString())
        {
            Console.println("error: ", fileName, ":", lineNumber, ": backlog entry identifier does not match its file name")
            errors += 1
            continue
        }

        let digitStart = headingPrefix.count
        let parsed     = parseDecimal(line, digitStart)
        if parsed.value == 0 or parsed.end != digitStart + 3 or !Utf8.startsWith(cast(const [..] u8) line[parsed.end until line.count], " — ")
        {
            Console.println("error: ", fileName, ":", lineNumber, ": malformed backlog identifier heading")
            errors += 1
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
    }

    return errors
}

private func markdownHeadingAnchor(line: string)->String
{
    var result: retval
    var start:  u64
    while start < line.count and start < 6 and line[start] == '#' do
        start += 1
    if start == 0 or start >= line.count or line[start] != ' ' do
        return result

    start += 1
    Utf8.visitRunes(cast(const [..] u8) line[start until line.count]) #code(c, charIndex, byteIndex)
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

    var target = path.count == 0 ? String.from(fileName) : Path.combine(Path.directoryName(fileName) orelse "", path)
    Path.normalize(&target)
    if !File.exists(target.toString()) and !Directory.exists(target.toString())
    {
        Console.println("error: ", fileName, ":", lineNumber, ": backlog link target '", destination, "' is missing")
        return 1
    }

    if hash == Swag.U64.Max do
        return 0

    var anchor = String.from(destination[hash + 1 until destination.count])
    anchor = anchor.toLower()
    let sourceLineAnchor = (anchor.toString()).count > 1 and anchor[0] == 'l' and Latin1.isDigit(anchor[1])
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
        while offset < line.count
        {
            let marker = Utf8.indexOf(cast(const [..] u8) line[offset until line.count], "](")
            if marker == Swag.U64.Max do
                break

            let start = offset + marker + 2
            if isInsideCodeSpan(line, offset + marker)
            {
                offset = start
                continue
            }

            let close = Utf8.indexOf(cast(const [..] u8) line[start until line.count], ")")
            if close == Swag.U64.Max do
                break

            let end = start + close
            errors += try auditBacklogLink(fileName, lineNumber, line[start until end])
            offset = end + 1
        }
    }

    return errors
}

private func isBacklogScope(text: string)->bool
{
    if text.count == 0 do
        return false

    var segments = 1'u32
    var segmentStart: u64
    for i in text.count
    {
        if text[i] == '.'
        {
            if i == segmentStart do
                return false
            segments     += 1
            segmentStart = i + 1
        }
        elif !Latin1.isLower(text[i]) and !Latin1.isDigit(text[i]) do
            return false
    }

    return segments >= 2 and segmentStart != text.count
}

private func isBacklogIdentifier(text: string)->bool
{
    let suffixDot = Utf8.lastIndexOf(cast(const [..] u8) text, ".")
    if suffixDot == Swag.U64.Max or suffixDot + 4 != text.count or !isBacklogScope(text[0 until suffixDot]) do
        return false

    for i in suffixDot + 1 until text.count
    {
        if !Latin1.isDigit(text[i]) do
            return false
    }

    return true
}

// A Related field is a live dependency graph, not historical prose. Every identifier it names
// must therefore still exist after entries are removed, merged, or moved.
private func auditBacklogRelated(fileName: string, seen: *HashSet'String)->u32 fail
{
    let content = try File.readAllText(fileName)

    var errors:     u32
    var lineNumber: u64
    var related:    bool

    for line in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        let trimmed = Latin1.trim(line)
        if Utf8.startsWith(cast(const [..] u8) trimmed, "- Related:") do
            related = true
        elif related and line.count != 0 and (line[0] == ' ' or line[0] == '\t') do
            related = true
        else do
            related = false

        if !related do
            continue

        var start: u64
        while start < line.count
        {
            while start < line.count and !Latin1.isLower(line[start]) do
                start += 1
            if start == line.count do
                break

            var end = start + 1
            while end < line.count and (Latin1.isLower(line[end]) or Latin1.isDigit(line[end]) or line[end] == '.') do
                end += 1

            let candidate = line[start until end]
            if isBacklogIdentifier(candidate) and !seen.contains(candidate)
            {
                Console.println("error: ", fileName, ":", lineNumber, ": Related identifier '", candidate, "' is not live")
                errors += 1
            }

            start = end
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

    var seen:   HashSet'String
    var errors: u32

    let files = try Directory.enumerateFiles(backlogDir.toString(), ".md")
    for file in files
    {
        let name = Path.fileName(file.fullname.toString()) orelse ""
        errors += try auditBacklogLinks(file.fullname.toString())

        if name == "README.md" or name == "repo.prompts.md" do
            continue

        let stem = Path.fileNameWithoutExtension(name) orelse ""
        if !isBacklogScope(stem)
        {
            Console.println("error: backlog file name '", name, "' does not follow <scope>[.<subscope>...].md")
            errors += 1
        }

        if Utf8.indexOf(cast(const [..] u8) readme.toString(), name) == Swag.U64.Max
        {
            Console.println("error: backlog/README.md does not document ", name)
            errors += 1
        }

        errors += try auditBacklogFile(file.fullname.toString(), &seen)
    }

    for file in files
    {
        let name = Path.fileName(file.fullname.toString()) orelse ""
        if name == "README.md" or name == "repo.prompts.md" do
            continue
        errors += try auditBacklogRelated(file.fullname.toString(), &seen)
    }

    if errors != 0
    {
        Console.println("error: backlog validation found ", errors, errors == 1 ? " problem" : " problems")
        return 1
    }

    return 0
}

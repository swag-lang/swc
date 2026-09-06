#global namespace Tool

using Core

// Every entry opens with the moment it was found, and says when it last changed. Both stamps are
// local time on a 24-hour clock, so the newest work reads off the file without asking Git.
private const StampShape    = "0000-00-00 00:00"
private const RecordedField = "- Recorded: "
private const UpdatedField  = "- Updated: "
private const NoteSeparator = " — "

// What one domain file contributes to the audit: its error count and the latest stamp any of its
// entries carries, kept as text so a stale README row can be reported in the file's own words.
private struct FileAudit
{
    errors: u32
    latest: u64
    stamp:  String
}

// A domain file as the README inventory must list it.
private struct Domain
{
    name:   String
    latest: u64
    stamp:  String
}

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

// Parses `YYYY-MM-DD HH:MM` into a value that orders chronologically. Zero means malformed.
private func parseStamp(text: string)->u64
{
    if text.count != StampShape.count do
        return 0

    var value: u64
    for i in text.count
    {
        if StampShape[i] == '0'
        {
            if !Latin1.isDigit(text[i]) do
                return 0
            value = value * 10 + cast(u64) (text[i] - '0')
        }
        elif text[i] != StampShape[i] do
            return 0
    }

    let minute = value % 100
    let hour   = (value / 100) % 100
    let day    = (value / 10000) % 100
    let month  = (value / 1000000) % 100
    if month == 0 or month > 12 or day == 0 or day > 31 or hour > 23 or minute > 59 do
        return 0
    return value
}

// An entry is placed by its latest stamp: nothing above it may be older.
private func auditEntryOrder(fileName: string, entryLine: u64, latest: u64, previous: *u64)->u32
{
    if entryLine == 0 or latest == 0 do
        return 0

    var errors: u32
    if latest > previous[]
    {
        Console.println("error: ", fileName, ":", entryLine, ": backlog entry is more recent than the one above it; entries go from the most recently updated down")
        errors = 1
    }

    previous[] = latest
    return errors
}

private func auditBacklogFile(fileName: string, seen: *HashSet'String)->FileAudit fail
{
    let content = try File.readAllText(fileName)
    let stem    = Path.fileNameWithoutExtension(fileName) orelse ""

    var headingPrefix = String.from("### ")
    headingPrefix += stem
    headingPrefix += "."

    var result:        retval
    var lineNumber     = 0'u64
    var entryCount     = 0'u64
    var entryLine:     u64                // The heading line of the current entry.
    var entryLatest:   u64                // The latest stamp of the current entry, zero until one is read.
    var previousLatest = Swag.U64.Max     // The latest stamp of the entry above; the list descends.
    var sectionLine:   u64                // A `##` heading met after an entry; no entry may follow it.
    var recorded:      u64                // The Recorded stamp of the current entry, zero until it is read.
    var awaitRecorded: bool               // The next non-blank line must be the entry's Recorded stamp.
    var allowUpdated:  bool               // The next line may be the entry's Updated stamp.

    for line in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        let trimmed = Latin1.trim(line)

        if Utf8.startsWith(cast(const [..] u8) line, "## ")
        {
            if entryCount != 0 do
                sectionLine = lineNumber
            continue
        }

        if Utf8.startsWith(cast(const [..] u8) line, "### ")
        {
            result.errors += auditEntryOrder(fileName, entryLine, entryLatest, &previousLatest)
            if sectionLine != 0
            {
                Console.println("error: ", fileName, ":", sectionLine, ": entries are grouped under a '##' heading; a domain file is one list from the most recently updated entry down")
                result.errors += 1
                sectionLine   = 0
            }

            entryLine     = lineNumber
            entryLatest   = 0
            awaitRecorded = true
            allowUpdated  = false
            recorded      = 0

            if !Utf8.startsWith(cast(const [..] u8) line, headingPrefix.toString())
            {
                Console.println("error: ", fileName, ":", lineNumber, ": backlog entry identifier does not match its file name")
                result.errors += 1
                continue
            }

            let digitStart = headingPrefix.count
            let parsed     = parseDecimal(line, digitStart)
            if parsed.value == 0 or parsed.end != digitStart + 3 or !Utf8.startsWith(cast(const [..] u8) line[parsed.end until line.count], " — ")
            {
                Console.println("error: ", fileName, ":", lineNumber, ": malformed backlog identifier heading")
                result.errors += 1
                continue
            }

            let key = String.from(line[4 until parsed.end])
            entryCount += 1
            if seen.contains(key)
            {
                Console.println("error: ", fileName, ":", lineNumber, ": duplicate backlog identifier ", key)
                result.errors += 1
            }
            else do
                seen.add(key)
            continue
        }

        if awaitRecorded
        {
            if trimmed.count == 0 do
                continue

            awaitRecorded = false
            if !Utf8.startsWith(cast(const [..] u8) trimmed, RecordedField)
            {
                Console.println("error: ", fileName, ":", lineNumber, ": backlog entry does not open with '", RecordedField, "YYYY-MM-DD HH:MM'")
                result.errors += 1
                continue
            }

            let stamp = trimmed[RecordedField.count until trimmed.count]
            recorded = parseStamp(stamp)
            if recorded == 0
            {
                Console.println("error: ", fileName, ":", lineNumber, ": malformed Recorded stamp, expected 'YYYY-MM-DD HH:MM'")
                result.errors += 1
                continue
            }

            entryLatest = recorded
            if recorded > result.latest
            {
                result.latest = recorded
                result.stamp  = String.from(stamp)
            }

            allowUpdated = true
            continue
        }

        let updatedAllowed = allowUpdated
        allowUpdated = false
        if Utf8.startsWith(cast(const [..] u8) trimmed, UpdatedField)
        {
            if !updatedAllowed
            {
                Console.println("error: ", fileName, ":", lineNumber, ": an Updated stamp must directly follow the entry's Recorded stamp")
                result.errors += 1
                continue
            }

            let rest    = trimmed[UpdatedField.count until trimmed.count]
            let stamp   = rest.count < StampShape.count ? "" : rest[0 until StampShape.count]
            let updated = parseStamp(stamp)
            if updated == 0
            {
                Console.println("error: ", fileName, ":", lineNumber, ": malformed Updated stamp, expected 'YYYY-MM-DD HH:MM — what changed'")
                result.errors += 1
                continue
            }

            let note = rest[stamp.count until rest.count]
            if !Utf8.startsWith(cast(const [..] u8) note, NoteSeparator) or Latin1.trim(note[NoteSeparator.count until note.count]).count == 0
            {
                Console.println("error: ", fileName, ":", lineNumber, ": an Updated stamp must say what changed after ' — '")
                result.errors += 1
                continue
            }

            if updated < recorded
            {
                Console.println("error: ", fileName, ":", lineNumber, ": Updated stamp is earlier than the entry's Recorded stamp")
                result.errors += 1
                continue
            }

            entryLatest = updated
            if updated > result.latest
            {
                result.latest = updated
                result.stamp  = String.from(stamp)
            }
        }
        elif Utf8.startsWith(cast(const [..] u8) trimmed, RecordedField)
        {
            Console.println("error: ", fileName, ":", lineNumber, ": a Recorded stamp must directly follow the entry heading")
            result.errors += 1
        }
    }

    result.errors += auditEntryOrder(fileName, entryLine, entryLatest, &previousLatest)

    if entryCount == 0 and result.errors == 0
    {
        Console.println("error: ", fileName, ": backlog domain has no entries")
        result.errors += 1
    }

    return result
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
        if Utf8.startsWith(cast(const [..] u8) trimmed, "- Related:") or
           Utf8.startsWith(cast(const [..] u8) trimmed, "Related:") or
           Utf8.startsWith(cast(const [..] u8) trimmed, "**Related:**") or
           Utf8.startsWith(cast(const [..] u8) trimmed, "- **Related:**") do
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

            var candidateEnd = end
            while candidateEnd > start and line[candidateEnd - 1] == '.' do
                candidateEnd -= 1
            let candidate = line[start until candidateEnd]
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

// The README inventory is ordered from the most recently updated domain down, and each row's
// stamp is the latest one its file holds, so the table answers "what moved last?" by itself.
private func auditBacklogIndex(fileName: string, readme: string, domains: const [..] Domain)->u32
{
    var errors:     u32
    var lineNumber: u64
    var previous = Swag.U64.Max
    var listed:     HashSet'String

    for line in Tokenize.splitLines(readme)
    {
        lineNumber += 1
        let trimmed = Latin1.trim(line)
        if !Utf8.startsWith(cast(const [..] u8) trimmed, "| [") do
            continue

        let open  = Utf8.indexOf(cast(const [..] u8) trimmed, "](")
        let close = open == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(cast(const [..] u8) trimmed, ")", open)
        if close == Swag.U64.Max or trimmed[trimmed.count - 1] != '|'
        {
            Console.println("error: ", fileName, ":", lineNumber, ": malformed inventory row")
            errors += 1
            continue
        }

        let name  = trimmed[open + 2 until close]
        let body  = trimmed[0 until trimmed.count - 1]
        let cell  = Utf8.lastIndexOf(cast(const [..] u8) body, "|")
        let text  = Latin1.trim(body[cell + 1 until body.count])
        let stamp = parseStamp(text)
        if stamp == 0
        {
            Console.println("error: ", fileName, ":", lineNumber, ": inventory row for '", name, "' has no 'YYYY-MM-DD HH:MM' stamp in its last column")
            errors += 1
            continue
        }

        if stamp > previous
        {
            Console.println("error: ", fileName, ":", lineNumber, ": inventory row for '", name, "' is out of order; rows go from the most recently updated file down")
            errors += 1
        }

        previous = stamp
        listed.add(String.from(name))

        for domain in domains where domain.name.toString() == name and domain.latest != 0 and domain.latest != stamp
        {
            Console.println("error: ", fileName, ":", lineNumber, ": inventory row for '", name, "' says ", text, " but the latest stamp in that file is ", domain.stamp.toString())
            errors += 1
        }
    }

    for domain in domains where !listed.contains(domain.name.toString())
    {
        Console.println("error: ", fileName, ": inventory has no row for ", domain.name.toString())
        errors += 1
    }

    return errors
}

// Checks the permanent backlog contract before every repository test campaign.
public func auditBacklog(context: *Context)->s32 fail
{
    let backlogDir = Path.combine(context.root.toString(), "backlog")
    let readmeFile = Path.combine(backlogDir.toString(), "README.md")
    let readme     = try File.readAllText(readmeFile.toString())

    var seen:    HashSet'String
    var domains: Array'Domain
    var errors:  u32

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

        let audit = try auditBacklogFile(file.fullname.toString(), &seen)
        errors += audit.errors

        with var domain: Domain
        {
            .name   = String.from(name)
            .latest = audit.latest
            .stamp  = audit.stamp
        }

        domains.add(domain)
    }

    for file in files
    {
        let name = Path.fileName(file.fullname.toString()) orelse ""
        if name == "README.md" or name == "repo.prompts.md" do
            continue
        errors += try auditBacklogRelated(file.fullname.toString(), &seen)
    }

    errors += auditBacklogIndex(readmeFile.toString(), readme.toString(), domains.toSlice())

    if errors != 0
    {
        Console.println("error: backlog validation found ", errors, errors == 1 ? " problem" : " problems")
        return 1
    }

    return 0
}

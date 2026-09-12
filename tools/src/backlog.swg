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
            if not Latin1.isDigit(text[i]) do
                return 0
            value = value * 10 + cast(u64) (text[i] - '0')
        }
        elif text[i] != StampShape[i] do
            return 0
    }

    let date = Time.DateTime{
        year: cast() (value / 100000000),
        month: cast() ((value / 1000000) % 100),
        day: cast() ((value / 10000) % 100),
        hour: cast() ((value / 100) % 100),
        minute: cast() (value % 100)}
    return date.isValid() ? value : 0
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
            if awaitRecorded
            {
                Console.println("error: ", fileName, ":", entryLine, ": backlog entry does not open with '", RecordedField, "YYYY-MM-DD HH:MM'")
                result.errors += 1
            }

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

            if not Utf8.startsWith(cast(const [..] u8) line, headingPrefix.toString())
            {
                Console.println("error: ", fileName, ":", lineNumber, ": backlog entry identifier does not match its file name")
                result.errors += 1
                continue
            }

            let digitStart = headingPrefix.count
            let parsed     = parseDecimal(line, digitStart)
            if parsed.value == 0 or parsed.end != digitStart + 3 or not Utf8.startsWith(cast(const [..] u8) line[parsed.end until line.count], " — ")
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
            if not Utf8.startsWith(cast(const [..] u8) trimmed, RecordedField)
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
            if not updatedAllowed
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
            if not Utf8.startsWith(cast(const [..] u8) note, NoteSeparator) or Latin1.trim(note[NoteSeparator.count until note.count]).count == 0
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

    if awaitRecorded
    {
        Console.println("error: ", fileName, ":", entryLine, ": backlog entry does not open with '", RecordedField, "YYYY-MM-DD HH:MM'")
        result.errors += 1
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
    if not File.exists(target.toString()) and not Directory.exists(target.toString())
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
        elif not Latin1.isLower(text[i]) and not Latin1.isDigit(text[i]) do
            return false
    }

    return segments >= 2 and segmentStart != text.count
}

private func isBacklogIdentifier(text: string)->bool
{
    let suffixDot = Utf8.lastIndexOf(cast(const [..] u8) text, ".")
    if suffixDot == Swag.U64.Max or suffixDot + 4 != text.count or not isBacklogScope(text[0 until suffixDot]) do
        return false

    for i in suffixDot + 1 until text.count
    {
        if not Latin1.isDigit(text[i]) do
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

        if not related do
            continue

        var start: u64
        while start < line.count
        {
            while start < line.count and not Latin1.isLower(line[start]) do
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
            if isBacklogIdentifier(candidate) and not seen.contains(candidate)
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
        if not Utf8.startsWith(cast(const [..] u8) trimmed, "| [") do
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
        if listed.contains(name)
        {
            Console.println("error: ", fileName, ":", lineNumber, ": duplicate inventory row for '", name, "'")
            errors += 1
        }

        listed.add(String.from(name))

        for domain in domains where domain.name.toString() == name and domain.latest != 0 and domain.latest != stamp
        {
            Console.println("error: ", fileName, ":", lineNumber, ": inventory row for '", name, "' says ", text, " but the latest stamp in that file is ", domain.stamp.toString())
            errors += 1
        }
    }

    for domain in domains where not listed.contains(domain.name.toString())
    {
        Console.println("error: ", fileName, ": inventory has no row for ", domain.name.toString())
        errors += 1
    }

    return errors
}

// Checks the permanent backlog contract before every repository test campaign.
private func collectHeadingIdentifiers(text: string, prefix: string, result: *HashSet'String)
{
    for line in Tokenize.splitLines(text)
    {
        if not Utf8.startsWith(cast(const [..] u8) line, prefix) do
            continue
        let heading = line[prefix.count to]
        let end     = Utf8.indexOf(cast(const [..] u8) heading, " ")
        if end != Swag.U64.Max and isBacklogIdentifier(heading[0 until end]) do
            result.add(String.from(heading[0 until end]))
    }
}

private func captureBacklogGit(context: *Context, arguments: Arguments, allowNoMatches = false)->String fail
{
    var command: Arguments
    command.add(["-C", context.root.toString()])
    command.addAll(arguments)
    let commandLine = joinArguments(command.toSlice())
    let process     = try Env.runProcess("git", commandLine.toString())
    if process.exitCode() != 0 and not (allowNoMatches and process.exitCode() == 1)
    {
        Console.print(process.standardOutput())
        Console.print(process.standardError())
        fail Swag.SystemError{"cannot read backlog allocation history", errorID: cast(u32) process.exitCode()}
    }

    return String.from(process.standardOutput())
}

// A renamed file keeps its old suffixes. Git's followed file history also includes retired
// identifiers from before committed renames, whose prefixes differ from the current domain.
private func collectDomainIdentifiers(text: string, headingPrefix: string, stem: string)->HashSet'String
{
    var identifiers: HashSet'String
    collectHeadingIdentifiers(text, headingPrefix, &identifiers)
    var result: HashSet'String
    for identifier in identifiers
    {
        let value = identifier.toString()
        result.add(Format.toString("%.%", stem, value[value.count - 3 to]))
    }

    return result
}

private func auditDomainAllocations(context: *Context, seen: *HashSet'String, domain: Domain, renames: string)->u32 fail
{
    let stem        = Path.fileNameWithoutExtension(domain.name.toString())!
    var historyPath = Format.toString("backlog/%", domain.name.toString())
    for line in Tokenize.splitLines(renames)
    {
        let fields = Tokenize.split(line, "\t")
        if fields.count == 3 and fields[0][0] == 'R' and fields[2] == historyPath.toString() do
            historyPath = String.from(fields[1])
    }

    var headCommand: Arguments
    headCommand.add(["grep", "-h", "--no-color", "-e", "^### ", "HEAD", "--", historyPath.toString()])
    let head     = try captureBacklogGit(context, headCommand, true)
    let previous = collectDomainIdentifiers(head.toString(), "### ", stem)

    var added: Array'String
    let prefix = Format.toString("%.", stem)
    for identifier in seen[] where identifier.count == prefix.count + 3 and Utf8.startsWith(cast(const [..] u8) identifier.toString(), prefix.toString())
    {
        if not previous.contains(identifier) do
            added.add(identifier)
    }

    if added.count == 0 do
        return 0
    added.sort()

    var historyCommand: Arguments
    historyCommand.add(["log", "--follow", "--find-renames=40%", "--format=", "--no-ext-diff", "--no-textconv", "-p", "--", historyPath.toString()])
    let history   = try captureBacklogGit(context, historyCommand)
    var allocated = collectDomainIdentifiers(history.toString(), "+### ", stem)
    // Default Git logs omit merge patches. A live heading, or a later removal, still proves
    // that a merge-resolution-only identifier was allocated.
    let retired = collectDomainIdentifiers(history.toString(), "-### ", stem)
    for identifier in previous do
        allocated.add(identifier)
    for identifier in retired do
        allocated.add(identifier)

    var errors: u32
    for identifier in added
    {
        let text = identifier.toString()
        var maximum: u32
        for old in allocated do
            maximum = Math.max(maximum, parseDecimal(old.toString(), prefix.count).value)
        let suffix = parseDecimal(text, prefix.count).value
        if suffix != maximum + 1
        {
            Console.println("error: backlog identifier '", text, "' must use suffix ", maximum + 1, "; retired suffixes stay allocated")
            errors += 1
        }
        else do
            allocated.add(identifier)
    }

    return errors
}

// Compare new working-tree entries with every suffix allocated on the checked-out branch.
// Removed entries still reserve their suffix. Source archives have no Git history to consult.
private func auditBacklogAllocations(context: *Context, seen: *HashSet'String, domains: const [..] Domain)->u32 fail
{
    let gitPath = Path.combine(context.root.toString(), ".git")
    if not File.exists(gitPath.toString()) and not Directory.exists(gitPath.toString()) do
        return 0
    var renameCommand: Arguments

    // A minimal entry retains its stamp while its entire heading changes with the prefix;
    // that puts a valid rename just below Git's default 50% similarity threshold.
    renameCommand.add(["diff", "--name-status", "--find-renames=40%", "HEAD", "--", "backlog"])
    let renames = try captureBacklogGit(context, renameCommand)
    var errors: u32
    for domain in domains do
        errors += try auditDomainAllocations(context, seen, domain, renames.toString())
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
        if not isBacklogScope(stem)
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
    if errors == 0 do
        errors += try auditBacklogAllocations(context, &seen, domains.toSlice())

    if errors != 0
    {
        Console.println("error: backlog validation found ", errors, errors == 1 ? " problem" : " problems")
        return 1
    }

    return 0
}

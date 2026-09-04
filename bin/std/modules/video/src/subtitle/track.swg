#global public
#global namespace Subtitle

using Core, Core.Errors

// Text subtitle syntax decoded into timed cues.
enum Format
{
    SubRip              // SubRip `.srt` timestamps and cue blocks.
    WebVtt              // WebVTT `.vtt` cues and inline markup.
    SubStationAlpha     // SubStation Alpha `.ssa` and Advanced SubStation Alpha `.ass` events.
    Lyric               // LRC timestamped lyric lines.
    MicroDvd            // MicroDVD `.sub` frame ranges.
    MatroskaText        // Text carried by a Matroska subtitle track.
}

// One subtitle cue on the media timeline.
struct Cue
{
    public readonly
    {
        startSeconds: f64     // Inclusive presentation time in seconds.
        endSeconds:   f64     // Exclusive presentation time in seconds.
    }

    textOffset: u64
    textLength: u64
}

impl Cue
{
    // Returns the inclusive cue start.
    mtd const startTime()->f64 => .startSeconds

    // Returns the exclusive cue end.
    mtd const endTime()->f64 => .endSeconds
}

// Text and next transition visible at one media position.
struct Presentation
{
    public readonly
    {
        text:              String     // Active cues joined in timeline order.
        nextChangeSeconds: f64        // Next cue start or end, or positive infinity past the last cue.
    }
}

impl Presentation
{
    // Borrows the active cue text.
    #[Swag.NoInline]
    mtd const content()->string => .text.toString()

    // Returns the next cue start or end, or positive infinity after the track.
    mtd const nextChange()->f64 => .nextChangeSeconds
}

// Owns one ordered subtitle track.
//
// A track stores plain UTF-8 cue text. Container or file styling is deliberately reduced to text;
// presentation belongs to the player and can therefore be changed without decoding again.
struct Track
{
    public readonly
    {
        name:     String        // Display name supplied by the file or container.
        language: String        // BCP 47 or container language tag, or empty when unspecified.
        format:   Format        // Syntax from which the cues were decoded.
        cues:     Array'Cue     // Cues ordered by start time, then end time.
    }

    internal
    {
        textStorage:         String
        allocationAllocator: IAllocator?
    }
}

private func timestampNumber(text: string)->f64 fail
{
    let trimmed = Latin1.trim(text)
    if !trimmed.count do
        fail InvalidFormatError{"subtitle timestamp has an empty component"}
    return try StrConv.toF64(trimmed)
}

// Reads `h:mm:ss.mmm`, `mm:ss.mmm`, and the comma-decimal forms used by SubRip.
private func parseTimestamp(text: string)->f64 fail
{
    var normalized = String.from(Latin1.trim(text))
    normalized.replace(','rune, ".")
    let parts = Tokenize.split(normalized.toString(), ':'u8)
    if parts.count < 2 or parts.count > 3 do
        fail InvalidFormatError{"subtitle timestamp needs minutes, seconds, and an optional hour"}

    let seconds = try timestampNumber(parts[parts.count - 1])
    let minutes = try timestampNumber(parts[parts.count - 2])
    let hours   = parts.count == 3 ? try timestampNumber(parts[0]) : 0
    if hours < 0 or minutes < 0 or minutes >= 60 or seconds < 0 or seconds >= 60 do
        fail InvalidFormatError{"subtitle timestamp component is outside its accepted range"}
    return hours * 3_600 + minutes * 60 + seconds
}

private func stripSubtitleMarkup(result: *String, text: string)
{
    result.clear()
    var insideTag, insideOverride: bool
    var index = 0'u64
    while index < text.count
    {
        if text[index] == '<'
        {
            insideTag = true
            index     += 1
            continue
        }

        if insideTag
        {
            if text[index] == '>' do
                insideTag = false
            index += 1
            continue
        }

        if text[index] == '{'
        {
            insideOverride = true
            index          += 1
            continue
        }

        if insideOverride
        {
            if text[index] == '}' do
                insideOverride = false
            index += 1
            continue
        }

        if text[index] == '\\' and index + 1 < text.count
        {
            let escaped = text[index + 1]
            if escaped == 'N' or escaped == 'n'
            {
                result.append('\n'rune)
                index += 2
                continue
            }

            if escaped == 'h'
            {
                result.append(' 'rune)
                index += 2
                continue
            }
        }

        let {c, eat} = Utf8.decodeRune(text[index to])
        if !eat do
            break
        result.append(c)
        index += eat
    }

    result.replace("&nbsp;", " ")
    result.replace("&amp;", "&")
    result.replace("&lt;", "<")
    result.replace("&gt;", ">")
    result.trim()
}

private func subtitleExtension(fileName: string)->String
{
    var result = String.from(Path.extension(fileName) orelse "")
    return result.toLower()
}

private func inferFormat(fileName, source: string)->Format fail
{
    let extension = subtitleExtension(fileName)
    switch extension.toString()
    {
    case ".srt":         return .SubRip
    case ".vtt":         return .WebVtt
    case ".ass", ".ssa": return .SubStationAlpha
    case ".lrc":         return .Lyric
    case ".sub":         return .MicroDvd
    }

    let head = Latin1.trim(source)
    if Utf8.startsWith(head, "WEBVTT") do
        return .WebVtt
    if Utf8.startsWith(head, "[Script Info]") or Utf8.indexOf(head, "[Events]", 0, .Latin1NoCase) != Swag.U64.Max do
        return .SubStationAlpha
    if head.count and head[0] == '[' do
        return .Lyric
    if head.count and head[0] == '{' do
        return .MicroDvd
    if Utf8.indexOf(head, "-->") != Swag.U64.Max do
        return .SubRip
    fail UnsupportedFormatError{"subtitle decoder does not recognize this text format"}
}

private func cueTimeLine(line: string)->{startSeconds, endSeconds: f64} fail
{
    let arrow = Utf8.indexOf(line, "-->")
    if arrow == Swag.U64.Max do
        fail InvalidFormatError{"subtitle cue has no timestamp arrow"}
    let start = try parseTimestamp(line[0 until arrow])
    let rest  = Latin1.trim(line[arrow + 3 to])
    var endAt = 0'u64
    while endAt < rest.count and !Latin1.isSpace(rest[endAt]) do
        endAt += 1
    let end = try parseTimestamp(rest[0 until endAt])
    if end <= start do
        fail InvalidFormatError{"subtitle cue end does not follow its start"}
    return {start, end}
}

private func joinCueLines(result: *String, lines: const [..] string, first, last: u64)
{
    result.clear()
    var joined: String
    for index in first until last
    {
        if joined.length do
            joined.append('\n'rune)
        joined += lines[index]
    }

    stripSubtitleMarkup(result, joined.toString())
}

private func decodeSubRip(track: *Track, source: string) fail
{
    let lines = Tokenize.splitLines(source)
    var index = 0'u64
    while index < lines.count
    {
        while index < lines.count and !(Latin1.trim(lines[index])).count do
            index += 1
        if index >= lines.count do
            break

        if Utf8.indexOf(lines[index], "-->") == Swag.U64.Max do
            index += 1
        if index >= lines.count do
            break
        let times = try cueTimeLine(lines[index])
        index += 1
        let first = index
        while index < lines.count and (Latin1.trim(lines[index])).count do
            index += 1
        var text: String
        joinCueLines(&text, lines.toSlice(), first, index)
        if text.length do
            track.addCue(times.startSeconds, times.endSeconds, text.toString())
    }
}

private func decodeWebVtt(track: *Track, source: string) fail
{
    let lines = Tokenize.splitLines(source)
    var index = 0'u64
    if lines.count and Utf8.startsWith(Latin1.trim(lines[0]), "WEBVTT") do
        index = 1
    while index < lines.count
    {
        while index < lines.count and !(Latin1.trim(lines[index])).count do
            index += 1
        if index >= lines.count do
            break
        if Utf8.startsWith(Latin1.trim(lines[index]), "NOTE")
        {
            while index < lines.count and (Latin1.trim(lines[index])).count do
                index += 1
            continue
        }

        if Utf8.indexOf(lines[index], "-->") == Swag.U64.Max do
            index += 1
        if index >= lines.count or Utf8.indexOf(lines[index], "-->") == Swag.U64.Max do
            continue
        let times = try cueTimeLine(lines[index])
        index += 1
        let first = index
        while index < lines.count and (Latin1.trim(lines[index])).count do
            index += 1
        var text: String
        joinCueLines(&text, lines.toSlice(), first, index)
        if text.length do
            track.addCue(times.startSeconds, times.endSeconds, text.toString())
    }
}

private func commaField(line: string, field: u32)->string
{
    var start   = 0'u64
    var current = 0'u32
    for index in line.count
    {
        if line[index] != ',' do
            continue
        if current == field do
            return line[start until index]
        current += 1
        start   = index + 1
    }

    return current == field ? line[start to] : ""
}

private func commaTail(line: string, field: u32)->string
{
    var current = 0'u32
    for index in line.count where line[index] == ','
    {
        if current == field do
            return line[index + 1 to]
        current += 1
    }

    return ""
}

private func decodeSubStationAlpha(track: *Track, source: string) fail
{
    let lines      = Tokenize.splitLines(source)
    var inEvents: bool
    var startField = 1'u32
    var endField   = 2'u32
    var textField  = 9'u32
    for raw in lines
    {
        let line = Latin1.trim(raw)
        if line.count and line[0] == '['
        {
            inEvents = Latin1.compare(line, "[Events]", ignoreCase: true) == 0
            continue
        }

        if !inEvents do
            continue
        if Utf8.startsWith(line, "Format:", .Latin1NoCase)
        {
            let fields = Tokenize.split(line[7 to], ','u8)
            for field, index in fields
            {
                let name = Latin1.trim(field)
                if Latin1.compare(name, "Start", ignoreCase: true) == 0 do
                    startField = cast(u32) index
                elif Latin1.compare(name, "End", ignoreCase: true) == 0 do
                    endField = cast(u32) index
                elif Latin1.compare(name, "Text", ignoreCase: true) == 0 do
                    textField = cast(u32) index
            }

            continue
        }

        if !Utf8.startsWith(line, "Dialogue:", .Latin1NoCase) do
            continue

        let event = Latin1.trim(line[9 to])
        let start = try parseTimestamp(commaField(event, startField))
        let end   = try parseTimestamp(commaField(event, endField))
        if end <= start do
            continue
        var text: String
        stripSubtitleMarkup(&text, commaTail(event, textField - 1))
        if text.length do
            track.addCue(start, end, text.toString())
    }
}

private func parseLrcTimestamp(text: string)->f64 fail
{
    return try parseTimestamp(text)
}

private func decodeLyric(track: *Track, source: string) fail
{
    let lines = Tokenize.splitLines(source)
    for raw in lines
    {
        var line = Latin1.trim(raw)
        var times: Array'f64
        while line.count and line[0] == '['
        {
            let close = Utf8.indexOf(line, "]")
            if close == Swag.U64.Max do
                break
            let stamp = line[1 until close]
            if Utf8.indexOf(stamp, ":") == Swag.U64.Max do
                break
            times.add(try parseLrcTimestamp(stamp))
            line = line[close + 1 to]
        }

        var text: String
        stripSubtitleMarkup(&text, Latin1.trim(line))
        for start in times where text.length do
            track.addCue(start, start + 5, text.toString())
    }

    track.sortCues()
    track.closeLyricCues()
}

private func decodeMicroDvd(track: *Track, source: string) fail
{
    var framesPerSecond = 25.0'f64
    let lines           = Tokenize.splitLines(source)
    for raw in lines
    {
        let line = Latin1.trim(raw)
        if line.count < 6 or line[0] != '{' do
            continue
        let firstClose = Utf8.indexOf(line, "}")
        if firstClose == Swag.U64.Max or firstClose + 1 >= line.count or line[firstClose + 1] != '{' do
            continue
        let secondClose = Utf8.indexOf(line, "}", firstClose + 2)
        if secondClose == Swag.U64.Max do
            continue
        let first = catch StrConv.toU64(line[1 until firstClose])
        let last  = catch StrConv.toU64(line[firstClose + 2 until secondClose])
        if firstClose == 2 and first == 1 and last == 1
        {
            let declared = catch StrConv.toF64(Latin1.trim(line[secondClose + 1 to]))
            if declared > 0 do
                framesPerSecond = declared
            continue
        }

        if last <= first do
            continue
        var text = String.from(line[secondClose + 1 to])
        text.replace('|'rune, "\n")
        var clean: String
        stripSubtitleMarkup(&clean, text.toString())
        if clean.length do
            track.addCue(cast(f64) first / framesPerSecond, cast(f64) last / framesPerSecond, clean.toString())
    }
}

impl Track
{
    // Borrows the container or file display name.
    #[Swag.NoInline]
    mtd const displayName()->string => .name.toString()

    // Borrows the BCP 47 or container language tag.
    #[Swag.NoInline]
    mtd const languageTag()->string => .language.toString()

    // Copies the display name into caller-owned storage.
    #[Swag.NoInline]
    mtd const copyDisplayName(result: *String)
    {
        result.clear()
        result[] += .name.toString()
    }

    // Copies the language tag into caller-owned storage.
    #[Swag.NoInline]
    mtd const copyLanguageTag(result: *String)
    {
        result.clear()
        result[] += .language.toString()
    }

    // Returns the decoded source syntax.
    #[Swag.NoInline]
    mtd const sourceFormat()->Format => .format

    // Returns the number of timed cues.
    #[Swag.NoInline]
    mtd const cueCount()->u64 => .cues.count

    // Borrows one cue, or returns null when `index` is outside the track.
    mtd const cue(index: u64)->const *Cue? => index < .cues.count ? &.cues[index] : null

    // Borrows one cue's text, or returns an empty view when `index` is outside the track.
    #[Swag.NoInline]
    mtd const cueContent(index: u64)->string
    {
        if index >= .cues.count do
            return ""
        let cue = .cues[index]
        return .textStorage.toString()[cue.textOffset until cue.textOffset + cue.textLength]
    }

    // Copies one cue's text into caller-owned storage.
    #[Swag.NoInline]
    mtd const copyCueContent(index: u64, result: *String)
    {
        result.clear()
        if index < .cues.count do
            result[] += .cueContent(index)
    }

    // Returns the inclusive start of one cue, or zero outside the track.
    #[Swag.NoInline]
    mtd const cueStartTime(index: u64)->f64 => index < .cues.count ? .cues[index].startSeconds : 0

    // Returns the exclusive end of one cue, or zero outside the track.
    #[Swag.NoInline]
    mtd const cueEndTime(index: u64)->f64 => index < .cues.count ? .cues[index].endSeconds : 0

    // Borrows the UTF-8 bytes for one cue. The pointer remains valid while the track is alive.
    #[Swag.NoInline]
    mtd const cueTextData(index: u64)->const [*] u8?
    {
        if index >= .cues.count do
            return null
        return cast(const [*] u8) .textStorage.buffer! + .cues[index].textOffset
    }

    // Returns the UTF-8 byte count for one cue, or zero outside the track.
    #[Swag.NoInline]
    mtd const cueTextLength(index: u64)->u64 => index < .cues.count ? .cues[index].textLength : 0

    // Borrows the display-name bytes. Use [[Video.Subtitle.Track.displayNameLength]] for the size.
    #[Swag.NoInline]
    mtd const displayNameData()->const [*] u8? => .name.buffer

    // Returns the display-name byte count.
    #[Swag.NoInline]
    mtd const displayNameLength()->u64 => .name.length

    // Borrows the language-tag bytes. Use [[Video.Subtitle.Track.languageTagLength]] for the size.
    #[Swag.NoInline]
    mtd const languageTagData()->const [*] u8? => .language.buffer

    // Returns the language-tag byte count.
    #[Swag.NoInline]
    mtd const languageTagLength()->u64 => .language.length

    // Returns the end of the last cue, or zero for an empty track.
    mtd const durationInSeconds()->f64 => .cues.count ? .cues[.cues.count - 1].endSeconds : 0

    private mtd closeLyricCues()
    {
        if .cues.count < 2 do
            return
        for index in .cues.count - 1 where .cues[index].endSeconds > .cues[index + 1].startSeconds
        {
            .cues[index].endSeconds = .cues[index + 1].startSeconds
        }
    }

    // Creates an empty track for a container decoder.
    func create(name: string = "", language: string = "", format = Format.MatroskaText)->Track
    {
        var result: retval
        result.name.reserve(17)
        result.name += name
        result.language.reserve(17)
        result.language += language
        result.textStorage.reserve(17)
        result.format = format
        return result
    }

    // Decodes a subtitle document held in UTF-8 text.
    //
    // `fileName` selects the syntax by extension, with a content fallback for unnamed input.
    func decode(fileName, source: string)->Track fail
    {
        var result: retval
        try Track.decodeInto(&result, fileName, source)
        return result
    }

    // Decodes into caller-owned storage, including across a shared-module boundary.
    func decodeInto(result: *Track, fileName, source: string) fail
    {
        result.name.clear()
        result.language.clear()
        result.cues.clear()
        result.textStorage.clear()
        result.textStorage.reserve(17)
        result.format = try inferFormat(fileName, source)
        switch result.format
        {
        case .SubRip:
            try decodeSubRip(result, source)

        case .WebVtt:
            try decodeWebVtt(result, source)

        case .SubStationAlpha:
            try decodeSubStationAlpha(result, source)

        case .Lyric:
            try decodeLyric(result, source)

        case .MicroDvd:
            try decodeMicroDvd(result, source)

        case .MatroskaText: {}
        }

        result.sortCues()
        if !result.cues.count do
            fail InvalidFormatError{"subtitle document has no timed cues"}
    }

    // Loads and decodes a subtitle file.
    //
    // UTF-8, UTF-16, UTF-32, and Windows-1252 are detected from the file bytes. The returned
    // track owns every cue and remains independent of the source file.
    func load(fileName: string)->Track fail
    {
        var result: retval
        try Track.loadInto(&result, fileName)
        return result
    }

    // Loads into caller-owned storage, avoiding an owning aggregate return at module boundaries.
    func loadInto(result: *Track, fileName: string) fail
    {
        let bytes    = try File.readAllBytes(fileName)
        let encoding = Text.detectEncoding(bytes.toSlice())
        let start    = Text.hasBom(bytes.toSlice(), encoding) ? Text.bomLength(encoding) : 0
        if !Text.looksLikeText(bytes.toSlice()[start to], encoding) do
            fail InvalidFormatError{"subtitle file does not contain readable text"}
        let source = Text.decode(bytes.toSlice()[start to], encoding)
        try Track.decodeInto(result, fileName, source.toString())
        result.name.clear()
        result.name.reserve(17)
        result.name += Path.fileNameWithoutExtension(fileName) orelse ""
    }

    // Loads a track whose lifetime remains owned by the video module.
    //
    // A successful call returns a non-null pointer. Call [[Video.Subtitle.Track.destroy]] when the
    // track is no longer needed.
    #[Swag.NoInline]
    func loadOwned(fileName: string)->*Track? fail
    {
        let allocator = (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)!
        let result    = Memory.new'Track(allocator)
        result.allocationAllocator   = allocator
        result.name.allocator        = allocator
        result.language.allocator    = allocator
        result.cues.allocator        = allocator
        result.textStorage.allocator = allocator
        defer #fail Memory.delete(result, allocator)
        try Track.loadInto(result, fileName)
        return result
    }

    // Releases a track returned by [[Video.Subtitle.Track.loadOwned]].
    #[Swag.NoInline]
    func destroy(track: *Track)
    {
        let allocator = track.allocationAllocator
        if allocator do
            Memory.delete(track, allocator!)
        else do
            Memory.delete(track)
    }

    // Appends one decoded cue.
    //
    // Empty text and non-positive ranges are ignored. Call [[Video.Subtitle.Track.sortCues]]
    // after appending container cues that are not already ordered.
    mtd addCue(startSeconds, endSeconds: f64, text: string)
    {
        if !text.count or startSeconds < 0 or endSeconds <= startSeconds do
            return
        let cue = .cues.emplaceInitAddress()
        cue.startSeconds = startSeconds
        cue.endSeconds   = endSeconds
        cue.textOffset   = .textStorage.length
        cue.textLength   = text.count
        .textStorage     += text
    }

    // Appends one UTF-8 cue payload supplied by a container.
    //
    // ASS and SSA containers prepend event fields which are not presentation text; this method
    // removes those fields together with inline markup before retaining the cue.
    mtd addEncodedCue(startSeconds, endSeconds: f64, text: string)
    {
        let content = .format == .SubStationAlpha ? commaTail(text, 7) : text
        var clean: String
        stripSubtitleMarkup(&clean, content)
        if clean.length do
            .addCue(startSeconds, endSeconds, clean.toString())
    }

    // Orders cues by start time and then by end time.
    mtd sortCues()
    {
        .cues.sort(func(a, b)
        {
            if a.startSeconds != b.startSeconds do
                return a.startSeconds <=> b.startSeconds
            return a.endSeconds <=> b.endSeconds
        })
    }

    // Returns the visible text and the next point at which it can change.
    mtd const presentationAt(seconds: f64)->Presentation
    {
        var result: retval
        result.nextChangeSeconds = .copyPresentationAt(seconds, &result.text)
        return result
    }

    // Copies the active cue text into caller-owned storage and returns the next transition.
    #[Swag.NoInline]
    mtd const copyPresentationAt(seconds: f64, result: *String)->f64
    {
        result.clear()
        result.reserve(17)
        var nextChange = Swag.F64.Inf
        for cue, index in .cues
        {
            if cue.startSeconds > seconds
            {
                nextChange = Math.min(nextChange, cue.startSeconds)
                break
            }

            if cue.endSeconds <= seconds do
                continue
            if result.length do
                result.append('\n'rune)
            result[]   += .cueContent(index)
            nextChange = Math.min(nextChange, cue.endSeconds)
        }

        return nextChange
    }
}

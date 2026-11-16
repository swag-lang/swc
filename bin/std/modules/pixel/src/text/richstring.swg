#global public

using Core

// One layout run produced from a [[Pixel.RichString]].
//
// A chunk is a slice of the text with uniform style and shaping data.
// Its string view remains valid only while the owning rich string is unchanged.
struct RichChunk
{
    public
    {
        slice:        string = ""                   // Borrowed UTF-8 slice represented by this run.
        fontStyle:    FontFamilyStyle = Regular     // Requested family style.
        hasFontStyle: bool                          // Whether the run explicitly selects `fontStyle`.
        isSpace:      bool                          // Whether the chunk is whitespace.
        isEol:        bool                          // Whether the chunk terminates a line.
        isUrl:        bool                          // Whether the chunk belongs to a link.
        urlStart:     u64    = Swag.U64.Max         // Text byte offset identifying the link, or U64.Max outside links.
        isHotUrl:     bool                          // Whether pointer interaction currently highlights the link.
        visible:      bool                          // Whether layout retained the chunk for painting.
        colorIdx:     s32                           // Palette slot of the run; zero is the default text color.

        boundRect: Math.Rectangle            // Bounds local to `pos`, in pixels.
        pos:       Math.Point                // Chunk origin in the containing layout.
        late font: *Font                     // Borrowed font selected for this chunk.
        shaped:    ShapedRun                 // Positioned glyphs for the chunk.
        under:     UnderlineStyle = None     // Underline or strikeout decoration.
    }
}

// Inline style of one run of a [[Pixel.RichString]].
//
// The default value is plain text: the regular face, no decoration, and the default color.
struct RichStyle
{
    public
    {
        bold:         bool     // Selects the bold face of the family.
        italic:       bool     // Selects the italic face of the family.
        underline:    UnderlineStyle = None     // Decoration drawn with the run.
        paletteIndex: u32      // Slot of [[Pixel.RichStringFormat.palette]], from 0 to 3; zero is the default text color.
    }
}

impl RichStyle
{
    // Returns whether the style changes nothing about the text it is applied to.
    mtd const isPlain()->bool => not .bold and not .italic and .underline == .None and .paletteIndex == 0
}

// One styled range of the text of a rich string. Ranges are ordered and never overlap.
#[Swag.NoDoc]
struct RichSpan
{
    start:     u64           // First text byte of the range.
    count:     u64           // Byte length of the range.
    style:     RichStyle     // Style of the range.
    linkStart: u64 = Swag.U64.Max     // Text offset where the enclosing link starts, or U64.Max outside links.
    target:    String        // Link target, or empty when the link text is its own target.
}

// Text with inline style runs for Pixel painting and layout.
//
// A rich string holds the visible text and the runs that style parts of it. Text given through
// assignment, [[Pixel.RichString.set]] or [[Pixel.RichString.append]] is always literal: no
// character of it is interpreted, so a file name or any other outside text is safe as it is.
//
// ```swag
// var label: Pixel.RichString
// label.append("Status: ")
// label.append(status, {bold: true})
// ```
//
// When the styling belongs to the sentence itself, as in a translated string that emphasizes
// one of its words, write the sentence in inline markup and give it to
// [[Pixel.RichString.setMarkup]]. Pass outside text through [[Pixel.RichString.escape]] before
// formatting it into markup.
struct RichString
{
    public
    {
        // Visible text, without any style information. Change it through the methods, which keep
        // the style runs in step with it.
        readonly text: String

        // Everything below comes out of [[Pixel.RichString.compute]] and the layout pass that
        // follows it. They describe the last result, and stay writable because the layout engine
        // lives in [[Pixel.Painter]].
        chunks:      Array'RichChunk     // Styled runs produced by 'compute'.
        layoutRect:  Math.Rectangle      // Rectangle used by the most recent layout.
        boundRect:   Math.Rectangle      // Bounds of visible content from the most recent layout.
        hasUrl:      bool                // Whether at least one chunk is a link.
        layoutScale: f32                 // Device scale used by the most recent layout, or zero before one.
    }

    // Styled ranges of `text`, in text order.
    spans: Array'RichSpan

    // Whether the chunks must be rebuilt before the next layout or paint.
    dirty: bool
}

// Reports whether a line may break at `c`.
//
// A no-break space is a space the author placed to keep its neighbours on one line, so it
// stays inside the word it sits in.
private func isBreakingSpace(c: rune)->bool => Unicode.isSpace(c) and c != ' 'rune and c != ' 'rune and c != ' 'rune

// Reads inline markup into visible text and, when `spans` is given, its style ranges.
private struct MarkupReader
{
    late text: *String     // Receives the visible text.
    spans:     *Array'RichSpan?     // Receives the style ranges, or null to keep the text only.

    bold:      u32           // Open `<b>` elements.
    italic:    u32           // Open `<i>` elements.
    underline: u32           // Open `<u>` elements.
    links:     u32           // Open `<a>` elements.
    colors:    Array'u32     // Palette slots of the open `<span>` elements.

    runStart:  u64        // Text offset where the current style took effect.
    linkStart: u64 = Swag.U64.Max     // Text offset where the outermost open link starts.
    target:    String     // Target of the outermost open link.
}

private impl MarkupReader
{
    // Closes the range the current style covers, before that style changes.
    mtd flush()
    {
        let end = .text.length
        defer .runStart = end
        if not .spans or end == .runStart do
            return

        var span: RichSpan
        span.start              = .runStart
        span.count              = end - .runStart
        span.style.bold         = .bold != 0
        span.style.italic       = .italic != 0
        span.style.underline    = .underline ? .Underline : .None
        span.style.paletteIndex = .colors.isEmpty() ? 0 : .colors.back()
        if .links
        {
            span.linkStart = .linkStart
            span.target    = .target
        }

        if not span.style.isPlain() or .links do
            .spans.add(span)
    }

    mtd openLink(target: string)
    {
        .flush()
        if not .links
        {
            .linkStart = .text.length
            .target    = target
        }

        .links += 1
    }

    mtd openColor(paletteIndex: u32)
    {
        .flush()
        .colors.add(paletteIndex)
    }

    // Applies the element that opens `source` and returns its byte length, or zero when `source`
    // does not open with a known element and its first byte is literal text.
    mtd element(source: const [..] u8)->u64
    {
        const HrefOpen  = "<a href=\""
        const HrefClose = "\">"

        switch
        {
        case Utf8.startsWith(source, "<b>"):
            .flush()
            .bold += 1
            return 3

        case Utf8.startsWith(source, "</b>"):
            .flush()
            if .bold do
                .bold -= 1
            return 4

        case Utf8.startsWith(source, "<i>"):
            .flush()
            .italic += 1
            return 3

        case Utf8.startsWith(source, "</i>"):
            .flush()
            if .italic do
                .italic -= 1
            return 4

        case Utf8.startsWith(source, "<u>"):
            .flush()
            .underline += 1
            return 3

        case Utf8.startsWith(source, "</u>"):
            .flush()
            if .underline do
                .underline -= 1
            return 4

        case Utf8.startsWith(source, "<span class=\"p1\">"):
            .openColor(1)
            return 17

        case Utf8.startsWith(source, "<span class=\"p2\">"):
            .openColor(2)
            return 17

        case Utf8.startsWith(source, "<span class=\"p3\">"):
            .openColor(3)
            return 17

        case Utf8.startsWith(source, "</span>"):
            .flush()
            if not .colors.isEmpty() do
                .colors.removeBack()
            return 7

        case Utf8.startsWith(source, "<a>"):
            .openLink("")
            return 3

        case Utf8.startsWith(source, HrefOpen):
            let close = Utf8.indexOf(source, HrefClose, HrefOpen.count)
            if close == Swag.U64.Max do
                return 0
            .openLink(Swag.makeString(source.buffer + HrefOpen.count, close - HrefOpen.count))
            return close + HrefClose.count

        case Utf8.startsWith(source, "</a>"):
            .flush()
            if .links do
                .links -= 1
            return 4

        case Utf8.startsWith(source, "<br>"):
            .text.append('\n'u8)
            return 4
        }

        return 0
    }

    // Appends the character the entity opening `source` stands for and returns the entity's byte
    // length, or zero when `source` does not open with a known entity.
    mtd entity(source: const [..] u8)->u64
    {
        switch
        {
        case Utf8.startsWith(source, "&lt;"):
            .text.append('<'u8)
            return 4

        case Utf8.startsWith(source, "&gt;"):
            .text.append('>'u8)
            return 4

        case Utf8.startsWith(source, "&amp;"):
            .text.append('&'u8)
            return 5

        case Utf8.startsWith(source, "&quot;"):
            .text.append('"'u8)
            return 6

        case Utf8.startsWith(source, "&apos;"):
            .text.append('\''u8)
            return 6

        case Utf8.startsWith(source, "&nbsp;"):
            .text.append(" ")
            return 6
        }

        return 0
    }

    mtd read(markup: string)
    {
        var scan  = markup.buffer
        var count = markup.count
        .text.reserve(.text.length + count)

        while count
        {
            let source = Swag.makeSlice(scan, count)

            var eaten = 0'u64
            if scan[] == '<' do
                eaten = .element(source)
            elif scan[] == '&' do
                eaten = .entity(source)

            if not eaten
            {
                .text.append(scan[])
                eaten = 1
            }

            scan  += eaten
            count -= eaten
        }

        .flush()
    }
}

impl RichString
{
    // Reports whether the visible text equals `other`, whatever its style runs.
    mtd const opEquals(other: string)->bool => .text == other

    // Invalidates the copied chunks, whose slices still point into the source text.
    mtd opPostCopy()
    {
        .chunks.clear()
        .layoutRect.clear()
        .dirty = true
    }

    // Returns the UTF-8 byte length of the visible text.
    #[Swag.Inline]
    mtd opCount() => .text.length

    // Replaces the content with the literal text `str`, as [[Pixel.RichString.set]] does.
    #[Swag.Inline]
    mtd opSet(str: string) => .set(str)

    // Returns whether the text is empty.
    #[Swag.Inline]
    mtd const isEmpty() => .text.isEmpty()

    // Returns whether the whole text is plain: no run changes its style and it holds no link.
    #[Swag.Inline]
    mtd const isPlain() => .spans.isEmpty()

    // Discards the last layout, so the next draw lays the text out again.
    mtd invalidate()
    {
        .layoutRect.clear()
    }

    // Removes the text and its style runs.
    mtd clear()
    {
        .text.clear()
        .spans.clear()
        .dirty = true
    }

    // Replaces the content with `text`, taken literally and drawn in `style`.
    //
    // A `null` text is empty. The text can span several lines. No character of it is interpreted:
    // `<b>` shows as those three characters. Setting the plain text the string already holds
    // keeps its layout.
    //
    // ```swag
    // title.set(fileName)
    // heading.set(sectionName, {bold: true})
    // ```
    mtd set(text: string?, style: RichStyle = {})
    {
        let value = text orelse ""
        if style.isPlain() and .spans.isEmpty() and .text == value do
            return

        .text = value
        .spans.clear()
        if not style.isPlain() and value.count do
            .spans.add({start: 0, count: value.count, style: style})
        .dirty = true
    }

    // Appends `text`, taken literally and drawn in `style`.
    //
    // ```swag
    // line.append(appName, {bold: true})
    // line.append(" is up to date.")
    // ```
    mtd append(text: string?, style: RichStyle = {})
    {
        let value = text orelse ""
        if not value.count do
            return

        if not style.isPlain() do
            .spans.add({start: .text.length, count: value.count, style: style})
        .text  += value
        .dirty = true
    }

    // Appends `text` as a link the reader can activate.
    //
    // `target` is what [[Pixel.RichString.urlTarget]] reports for the link; without one the link
    // text is its own target. The link is drawn in the link colors of the format, in `style`.
    mtd appendLink(text: string, target: string? = null, style: RichStyle = {})
    {
        if not text.count do
            return

        var span: RichSpan
        span.start     = .text.length
        span.count     = text.count
        span.style     = style
        span.linkStart = span.start
        span.target    = target
        .spans.add(span)
        .text  += text
        .dirty = true
    }

    // Replaces the content with a sentence written in inline markup.
    //
    // The markup is a strict subset of inline HTML, so the same sentence reads the same in an
    // HTML view:
    //
    // - `<b>`, `<i>` and `<u>` for bold, italic and underlined text;
    // - `<a>` for a link whose text is its own target, and `<a href="target">` to name the target;
    // - `<span class="p1">`, `"p2"` or `"p3"` for a slot of [[Pixel.RichStringFormat.palette]];
    // - `<br>` for a line break, which a newline character gives as well;
    // - `&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;` and `&nbsp;` for the characters they name.
    //
    // Elements nest, and one left open runs to the end of the text. Anything else is literal,
    // including an element or an entity this list does not name. A `null` markup is empty.
    //
    // Markup is for text the program owns. Pass any outside text formatted into it through
    // [[Pixel.RichString.escape]] first, or build the string with [[Pixel.RichString.append]].
    //
    // ```swag
    // label.setMarkup("Retry after <a>15 minutes</a>.")
    // title.setMarkup(Format.toString(texts.replaceTitle, RichString.escape(fileName)))
    // ```
    mtd setMarkup(markup: string?)
    {
        .text.clear()
        .spans.clear()
        .dirty = true

        var reader = MarkupReader{text: &.text, spans: &.spans}
        reader.read(markup orelse "")
    }

    // Returns a rich string holding the sentence `markup`, as [[Pixel.RichString.setMarkup]] reads it.
    func fromMarkup(markup: string?)->RichString
    {
        var result: #returntype
        result.setMarkup(markup)
        return result
    }

    // Returns the visible text of `markup`, without its elements and with its entities decoded.
    func plainText(markup: string)->String
    {
        var result: #returntype
        var reader = MarkupReader{text: &result}
        reader.read(markup)
        return result
    }

    // Returns `text` with the characters markup gives a meaning to replaced by their entities.
    //
    // The result reads back as exactly `text` when it is part of a markup sentence.
    func escape(text: string)->String
    {
        var result: #returntype
        result.reserve(text.count)
        for c in cast(const [..] u8, text)
        {
            switch c
            {
            case '<': result += "&lt;"
            case '>': result += "&gt;"
            case '&': result += "&amp;"
            default:  result.append(c)
            }
        }

        return result
    }

    // Returns the visible link chunk containing `at`, or `null` when there is none.
    //
    // `at` is expressed in the coordinates of the last layout.
    mtd getUrlChunkAt(at: Math.Point)->*RichChunk?
    {
        if not .hasUrl do
            return null
        for &c in .chunks where c.isUrl and c.visible
        {
            var r = c.boundRect
            r.offset(c.pos)
            if r.contains(at) do
                return c
        }

        return null
    }

    // Returns the complete visible text of the link identified by [[Pixel.RichChunk.urlStart]].
    //
    // A link can contain several styled runs or wrapped words. Returns empty for an unknown
    // offset.
    mtd urlText(start: u64)->String
    {
        .compute()
        var result: #returntype
        for &chunk in .chunks where chunk.isUrl and chunk.urlStart == start do
            result += chunk.slice
        return result
    }

    // Returns the target of the link identified by [[Pixel.RichChunk.urlStart]].
    //
    // The target is the one the link names, or its visible text when it names none. An unknown
    // offset returns empty.
    mtd urlTarget(start: u64)->String
    {
        for &span in .spans where span.linkStart == start and not span.target.isEmpty() do
            return span.target
        return .urlText(start)
    }

    // Adds the chunk covering the text bytes from `first` up to `last`, styled by `span`.
    private mtd addChunk(first, last: u64, span: const *RichSpan?, space, eol: bool = false)
    {
        if last == first do
            return

        var chunk: RichChunk
        chunk.isSpace = space
        chunk.isEol   = eol
        chunk.slice   = Swag.makeString(.text.buffer + first, last - first)

        if span
        {
            chunk.isUrl    = span.linkStart != Swag.U64.Max
            chunk.urlStart = span.linkStart
            chunk.colorIdx = cast(s32, span.style.paletteIndex)
            chunk.under    = span.style.underline

            chunk.hasFontStyle = span.style.bold or span.style.italic
            if span.style.bold and span.style.italic do
                chunk.fontStyle = .BoldItalic
            elif span.style.bold do
                chunk.fontStyle = .Bold
            elif span.style.italic do
                chunk.fontStyle = .Italic
        }

        if chunk.isUrl do
            .hasUrl = true
        .chunks.add(chunk)
    }

    // Splits the text into chunks that each carry one style.
    //
    // A chunk ends where the style changes, at each run of spaces, and at each line break. The
    // chunks are rebuilt only when the content changed or when `force` is true, and the last
    // layout is discarded with them.
    mtd compute(force = false)
    {
        if not .dirty and not force do
            return

        .dirty  = false
        .hasUrl = false
        .chunks.clear()
        .layoutRect.clear()

        let length     = .text.length
        var index      = 0'u64
        var chunkStart = 0'u64
        var spanIndex  = 0'u64

        while index < length
        {
            // The text up to `regionEnd` shares one style: that of the range covering `index`, or
            // the plain style up to the next range.
            while spanIndex < .spans.count and .spans[spanIndex].start + .spans[spanIndex].count <= index do
                spanIndex += 1

            var span: const *RichSpan?
            var regionEnd = length
            if spanIndex < .spans.count
            {
                let next = &.spans[spanIndex]
                if next.start <= index
                {
                    span      = next
                    regionEnd = Math.min(next.start + next.count, length)
                }
                else
                {
                    regionEnd = Math.min(next.start, length)
                }
            }

            while index < regionEnd
            {
                var {c, eat} = Utf8.decodeRune(Swag.makeSlice(.text.buffer + index, regionEnd - index))
                if eat == 0
                {
                    index = regionEnd
                    break
                }

                if c == '\r' or c == '\n'
                {
                    .addChunk(chunkStart, index, span)
                    chunkStart = index
                    index      += eat
                    if c == '\r' and index < regionEnd and .text[index] == '\n' do
                        index += 1

                    .addChunk(chunkStart, index, span, eol: true)
                    chunkStart = index
                    continue
                }

                if isBreakingSpace(c)
                {
                    .addChunk(chunkStart, index, span)
                    chunkStart = index

                    // A line break is white space too, but it ends the line: it is left for the
                    // next turn of the loop instead of being folded into the run of spaces.
                    while eat and isBreakingSpace(c) and c != '\r' and c != '\n'
                    {
                        index    += eat
                        {c, eat} = Utf8.decodeRune(Swag.makeSlice(.text.buffer + index, regionEnd - index))
                    }

                    .addChunk(chunkStart, index, span, space: true)
                    chunkStart = index
                    continue
                }

                index += eat
            }

            .addChunk(chunkStart, index, span)
            chunkStart = index
        }
    }
}

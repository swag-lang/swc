#global public

using Core

// One layout run produced from a [[Pixel.RichString]].
//
// A chunk is a slice of the original text with uniform style and shaping data.
// Its string view remains valid only while the owning rich string is unchanged.
struct RichChunk
{
    public
    {
        slice:        string = ""                   // Borrowed UTF-8 slice represented by this run.
        fontStyle:    FontFamilyStyle = Regular     // Requested family style.
        hasFontStyle: bool                          // Whether markup explicitly selected `fontStyle`.
        isSpace:      bool                          // Whether the chunk is whitespace.
        isEol:        bool                          // Whether the chunk terminates a line.
        isUrl:        bool                          // Whether the chunk belongs to `<url>` markup.
        isHotUrl:     bool                          // Whether pointer interaction currently highlights the URL.
        visible:      bool                          // Whether layout retained the chunk for painting.
        colorIdx:     s32                           // Palette color index selected by `<pN>` markup.

        boundRect: Math.Rectangle            // Bounds local to `pos`, in pixels.
        pos:       Math.Point                // Chunk origin in the containing layout.
        late font: *Font                     // Borrowed font selected for this chunk.
        shaped:    ShapedRun                 // Positioned glyphs for the chunk.
        under:     UnderlineStyle = None     // Underline or strikeout decoration.
    }
}

// Text with lightweight inline formatting for Pixel painting and layout.
//
// Markup can select bold, italic, underline, palette colors, and clickable URL
// spans. The original text is retained in `raw`; call [[Pixel.RichString.compute]]
// after changing layout inputs to rebuild the styled chunks.
//
// ## Example
//
// ```swag
// var label: Pixel.RichString
// label = "Status: <b><p1>ready</p></b>"
// label.compute()
// ```
//
// See [[Pixel.RichString.set]] for the complete marker set.
struct RichString
{
    public
    {
        raw: String     // Original text, including formatting markers.

        // Everything below comes out of [[Pixel.RichString.compute]] and the layout pass that
        // follows it. Set 'raw' through the methods and compute again; these describe the last
        // result. They stay writable because the layout engine lives in [[Pixel.Painter]].
        chunks:      Array'RichChunk     // Styled runs produced by 'compute'.
        layoutRect:  Math.Rectangle      // Rectangle used by the most recent layout.
        boundRect:   Math.Rectangle      // Bounds of visible content from the most recent layout.
        hasUrl:      bool                // Whether at least one chunk is a URL.
        layoutScale: f32                 // Device scale used by the most recent layout, or zero before one.
    }

    // Whether the chunks must be rebuilt before the next layout or paint.
    dirty: bool
}

impl RichString
{
    // Reports whether the original marked-up text equals `other`.
    mtd opEquals(other: string)->bool => .raw == other

    // Invalidates the copied chunks, whose slices still point into the source text.
    mtd opPostCopy()
    {
        .chunks.clear()
        .set(.raw)
    }

    #[Swag.Mixin]
    private mtd addChunk(idx: u64, space, eol, url: bool = false)
    {
        if idx - startChunk == 0 do
            return

        chunk.isSpace      = space
        chunk.isEol        = eol
        chunk.isUrl        = url or isUrl.back()
        chunk.visible      = false
        chunk.colorIdx     = colorFg.back()
        chunk.under        = under.back()
        chunk.hasFontStyle = false

        if chunk.isUrl do
            .hasUrl = true

        if isBold.back() and isItalic.back()
        {
            chunk.hasFontStyle = true
            chunk.fontStyle    = .BoldItalic
        }
        elif isBold.back()
        {
            chunk.hasFontStyle = true
            chunk.fontStyle    = .Bold
        }
        elif isItalic.back()
        {
            chunk.hasFontStyle = true
            chunk.fontStyle    = .Italic
        }

        chunk.slice = Swag.makeString(.raw.buffer + startChunk, idx - startChunk)
        .chunks.add(chunk)
        startChunk = idx
    }

    // Returns the UTF-8 byte length of the original marked-up text.
    #[Swag.Inline]
    mtd opCount() => .raw.length

    // Replaces the original text and invalidates its parsed chunks.
    #[Swag.Inline]
    mtd opSet(str: string) => .set(str)

    // Returns whether the marked-up text is empty.
    #[Swag.Inline]
    mtd const isEmpty() => .raw.isEmpty()

    // Discards the last layout, so the next draw lays the text out again.
    mtd invalidate()
    {
        .layoutRect.clear()
    }

    // Replaces the marked-up text and invalidates its chunks.
    //
    // A `null` text is empty. The text can span several lines and accepts these markers, each
    // closed by its `</...>` counterpart:
    //
    // - `<b>` for bold;
    // - `<i>` for italic;
    // - `<u>` for underline;
    // - `<p1>`, `<p2>`, and `<p3>` for a palette color, closed by `</p>`;
    // - `<url>` for a clickable link.
    //
    // ```swag
    // label.set("<b>this is bold</b> but this is normal <i>and this is italic</i>")
    // ```
    mtd set(text: string?)
    {
        if .chunks.count and .raw == text do
            return
        .raw   = text orelse ""
        .dirty = true
    }

    // Returns owned plain text with supported formatting markers removed.
    func plainText(str: string)->String
    {
        var result: retval

        var scan  = str.buffer
        var count = str.count
        result.reserve(count)

        while count
        {
            let sl      = Swag.makeSlice(scan, count)
            var handled = false
            switch
            {
            case Utf8.startsWith(sl, "<u>"), Utf8.startsWith(sl, "<b>"), Utf8.startsWith(sl, "<i>"):
                scan    += 3
                count   -= 3
                handled = true

            case Utf8.startsWith(sl, "</u>"), Utf8.startsWith(sl, "</b>"), Utf8.startsWith(sl, "</i>"), Utf8.startsWith(sl, "</p>"):
                scan    += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<p1>"), Utf8.startsWith(sl, "<p2>"), Utf8.startsWith(sl, "<p3>"):
                scan    += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<url>"):
                scan    += 5
                count   -= 5
                handled = true

            case Utf8.startsWith(sl, "</url>"):
                scan    += 6
                count   -= 6
                handled = true
            }

            if handled do
                continue

            result += scan[]
            scan   += 1
            count  -= 1
        }

        return result
    }

    // Returns the visible URL chunk containing `at`, or `null` when there is none.
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

    // Splits the marked-up text into chunks that each carry one style.
    //
    // The chunks are rebuilt only when the text changed or when `force` is true, and the last
    // layout is discarded with them.
    mtd compute(force = false)
    {
        if not .dirty and not force do
            return

        .dirty  = false
        .hasUrl = false
        .chunks.clear()
        .layoutRect.clear()

        var count = .raw.length
        if not count do
            return

        var startChunk = 0'u64
        var chunk: RichChunk

        var byteIdx = 0'u64
        var isBold:   Array'bool
        var isItalic: Array'bool
        var isUrl:    Array'bool
        var colorFg:  Array'u32
        var under:    Array'UnderlineStyle

        isBold.add(false)
        isItalic.add(false)
        isUrl.add(false)
        colorFg.add(0)
        under.add(UnderlineStyle.None)

        var scan = .raw.buffer
        while count
        {
            var sl      = Swag.makeSlice(scan, count)
            var handled = false
            switch
            {
            case sl[0] != '<':
                break

            case Utf8.startsWith(sl, "<u>"):
                .addChunk(byteIdx)
                under.add(UnderlineStyle.Underline)
                byteIdx, scan, startChunk += 3
                count   -= 3
                handled = true

            case Utf8.startsWith(sl, "</u>"):
                .addChunk(byteIdx)
                if under.count > 1 do
                    under.removeBack()
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<b>"):
                .addChunk(byteIdx)
                isBold.add(true)
                byteIdx, scan, startChunk += 3
                count   -= 3
                handled = true

            case Utf8.startsWith(sl, "</b>"):
                .addChunk(byteIdx)
                if isBold.count > 1 do
                    isBold.removeBack()
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<i>"):
                .addChunk(byteIdx)
                isItalic.add(true)
                byteIdx, scan, startChunk += 3
                count   -= 3
                handled = true

            case Utf8.startsWith(sl, "</i>"):
                .addChunk(byteIdx)
                if isItalic.count > 1 do
                    isItalic.removeBack()
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<p1>"):
                .addChunk(byteIdx)
                colorFg.add(1)
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<p2>"):
                .addChunk(byteIdx)
                colorFg.add(2)
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<p3>"):
                .addChunk(byteIdx)
                colorFg.add(3)
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "</p>"):
                .addChunk(byteIdx)
                if colorFg.count > 1 do
                    colorFg.removeBack()
                byteIdx, scan, startChunk += 4
                count   -= 4
                handled = true

            case Utf8.startsWith(sl, "<url>"):
                .addChunk(byteIdx)
                isUrl.add(true)
                byteIdx, scan, startChunk += 5
                count   -= 5
                handled = true

            case Utf8.startsWith(sl, "</url>"):
                .addChunk(byteIdx)
                if isUrl.count > 1 do
                    isUrl.removeBack()
                byteIdx, scan, startChunk += 6
                count   -= 6
                handled = true
            }

            if handled do
                continue

            var {c, eat} = Utf8.decodeRune(sl)
            if eat == 0 do
                break

            if c == '\r' or c == '\n'
            {
                .addChunk(byteIdx)
                byteIdx, scan += eat
                count         -= eat
                if c == '\r' and count
                {
                    sl = Swag.makeSlice(scan, count)
                    let {next, nextEat} = Utf8.decodeRune(sl)
                    if next == '\n'
                    {
                        byteIdx, scan += nextEat
                        count         -= nextEat
                    }
                }

                .addChunk(byteIdx, eol: true)
                continue
            }

            if Unicode.isSpace(c)
            {
                .addChunk(byteIdx)
                while eat and Unicode.isSpace(c)
                {
                    byteIdx, scan += eat
                    count         -= eat
                    sl            = Swag.makeSlice(scan, count)
                    {c, eat}      = Utf8.decodeRune(sl)
                }

                .addChunk(byteIdx, space: true)
                continue
            }

            byteIdx, scan += eat
            count         -= eat
        }

        // Remaining chunk
        Swag.assert(startChunk <= .raw.length)
        if startChunk < .raw.length do
            .addChunk(.raw.length)
    }
}

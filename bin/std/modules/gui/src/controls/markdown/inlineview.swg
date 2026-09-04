#global internal
#global namespace Markdown

using Core, Pixel

// How far a justified space may grow, in line heights. It is the bound Pixel's own justified text
// uses, so a line one engine leaves ragged is left ragged by the other for the same reason.
private const JustifyLimit = 2.0

#[Swag.EnumFlags]
private enum InlineFlags
{
    None = 0
    Bold
    Italic
    Strikeout
    Code
    Highlight
    Link
    Subscript
    Superscript
    ListMarker
    ListBullet
    ListUnchecked
    ListChecked
}

private struct InlineAtom
{
    text:       String
    target:     String
    expression: MathExpression
    position:   Math.Rectangle
    textStart:  u64     // Byte offset of this atom in the view's text, which is what a search and a selection address.
    ascent:     f32
    descent:    f32
    colorIndex: u32
    flags:      InlineFlags
    isMath:     bool
    isSpace:    bool
    isBreak:    bool
    visible:    bool
    searchHit:  bool
}

// Returns how many bytes one atom contributes to the view's text.
//
// A run of whitespace and a line ending are each rendered, searched, and copied as one character
// whatever the author wrote, so both count as one; every other atom counts its own text, which is
// the mathematical source for a formula.
private func atomTextLength(atom: const *InlineAtom)->u64
{
    if atom.isBreak or atom.isSpace do
        return 1
    return atom.text.count
}

// Returns the text one atom contributes to the view's text.
private func atomText(atom: const *InlineAtom)->string
{
    if atom.isBreak do
        return "\n"
    if atom.isSpace do
        return " "
    return atom.text.toString()
}

// One laid-out line of the view, and the run of atoms it holds.
//
// The layout produces these on its way through the atoms. A selection is drawn from them rather
// than from the atoms themselves: a band that follows each glyph's own box breaks at every word,
// every space and every change of size, which reads as hatching rather than as one selection.
private struct InlineLine
{
    top:    f32     // Top of the line box, in the view's coordinates.
    height: f32     // Full height of the line box, so consecutive lines abut exactly.
    first:  u64     // First atom of the line.
    last:   u64     // One past the last atom of the line.
}

private struct InlineState
{
    bold:          u32
    italic:        u32
    strikeout:     u32
    code:          u32
    highlight:     u32
    link:          u32
    subscript:     u32
    superscript:   u32
    listMarker:    u32
    listBullet:    u32
    listUnchecked: u32
    listChecked:   u32
    colorIndex:    u32
}

private impl InlineState
{
    mtd const flags()->InlineFlags
    {
        var result = InlineFlags.None
        if .bold do
            result.add(.Bold)
        if .italic do
            result.add(.Italic)
        if .strikeout do
            result.add(.Strikeout)
        if .code do
            result.add(.Code)
        if .highlight do
            result.add(.Highlight)
        if .link do
            result.add(.Link)
        if .subscript do
            result.add(.Subscript)
        if .superscript do
            result.add(.Superscript)
        if .listMarker do
            result.add(.ListMarker)
        if .listBullet do
            result.add(.ListBullet)
        if .listUnchecked do
            result.add(.ListUnchecked)
        if .listChecked do
            result.add(.ListChecked)
        return result
    }
}

#[Swag.Opaque, Swag.NoDoc]
public struct InlineView
{
    using wnd: Wnd

    owner: *View
    kind:  BlockKind
    atoms: Array'InlineAtom
    lines: Array'InlineLine

    // Where this view sits in the reading order of every text view the document owns, which is
    // the coordinate a document-wide selection is expressed in. Assigned once, at creation.
    orderIndex:   u64
    textLength:   u64     // Total bytes of the view's text, the upper bound of every offset into it.
    layoutWidth:  f32
    layoutHeight: f32
    hotAtom:      #null *InlineAtom
    horizontalAlignment = StringHorzAlignment.Left
    searchStart         = Swag.U64.Max
    searchEnd:    u64
}

impl InlineView
{
    mtd clearSearchHighlight()
    {
        var changed = .searchStart != Swag.U64.Max
        .searchStart = Swag.U64.Max
        .searchEnd   = 0
        for &atom in .atoms where atom.searchHit
        {
            atom.searchHit = false
            changed        = true
        }

        if changed do
            .invalidate()
    }

    // Returns the whole text of the view: what a search matches against, and what a selection
    // spanning it copies.
    mtd text()->String
    {
        var result: retval
        for &atom in .atoms do
            result += atomText(atom)
        return result
    }

    // Returns the part of the view's text between two byte offsets.
    mtd textSlice(start, end: u64)->String
    {
        var result: retval
        for &atom in .atoms
        {
            let atomEnd = atom.textStart + atomTextLength(atom)
            if atomEnd <= start do
                continue
            if atom.textStart >= end do
                break

            let source = atomText(atom)
            let low    = Math.max(start, atom.textStart) - atom.textStart
            let high   = Math.min(end, atomEnd) - atom.textStart
            if low == 0 and high >= source.count do
                result += source
            elif low < source.count do
                result += source[low until Math.min(high, source.count)]
        }

        return result
    }

    mtd searchMatchCount(text: string)->u64
    {
        if !text.count do
            return 0

        let source = .text()
        var count: u64
        var from:  u64
        while true
        {
            let match = Utf8.indexOf(source.toString(), text, from, .Latin1NoCase)
            if match == Swag.U64.Max do
                return count
            count += 1
            from  = match + text.count
        }
    }

    // Highlights the exact rendered range of one case-insensitive match.
    mtd highlightText(text: string, occurrence: u64 = 0)->bool
    {
        .clearSearchHighlight()
        if !text.count do
            return false

        let source = .text()
        var match: u64
        var from:  u64
        for occurrence + 1
        {
            match = Utf8.indexOf(source.toString(), text, from, .Latin1NoCase)
            if match == Swag.U64.Max do
                return false
            from = match + text.count
        }

        .searchStart = match
        .searchEnd   = match + text.count
        for &atom in .atoms where atom.textStart < .searchEnd and atom.textStart + atomTextLength(atom) > .searchStart do
            atom.searchHit = true
        .invalidate()
        return true
    }

    mtd appendTextAtom(text: string, state: InlineState, isSpace = false, isBreak = false)
    {
        var atom: InlineAtom
        atom.text       = text
        atom.flags      = state.flags()
        atom.colorIndex = state.colorIndex
        atom.isSpace    = isSpace
        atom.isBreak    = isBreak
        .atoms.add(#move atom)
    }

    mtd appendWord(text: string, state: InlineState)
    {
        var start = 0'u64
        var index = 0'u64
        var runes = 0'u32
        while index < text.count
        {
            let {?, eat} = Utf8.decodeRune(text[index to])
            index += eat
            runes += 1
            if runes < 24 do
                continue
            .appendTextAtom(text[start until index], state)
            start = index
            runes = 0
        }

        if start < text.count do
            .appendTextAtom(text[start to], state)
    }

    mtd appendText(text: string, state: InlineState)
    {
        var start = 0'u64
        var index = 0'u64
        while index <= text.count
        {
            let atEnd = index == text.count
            let split = !atEnd and (text[index] == ' ' or text[index] == '\t' or text[index] == '\n' or text[index] == '\r')
            if !atEnd and !split
            {
                index += 1
                continue
            }

            if index > start do
                .appendWord(text[start until index], state)

            if atEnd do
                break

            var whitespaceEnd = index + 1
            if text[index] == '\r' and whitespaceEnd < text.count and text[whitespaceEnd] == '\n' do
                whitespaceEnd += 1

            let isBreak = text[index] == '\n' or text[index] == '\r'
            .appendTextAtom(text[index until whitespaceEnd], state, !isBreak, isBreak)
            index = whitespaceEnd
            start = index
        }
    }

    mtd appendMath(source: string, state: InlineState)
    {
        let expression = catch MathExpression.parse(source) as parseError
        if parseError != null
        {
            .appendText(source, state)
            return
        }

        // The formula keeps its source beside its parsed form: it is what a search matches and
        // what a selection crossing it copies, since nothing else can stand for a rendered
        // formula in plain text.
        var atom: InlineAtom
        atom.text       = source
        atom.expression = #move expression
        atom.flags      = state.flags()
        atom.colorIndex = state.colorIndex
        atom.isMath     = true
        .atoms.add(#move atom)
    }

    mtd assignLinkTarget(first: u64, target: string)
    {
        for index in first until .atoms.count
        {
            .atoms[index].flags.add(.Link)
            .atoms[index].target = target
        }
    }

    mtd parse(text: string)
    {
        .atoms.clear()
        var state: InlineState
        var index     = 0'u64
        var textStart = 0'u64
        var linkStart = Swag.U64.Max

        while index < text.count
        {
            if text[index] != '<'
            {
                index += 1
                continue
            }

            if index > textStart do
                .appendText(text[textStart until index], state)

            let remaining = text[index to]
            var eaten     = 0'u64
            switch
            {
            // The protocol escape for a literal '<' in document text.
            case Utf8.startsWith(remaining, "<<"):
                .appendText("<", state)
                eaten = 2

            case Utf8.startsWith(remaining, "<b>"):
                state.bold += 1
                eaten      = 3

            case Utf8.startsWith(remaining, "</b>"):
                state.bold = state.bold ? state.bold - 1 : 0
                eaten      = 4

            case Utf8.startsWith(remaining, "<i>"):
                state.italic += 1
                eaten        = 3

            case Utf8.startsWith(remaining, "</i>"):
                state.italic = state.italic ? state.italic - 1 : 0
                eaten        = 4

            case Utf8.startsWith(remaining, "<s>"):
                state.strikeout += 1
                eaten           = 3

            case Utf8.startsWith(remaining, "</s>"):
                state.strikeout = state.strikeout ? state.strikeout - 1 : 0
                eaten           = 4

            case Utf8.startsWith(remaining, "<c>"):
                state.code += 1
                eaten      = 3

            case Utf8.startsWith(remaining, "</c>"):
                state.code = state.code ? state.code - 1 : 0
                eaten      = 4

            case Utf8.startsWith(remaining, "<h>"):
                state.highlight += 1
                eaten           = 3

            case Utf8.startsWith(remaining, "</h>"):
                state.highlight = state.highlight ? state.highlight - 1 : 0
                eaten           = 4

            case Utf8.startsWith(remaining, "<sub>"):
                state.subscript += 1
                eaten           = 5

            case Utf8.startsWith(remaining, "</sub>"):
                state.subscript = state.subscript ? state.subscript - 1 : 0
                eaten           = 6

            case Utf8.startsWith(remaining, "<sup>"):
                state.superscript += 1
                eaten             = 5

            case Utf8.startsWith(remaining, "</sup>"):
                state.superscript = state.superscript ? state.superscript - 1 : 0
                eaten             = 6

            case Utf8.startsWith(remaining, "<lm>"):
                state.listMarker += 1
                eaten            = 4

            case Utf8.startsWith(remaining, "</lm>"):
                state.listMarker = state.listMarker ? state.listMarker - 1 : 0
                eaten            = 5

            case Utf8.startsWith(remaining, "<lb>"):
                state.listMarker += 1
                state.listBullet += 1
                eaten            = 4

            case Utf8.startsWith(remaining, "</lb>"):
                state.listMarker = state.listMarker ? state.listMarker - 1 : 0
                state.listBullet = state.listBullet ? state.listBullet - 1 : 0
                eaten            = 5

            case Utf8.startsWith(remaining, "<lu>"):
                state.listMarker    += 1
                state.listUnchecked += 1
                eaten               = 4

            case Utf8.startsWith(remaining, "</lu>"):
                state.listMarker    = state.listMarker ? state.listMarker - 1 : 0
                state.listUnchecked = state.listUnchecked ? state.listUnchecked - 1 : 0
                eaten               = 5

            case Utf8.startsWith(remaining, "<lc>"):
                state.listMarker  += 1
                state.listChecked += 1
                eaten             = 4

            case Utf8.startsWith(remaining, "</lc>"):
                state.listMarker  = state.listMarker ? state.listMarker - 1 : 0
                state.listChecked = state.listChecked ? state.listChecked - 1 : 0
                eaten             = 5

            case Utf8.startsWith(remaining, "<p1>"):
                state.colorIndex = 1
                eaten            = 4

            case Utf8.startsWith(remaining, "<p2>"):
                state.colorIndex = 2
                eaten            = 4

            case Utf8.startsWith(remaining, "<p3>"):
                state.colorIndex = 3
                eaten            = 4

            case Utf8.startsWith(remaining, "</p>"):
                state.colorIndex = 0
                eaten            = 4

            case Utf8.startsWith(remaining, "<a>"):
                state.link += 1
                linkStart  = .atoms.count
                eaten      = 3

            case Utf8.startsWith(remaining, "</a>"):
                state.link = state.link ? state.link - 1 : 0
                eaten      = 4

            case Utf8.startsWith(remaining, "<t>"):
                let end = Utf8.indexOf(text, "</t>", index + 3)
                if end != Swag.U64.Max
                {
                    if linkStart != Swag.U64.Max do
                        .assignLinkTarget(linkStart, text[index + 3 until end])
                    linkStart = Swag.U64.Max
                    eaten     = end - index + 4
                }

            case Utf8.startsWith(remaining, "<m>"):
                let end = Utf8.indexOf(text, "</m>", index + 3)
                if end != Swag.U64.Max
                {
                    .appendMath(text[index + 3 until end], state)
                    eaten = end - index + 4
                }
            }

            if !eaten
            {
                .appendText(text[index until index + 1], state)
                eaten = 1
            }

            index     += eaten
            textStart = index
        }

        if textStart < text.count do
            .appendText(text[textStart to], state)

        // Every atom takes its place in the view's text now, once, so a search, a hit test, a
        // selection and a copy all address the same coordinate without walking the atoms again.
        .textLength = 0
        for &atom in .atoms
        {
            atom.textStart = .textLength
            .textLength    += atomTextLength(atom)
        }

        .layoutWidth = 0
    }

    mtd padding()->Math.Vector4
    {
        switch .kind
        {
        case .Heading1: return {0, 8, 0, 2}
        case .Heading2: return {0, 8, 0, 2}
        case .Code:     return {18, 14, 18, 14}
        case .Table:    return {16, 12, 16, 12}

        case .Quote, .AlertNote, .AlertTip, .AlertImportant,
             .AlertWarning, .AlertCaution: return {18, 10, 10, 10}

        case .Metadata:        return {12, 8, 12, 8}
        case .TableOfContents: return {18, 12, 18, 12}
        case .Footnote:        return {0, 4, 0, 4}
        default:               return {0, 2, 0, 2}
        }
    }

    mtd fontSize()->u32
    {
        switch .kind
        {
        case .Heading1:     return .owner.documentStyle.heading1FontSize
        case .Heading2:     return .owner.documentStyle.heading2FontSize
        case .Heading3:     return .owner.documentStyle.heading3FontSize
        case .Heading4:     return .owner.documentStyle.heading4FontSize
        case .Heading5:     return .owner.documentStyle.heading5FontSize
        case .Heading6:     return .owner.documentStyle.heading6FontSize
        case .Code, .Table: return .owner.documentStyle.codeFontSize
        case .Metadata:     return Math.max(.owner.documentStyle.codeFontSize - 1, 8)
        case .Footnote:     return Math.max(.owner.documentStyle.bodyFontSize - 2, 8)
        default:            return .owner.documentStyle.bodyFontSize
        }
    }

    mtd fontStyle(flags: InlineFlags)->FontFamilyStyle
    {
        let bold   = flags.has(.Bold) or .kind >= .Heading1 and .kind <= .Heading6
        let italic = flags.has(.Italic) or .kind == .Quote
        if bold and italic do
            return .BoldItalic
        if bold do
            return .Bold
        if italic do
            return .Italic
        return .Regular
    }

    mtd font(atom: const *InlineAtom)->*Font
    {
        let style = .fontStyle(atom.flags)
        let size  = atom.flags.has(.Subscript) or atom.flags.has(.Superscript) ? Math.max(.fontSize() * 3 / 4, 8) : .fontSize()
        if atom.flags.has(.Code) or .kind == .Code or .kind == .Table or .kind == .Metadata do
            return .theme().createDefaultFontFS(size, style)
        return .theme().createDefaultFont(size, style)
    }

    mtd measureAtom(atom: *InlineAtom)
    {
        if atom.isMath
        {
            var options: MathLayoutOptions
            options.style = .Text
            let metrics = atom.expression.measure(.theme().createDefaultFont(.fontSize()), options)
            atom.position.width  = metrics.width
            atom.position.height = metrics.height()
            atom.ascent          = metrics.ascent
            atom.descent         = metrics.descent
            return
        }

        let font = .font(atom)
        if atom.flags.has(.ListBullet)
        {
            atom.position.width  = font.height * 0.55
            atom.position.height = font.height
            atom.ascent          = font.ascent
            atom.descent         = -font.descent
            return
        }

        if atom.flags.has(.ListUnchecked) or atom.flags.has(.ListChecked)
        {
            atom.position.width  = font.height * 0.8
            atom.position.height = font.height
            atom.ascent          = font.ascent
            atom.descent         = -font.descent
            return
        }

        let text = atom.isSpace ? " " : atom.text.toString()
        atom.position.width  = Painter.measureString(text, font).width
        atom.position.height = font.height
        atom.ascent          = font.ascent
        atom.descent         = -font.descent
    }

    // Places one finished line of atoms and returns the height it takes.
    //
    // `wrapped` says the line ended because the next word did not fit, which is the only line a
    // justified paragraph stretches: a line the author ended and the last line of a block keep
    // their natural width.
    mtd finishLine(first, last: u64, top, left, right: f32, wrapped: bool)->f32
    {
        if first >= last do
            return .theme().createDefaultFont(.fontSize()).height * .owner.documentStyle.lineHeight

        var ascent:  f32
        var descent: f32
        for index in first until last where .atoms[index].visible
        {
            ascent  = Math.max(ascent, .atoms[index].ascent)
            descent = Math.max(descent, .atoms[index].descent)
        }

        let natural   = ascent + descent
        let line      = Math.max(natural, .theme().createDefaultFont(.fontSize()).height * .owner.documentStyle.lineHeight)
        let offset    = (line - natural) * 0.5
        var lineRight = left
        for index in first until last where .atoms[index].visible do
            lineRight = Math.max(lineRight, .atoms[index].position.right())
        var shift: f32
        if .horizontalAlignment == .Center do
            shift = Math.max(right - lineRight, 0) * 0.5
        elif .horizontalAlignment == .Right do
            shift = Math.max(right - lineRight, 0)

        let stretch = .measureJustification(first, last, right, line, wrapped)
        var advance = shift
        for index in first until last where .atoms[index].visible
        {
            .atoms[index].position.x += advance
            .atoms[index].position.y = top + offset + ascent - .atoms[index].ascent
            if .atoms[index].flags.has(.Superscript) do
                .atoms[index].position.y -= ascent * 0.28
            elif .atoms[index].flags.has(.Subscript) do
                .atoms[index].position.y += descent * 0.55
            if .atoms[index].isSpace and index > stretch.firstInk and index < stretch.lastInk do
                advance += stretch.step
        }

        .lines.add(InlineLine{top, line, first, last})
        return line
    }

    // Returns how much every interior space of one wrapped line has to grow to reach `right`.
    //
    // A space is interior when ink stands on both sides of it: the space a wrap leaves at the end
    // of a line is what would otherwise absorb the whole stretch and leave the last word short of
    // the edge. The bound is the one Pixel's own justified text uses, so a line the two engines
    // both refuse to stretch is refused for the same reason.
    private mtd measureJustification(first, last: u64, right, line: f32, wrapped: bool)->{ step: f32, firstInk: u64, lastInk: u64 }
    {
        var result: retval
        result.firstInk = Swag.U64.Max
        if !wrapped or .horizontalAlignment != .Justify do
            return result

        var gaps     = 0'u64
        var gapWidth = 0'f32
        var inkEnd   = 0'f32
        var spaceAt  = Swag.U64.Max

        for index in first until last where .atoms[index].visible
        {
            if .atoms[index].isSpace
            {
                if result.firstInk != Swag.U64.Max and spaceAt == Swag.U64.Max do
                    spaceAt = index
                continue
            }

            if result.firstInk == Swag.U64.Max do
                result.firstInk = index
            elif spaceAt != Swag.U64.Max
            {
                gaps     += 1
                gapWidth = Math.max(gapWidth, .atoms[spaceAt].position.width)
            }

            spaceAt        = Swag.U64.Max
            result.lastInk = index
            inkEnd         = .atoms[index].position.right()
        }

        if !gaps do
            return result

        let step = Math.max(right - inkEnd, 0) / cast(f32) gaps
        if gapWidth + step < line * JustifyLimit do
            result.step = step
        return result
    }

    mtd layout(width: f32)->f32
    {
        if width <= 0 do
            return 0
        if .layoutWidth == width do
            return .layoutHeight

        if .kind == .Rule
        {
            .layoutWidth  = width
            .layoutHeight = 24
            return .layoutHeight
        }

        .lines.clear()

        let inset            = .padding()
        let left             = inset.x
        let right            = Math.max(width - inset.z, left + 1)
        var x                = left
        var y                = inset.y
        var first            = 0'u64
        var lineLeft         = left
        var continuationLeft = left
        var explicitStart    = true
        var afterMarker: bool

        for &atom, index in .atoms
        {
            atom.visible = false
            .measureAtom(atom)
            if atom.isBreak
            {
                y                += .finishLine(first, index, y, lineLeft, right, wrapped: false)
                x                = left
                first            = index + 1
                lineLeft         = left
                continuationLeft = left
                explicitStart    = true
                afterMarker      = false
                continue
            }

            // Whitespace the author wrote at the start of a line — code indentation, a nested
            // list level — is layout, so it renders; only the space a wrap left behind is dropped.
            if atom.isSpace and x == lineLeft and !explicitStart do
                continue
            if !atom.isSpace and x > lineLeft and x + atom.position.width > right
            {
                y        += .finishLine(first, index, y, lineLeft, right, wrapped: true)
                x        = continuationLeft
                first    = index
                lineLeft = continuationLeft
            }

            atom.visible    = true
            atom.position.x = x
            x               += atom.position.width
            if !atom.isSpace do
                explicitStart = false
            if atom.flags.has(.ListMarker) do
                afterMarker = true
            elif afterMarker and atom.isSpace do
                continuationLeft = x
            elif !atom.isSpace do
                afterMarker = false
        }

        if first < .atoms.count or .atoms.isEmpty() do
            y += .finishLine(first, .atoms.count, y, lineLeft, right, wrapped: false)
        .layoutWidth  = width
        .layoutHeight = y + inset.w
        return .layoutHeight
    }

    mtd color(atom: const *InlineAtom)->Color
    {
        let colors = .themeColors()
        if atom.flags.has(.Link) do
            return atom == .hotAtom ? colors.url_HotText : colors.url_Text
        if atom.colorIndex == 1 and .kind >= .AlertNote and .kind <= .AlertCaution
        {
            if .kind == .AlertWarning do
                return colors.embInfo_MessageText
            if .kind == .AlertCaution do
                return colors.embInfo_CriticalText
            return colors.embInfo_InformationText
        }

        switch atom.colorIndex
        {
        case 1:  return colors.richColor1
        case 2:  return colors.richColor2
        case 3:  return colors.richColor3
        default: return .kind == .Metadata ? colors.label_TextFaint : colors.label_Text
        }
    }

    mtd atomAt(point: Math.Point)->#null *InlineAtom
    {
        for &atom in .atoms where atom.visible and atom.flags.has(.Link) and atom.position.contains(point) do
            return atom
        return null
    }

    // Reports whether an atom is drawn as a shape rather than as its own glyphs.
    //
    // A bullet, a task box and a formula all stand for their text without being it, so a point
    // inside one names its start or its end and never a position between two of its bytes.
    private func isAtomOpaque(atom: const *InlineAtom)->bool
    {
        return atom.isMath or atom.flags.has(.ListBullet) or atom.flags.has(.ListUnchecked) or atom.flags.has(.ListChecked)
    }

    // Returns how wide the first `bytes` of one atom are drawn.
    private mtd prefixWidth(atom: const *InlineAtom, bytes: u64)->f32
    {
        let length = atomTextLength(atom)
        if bytes >= length do
            return atom.position.width
        if !bytes do
            return 0
        if atom.isBreak or atom.isSpace or isAtomOpaque(atom) do
            return atom.position.width
        return Painter.measureString(atom.text.toString()[0 until bytes], .font(atom)).width
    }

    // Returns the byte offset inside one atom nearest to `x`, measured from the atom's left edge.
    private mtd byteAtWidth(atom: const *InlineAtom, x: f32)->u64
    {
        let length = atomTextLength(atom)
        if atom.isBreak or atom.isSpace or isAtomOpaque(atom) do
            return x < atom.position.width * 0.5 ? 0 : length

        // The boundary the pointer is closest to wins, so a click on the left half of a glyph
        // puts the caret before it and one on the right half puts it after.
        let source = atom.text.toString()
        let font   = .font(atom)
        var scan   = 0'u64
        var before = 0'f32
        while scan < source.count
        {
            let {?, eat} = Utf8.decodeRune(source[scan to])
            let after    = Painter.measureString(source[0 until scan + eat], font).width
            if x < (before + after) * 0.5 do
                return scan
            before = after
            scan   += eat
        }

        return length
    }

    // Fills the reader's selection, one band per line of the view.
    //
    // A line is filled once, from the first selected glyph to the last, at the full height of the
    // line box: the band then runs unbroken through the spaces between words and through a change
    // of size or family inside a sentence, and the band of one line meets the band of the next
    // exactly, because consecutive line boxes abut.
    private mtd paintSelection(painter: *Painter)
    {
        let selection = .owner.selectionInInline(.orderIndex)
        if !selection.has do
            return

        for &line in .lines
        {
            var left  = Swag.F32.Max
            var right = Swag.F32.Min

            for index in line.first until line.last where .atoms[index].visible
            {
                let atom    = &.atoms[index]
                let atomEnd = atom.textStart + atomTextLength(atom)
                if selection.end <= atom.textStart or selection.start >= atomEnd do
                    continue

                left  = Math.min(left, atom.position.x + .prefixWidth(atom, Math.max(selection.start, atom.textStart) - atom.textStart))
                right = Math.max(right, atom.position.x + .prefixWidth(atom, Math.min(selection.end, atomEnd) - atom.textStart))
            }

            if right > left do
                painter.fillRect({left, line.top, right - left, line.height}, .themeColors().edit_SelectedBk)
        }
    }

    // Fills one exact search band and optionally reports its geometry in local coordinates.
    private mtd searchMatchRectLocal(result: *Math.Rectangle)->bool
    {
        if .searchStart == Swag.U64.Max or .searchEnd <= .searchStart do
            return false

        var found: bool
        for &line in .lines
        {
            var left  = Swag.F32.Max
            var right = Swag.F32.Min
            for index in line.first until line.last where .atoms[index].visible
            {
                let atom    = &.atoms[index]
                let atomEnd = atom.textStart + atomTextLength(atom)
                if .searchEnd <= atom.textStart or .searchStart >= atomEnd do
                    continue
                left  = Math.min(left, atom.position.x + .prefixWidth(atom, Math.max(.searchStart, atom.textStart) - atom.textStart))
                right = Math.max(right, atom.position.x + .prefixWidth(atom, Math.min(.searchEnd, atomEnd) - atom.textStart))
            }

            if right <= left do
                continue

            let rect = Math.Rectangle{left, line.top, right - left, line.height}
            if !found
            {
                result[] = rect
                found    = true
                continue
            }

            let unionRight = Math.max(result.right(), rect.right())
            let unionDown  = Math.max(result.bottom(), rect.bottom())
            result.x      = Math.min(result.x, rect.x)
            result.y      = Math.min(result.y, rect.y)
            result.width  = unionRight - result.x
            result.height = unionDown - result.y
        }

        return found
    }

    mtd searchMatchRect(result: *Math.Rectangle)->bool
    {
        var local: Math.Rectangle
        if !.searchMatchRectLocal(&local) do
            return false
        result[] = .localToSurface(local)
        return true
    }

    private mtd paintSearchHighlight(painter: *Painter)
    {
        var rect: Math.Rectangle
        if .searchMatchRectLocal(&rect) do
            painter.fillRect(rect, .themeColors().edit_SelectedBk)
    }

    // Returns the text offset nearest to a point in this view's coordinates.
    //
    // `distance` is zero when the point landed inside a rendered atom. A point beside a line
    // answers with that line's nearest atom, so a drag leaving the text keeps selecting the line
    // it travels along rather than jumping to another block.
    mtd textPositionAt(point: Math.Point)->{ offset: u64, distance: f32 }
    {
        var result: retval
        result.distance = Swag.F32.Max

        for &atom in .atoms where atom.visible
        {
            let frame = atom.position
            if frame.contains(point)
            {
                result.offset   = atom.textStart + .byteAtWidth(atom, point.x - frame.x)
                result.distance = 0
                return result
            }

            var dx = 0'f32
            if point.x < frame.x do
                dx = frame.x - point.x
            elif point.x > frame.right() do
                dx = point.x - frame.right()

            var dy = 0'f32
            if point.y < frame.y do
                dy = frame.y - point.y
            elif point.y > frame.bottom() do
                dy = point.y - frame.bottom()

            // An atom on the pointed line beats every atom of another line, however close.
            let score = dy * 4096 + dx
            if score >= result.distance do
                continue
            result.distance = score
            result.offset   = point.x <= frame.x ? atom.textStart : atom.textStart + atomTextLength(atom)
        }

        if result.distance == Swag.F32.Max do
            result.distance = 0
        return result
    }

    // Returns the run of the view's text one word around `offset` covers.
    mtd wordRangeAt(offset: u64)->{ start: u64, end: u64 }
    {
        var result: retval
        let source = .text()
        let length = source.length
        if !length do
            return result

        // One pass records where each rune starts and whether it belongs to a word; the word is
        // then the run of word runes around the rune holding the offset, or that rune alone.
        var starts: Array'u64
        var words:  Array'bool
        var scan = 0'u64
        while scan < length
        {
            let {value, eat} = Utf8.decodeRune(source.toString()[scan to])
            starts.add(scan)
            words.add(Unicode.isLetterOrDigit(value) or value == '_'rune)
            scan += eat
        }

        starts.add(scan)
        let position  = Math.min(offset, length - 1)
        var runeIndex = 0'u64
        for i in words.count where starts[i] <= position do
            runeIndex = i

        var lo = runeIndex
        var hi = runeIndex
        if words[runeIndex]
        {
            while lo and words[lo - 1] do
                lo -= 1
            while hi + 1 < words.count and words[hi + 1] do
                hi += 1
        }

        result.start = starts[lo]
        result.end   = starts[hi + 1]
        return result
    }

    mtd preferredHeight(width: f32)->f32 => .layout(width)

    // Width of the longest line when nothing wraps, used by tables to size columns from content.
    mtd naturalWidth()->f32
    {
        var widest = 0'f32
        var x      = 0'f32
        for &atom in .atoms
        {
            if atom.isBreak
            {
                widest = Math.max(widest, x)
                x      = 0
                continue
            }

            .measureAtom(atom)
            x += atom.position.width
        }

        return Math.max(widest, x)
    }

    func create(owner: *View, parent: *Wnd, source: string, kind: BlockKind)->*InlineView
    {
        let result = Wnd.create'InlineView(parent, "gui.markdown.inline")
        result.owner           = owner
        result.kind            = kind
        result.backgroundStyle = .View

        // Views are created in reading order — a block after the block before it, a table cell
        // after the cell to its left — so registering here is what puts the document in order.
        result.orderIndex = owner.registerInline(result)

        if kind >= .Heading1 and kind <= .Heading6 do
            result.horizontalAlignment = owner.documentStyle.headingAlignment
        elif kind == .Paragraph do
            result.horizontalAlignment = owner.documentStyle.paragraphAlignment
        result.parse(source)
        return result
    }
}

impl IWnd for InlineView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect    = .clientRect()
        let painter = evt.paintContext.painter
        discard .layout(rect.width)

        if .kind == .Code
        {
            painter.fillRect(rect, .themeColors().edit_Bk)
            painter.drawRect(rect, .themeColors().edit_Border, 1)
        }
        elif .kind == .Table or .kind == .Metadata or .kind == .TableOfContents do
            painter.fillRect(rect, .themeColors().edit_Bk)
        if .kind == .Quote or .kind >= .AlertNote and .kind <= .AlertCaution
        {
            var accent = .themeColors().richColor1
            if .kind >= .AlertNote and .kind <= .AlertImportant
            {
                accent = .themeColors().embInfo_InformationText
                painter.fillRect(rect, .themeColors().embInfo_InformationBk)
            }
            elif .kind == .AlertWarning
            {
                accent = .themeColors().embInfo_MessageText
                painter.fillRect(rect, .themeColors().embInfo_MessageBk)
            }
            elif .kind == .AlertCaution
            {
                accent = .themeColors().embInfo_CriticalText
                painter.fillRect(rect, .themeColors().embInfo_CriticalBk)
            }

            painter.fillRect({0, 8, 3, Math.max(rect.height - 16, 0)}, accent)
        }

        if .kind == .Rule
        {
            painter.fillRect({0, Math.floor(rect.vertCenter()), rect.width, 1}, .themeColors().edit_Border)
            return
        }

        // What a word carries under it comes first, then the reader's selection over all of it,
        // then the glyphs. Painting the selection per atom instead would break it at every word,
        // every space and every change of size, which reads as hatching rather than as a selection.
        for &atom in .atoms where atom.visible and (atom.flags.has(.Code) or atom.flags.has(.Highlight))
        {
            let ground     = atom.flags.has(.Highlight) ? .themeColors().edit_SelectedBk : .themeColors().edit_Bk
            var background = atom.position
            background.x      -= 2
            background.width  += 4
            background.y      -= 1
            background.height += 2
            painter.fillRect(background, ground)
        }

        .paintSearchHighlight(painter)

        .paintSelection(painter)

        for &atom in .atoms where atom.visible
        {
            let color = .color(atom)
            if atom.isMath
            {
                var options: MathLayoutOptions
                options.style = .Text
                painter.drawMath(atom.position.x, atom.position.y, &atom.expression, .theme().createDefaultFont(.fontSize()), color, options)
            }
            else
            {
                if atom.flags.has(.ListBullet)
                {
                    let font = .font(atom)
                    let size = Math.max(Math.round(font.height * 0.3), 4)
                    painter.fillRect({atom.position.x + (atom.position.width - size) * 0.5, atom.position.y + (font.height - size) * 0.5, size, size}, color)
                    continue
                }

                if atom.flags.has(.ListUnchecked) or atom.flags.has(.ListChecked)
                {
                    let font = .font(atom)
                    let size = Math.max(Math.round(font.height * 0.62), 8)
                    let x    = atom.position.x + (atom.position.width - size) * 0.5
                    let y    = atom.position.y + (font.height - size) * 0.5
                    painter.drawRect({x, y, size, size}, color, 1)
                    if atom.flags.has(.ListChecked)
                    {
                        let stroke = Math.max(Math.round(size * 0.14), 1)
                        painter.drawLine(x + size * 0.2, y + size * 0.52, x + size * 0.42, y + size * 0.74, color, stroke)
                        painter.drawLine(x + size * 0.42, y + size * 0.74, x + size * 0.82, y + size * 0.24, color, stroke)
                    }

                    continue
                }

                let decoration = atom.flags.has(.Strikeout) ? UnderlineStyle.Strikeout : (atom.flags.has(.Link) ? UnderlineStyle.Underline : UnderlineStyle.None)
                painter.drawString(atom.position.x, atom.position.y, atom.isSpace ? " " : atom.text.toString(), .font(atom), color, decoration)
            }
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Move:

            // A drag owns the pointer wherever it has travelled to, so the document resolves the
            // position rather than this view: the run under the pointer usually belongs to
            // another block by now.
            if .owner.isSelecting()
            {
                .owner.extendSelection(evt.surfacePos)
                .app().setFrameCursor(Cursor.from(.IBeam))
                return
            }

            let atom = .atomAt(.surfaceToLocal(evt.surfacePos))
            if atom != .hotAtom
            {
                .hotAtom = atom
                .invalidate()
            }

            if atom do
                .app().setFrameCursor(Cursor.from(.Hand))
            else do
                .app().setFrameCursor(Cursor.from(.IBeam))

        case .Leave:
            if .hotAtom
            {
                .hotAtom = null
                .invalidate()
            }

        case .Pressed where evt.button == .Left:
            let local = .surfaceToLocal(evt.surfacePos)
            let atom  = .atomAt(local)
            if atom and !atom!.target.isEmpty()
            {
                .owner.sigLinkActivated.call(.owner, atom!.target.toString())
                return
            }

            .owner.beginSelection(me, .textPositionAt(local).offset)
            .captureMouse()

        case .Released where evt.button == .Left:
            if !.owner.isSelecting()
            {
                evt.accepted = false
                return
            }

            .owner.endSelection()
            if .mouseCapture() == cast(*Wnd) me do
                .releaseMouse()

        case .DoubleClick where evt.button == .Left:
            .owner.selectWordAt(me, .textPositionAt(.surfaceToLocal(evt.surfacePos)).offset)

        case .Pressed where evt.button == .Right:
            .owner.showContextMenu(evt.surfacePos)

        default:
            evt.accepted = false
        }
    }
}

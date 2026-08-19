#global internal
#global namespace Markdown

using Core, Pixel

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

    owner:        *View = undefined
    kind:         BlockKind
    atoms:        Array'InlineAtom
    layoutWidth:  f32
    layoutHeight: f32
    hotAtom:      #null *InlineAtom
    horizontalAlignment = StringHorzAlignment.Left
}

impl InlineView
{
    mtd clearSearchHighlight()
    {
        var changed: bool
        for &atom in .atoms where atom.searchHit
        {
            atom.searchHit = false
            changed        = true
        }

        if changed do
            .invalidate()
    }

    // Highlights every rendered atom touched by a case-insensitive match, for all matches.
    mtd highlightText(text: string)->bool
    {
        .clearSearchHighlight()
        var source: String
        for &atom in .atoms
        {
            if atom.isBreak do
                source += "\n"
            elif atom.isSpace do
                source += " "
            elif !atom.isMath do
                source += atom.text
        }

        var found      = false
        var searchFrom = 0'u64
        while true
        {
            let match = Utf8.indexOf(source.toString(), text, searchFrom, .Latin1NoCase)
            if match == Swag.U64.Max do
                break

            found = true
            let matchEnd = match + @countof(text)
            var start    = 0'u64
            for &atom in .atoms
            {
                let length = atom.isBreak or atom.isSpace ? 1 : (atom.isMath ? 0 : @countof(atom.text))
                let end    = start + length
                if end > match and start < matchEnd do
                    atom.searchHit = true
                start = end
            }

            searchFrom = match + Math.max(@countof(text), 1)
        }

        if !found do
            return false
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
        while index < @countof(text)
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

        if start < @countof(text) do
            .appendTextAtom(text[start to], state)
    }

    mtd appendText(text: string, state: InlineState)
    {
        var start = 0'u64
        var index = 0'u64
        while index <= @countof(text)
        {
            let atEnd = index == @countof(text)
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
            if text[index] == '\r' and whitespaceEnd < @countof(text) and text[whitespaceEnd] == '\n' do
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

        var atom: InlineAtom
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

        while index < @countof(text)
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

        if textStart < @countof(text) do
            .appendText(text[textStart to], state)
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

    mtd finishLine(first, last: u64, top, left, right: f32)->f32
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
        for index in first until last where .atoms[index].visible
        {
            .atoms[index].position.x += shift
            .atoms[index].position.y = top + offset + ascent - .atoms[index].ascent
            if .atoms[index].flags.has(.Superscript) do
                .atoms[index].position.y -= ascent * 0.28
            elif .atoms[index].flags.has(.Subscript) do
                .atoms[index].position.y += descent * 0.55
        }

        return line
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
                y                += .finishLine(first, index, y, lineLeft, right)
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
                y        += .finishLine(first, index, y, lineLeft, right)
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
            y += .finishLine(first, .atoms.count, y, lineLeft, right)
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
        if kind >= .Heading1 and kind <= .Heading6 do
            result.horizontalAlignment = owner.documentStyle.headingAlignment
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

        for &atom in .atoms where atom.visible
        {
            let color = .color(atom)
            if atom.flags.has(.Code) or atom.flags.has(.Highlight) or atom.searchHit
            {
                let ground     = atom.flags.has(.Highlight) or atom.searchHit ? .themeColors().edit_SelectedBk : .themeColors().edit_Bk
                var background = atom.position
                background.x      -= 2
                background.width  += 4
                background.y      -= 1
                background.height += 2
                painter.fillRect(background, ground)
            }

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
            let atom = .atomAt(.surfaceToLocal(evt.surfacePos))
            if atom != .hotAtom
            {
                .hotAtom = atom
                .invalidate()
            }

            if atom do
                .app().setFrameCursor(Cursor.from(.Hand))

        case .Leave:
            if .hotAtom
            {
                .hotAtom = null
                .invalidate()
            }

        case .Pressed where evt.button == .Left:
            let atom = .atomAt(.surfaceToLocal(evt.surfacePos))
            if atom and !atom!.target.isEmpty() do
                .owner.sigLinkActivated.call(.owner, atom!.target.toString())
            else do
                evt.accepted = false

        default:
            evt.accepted = false
        }
    }
}

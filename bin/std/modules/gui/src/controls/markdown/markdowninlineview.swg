#global internal

using Core, Pixel

#[Swag.EnumFlags]
private enum MarkdownInlineFlags
{
    None      = 0
    Bold
    Italic
    Strikeout
    Code
    Highlight
    Link
    Subscript
    Superscript
}

private struct MarkdownInlineAtom
{
    text:       String
    target:     String
    expression: MathExpression
    position:   Math.Rectangle
    ascent:     f32
    descent:    f32
    colorIndex: u32
    flags:      MarkdownInlineFlags
    isMath:     bool
    isSpace:    bool
    isBreak:    bool
    visible:    bool
}

private struct MarkdownInlineState
{
    bold:      u32
    italic:    u32
    strikeout: u32
    code:      u32
    highlight: u32
    link:      u32
    subscript: u32
    superscript: u32
    colorIndex: u32
}

private impl MarkdownInlineState
{
    mtd const flags()->MarkdownInlineFlags
    {
        var result = MarkdownInlineFlags.None
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
        return result
    }
}

#[Swag.Opaque, Swag.NoDoc]
public struct MarkdownInlineView
{
    using wnd: Wnd

    owner: *MarkdownView = undefined
    kind:  MarkdownBlockKind
    atoms: Array'MarkdownInlineAtom
    layoutWidth:  f32
    layoutHeight: f32
    hotAtom:      #null *MarkdownInlineAtom
    horizontalAlignment = StringHorzAlignment.Left
}

internal impl MarkdownInlineView
{
    mtd appendTextAtom(text: string, state: MarkdownInlineState, isSpace = false, isBreak = false)
    {
        var atom: MarkdownInlineAtom
        atom.text       = text
        atom.flags      = state.flags()
        atom.colorIndex = state.colorIndex
        atom.isSpace    = isSpace
        atom.isBreak    = isBreak
        .atoms.add(#move atom)
    }

    mtd appendWord(text: string, state: MarkdownInlineState)
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

    mtd appendText(text: string, state: MarkdownInlineState)
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

    mtd appendMath(source: string, state: MarkdownInlineState)
    {
        let expression = catch MathExpression.parse(source) as parseError
        if parseError != null
        {
            .appendText(source, state)
            return
        }

        var atom: MarkdownInlineAtom
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
        var state: MarkdownInlineState
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
            case Utf8.startsWith(remaining, "<b>"):  state.bold += 1; eaten = 3
            case Utf8.startsWith(remaining, "</b>"): state.bold = state.bold ? state.bold - 1 : 0; eaten = 4
            case Utf8.startsWith(remaining, "<i>"):  state.italic += 1; eaten = 3
            case Utf8.startsWith(remaining, "</i>"): state.italic = state.italic ? state.italic - 1 : 0; eaten = 4
            case Utf8.startsWith(remaining, "<s>"):  state.strikeout += 1; eaten = 3
            case Utf8.startsWith(remaining, "</s>"): state.strikeout = state.strikeout ? state.strikeout - 1 : 0; eaten = 4
            case Utf8.startsWith(remaining, "<c>"):  state.code += 1; eaten = 3
            case Utf8.startsWith(remaining, "</c>"): state.code = state.code ? state.code - 1 : 0; eaten = 4
            case Utf8.startsWith(remaining, "<h>"):  state.highlight += 1; eaten = 3
            case Utf8.startsWith(remaining, "</h>"): state.highlight = state.highlight ? state.highlight - 1 : 0; eaten = 4
            case Utf8.startsWith(remaining, "<sub>"):  state.subscript += 1; eaten = 5
            case Utf8.startsWith(remaining, "</sub>"): state.subscript = state.subscript ? state.subscript - 1 : 0; eaten = 6
            case Utf8.startsWith(remaining, "<sup>"):  state.superscript += 1; eaten = 5
            case Utf8.startsWith(remaining, "</sup>"): state.superscript = state.superscript ? state.superscript - 1 : 0; eaten = 6

            case Utf8.startsWith(remaining, "<p1>"): state.colorIndex = 1; eaten = 4
            case Utf8.startsWith(remaining, "<p2>"): state.colorIndex = 2; eaten = 4
            case Utf8.startsWith(remaining, "<p3>"): state.colorIndex = 3; eaten = 4
            case Utf8.startsWith(remaining, "</p>"): state.colorIndex = 0; eaten = 4

            case Utf8.startsWith(remaining, "<a>"):
                state.link += 1
                linkStart = .atoms.count
                eaten     = 3

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
        case .Code:                                         return {18, 14, 18, 14}
        case .Table:                                        return {16, 12, 16, 12}
        case .Quote, .AlertNote, .AlertTip, .AlertImportant,
             .AlertWarning, .AlertCaution:                   return {18, 10, 10, 10}
        case .Metadata:                                     return {12, 8, 12, 8}
        case .TableOfContents:                              return {18, 12, 18, 12}
        case .Footnote:                                     return {0, 4, 0, 4}
        default:        return {0, 2, 0, 2}
        }
    }

    mtd fontSize()->u32
    {
        switch .kind
        {
        case .Heading1:          return 32
        case .Heading2:          return 25
        case .Heading3:          return 21
        case .Heading4:          return 18
        case .Heading5, .Heading6: return 16
        case .Code, .Table:      return .owner.documentStyle.codeFontSize
        case .Metadata:          return Math.max(.owner.documentStyle.codeFontSize - 1, 8)
        case .Footnote:          return Math.max(.owner.documentStyle.bodyFontSize - 2, 8)
        default:                 return .owner.documentStyle.bodyFontSize
        }
    }

    mtd fontStyle(flags: MarkdownInlineFlags)->FontFamilyStyle
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

    mtd font(atom: const *MarkdownInlineAtom)->*Font
    {
        let style = .fontStyle(atom.flags)
        let size  = atom.flags.has(.Subscript) or atom.flags.has(.Superscript) ? Math.max(.fontSize() * 3 / 4, 8) : .fontSize()
        if atom.flags.has(.Code) or .kind == .Code or .kind == .Table or .kind == .Metadata do
            return .theme().createDefaultFontFS(size, style)
        return .theme().createDefaultFont(size, style)
    }

    mtd measureAtom(atom: *MarkdownInlineAtom)
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
        let text = atom.isSpace ? " " : atom.text.toString()
        atom.position.width  = Painter.measureString(text, font).width
        atom.position.height = font.height
        atom.ascent          = font.ascent
        atom.descent         = -font.descent
    }

    mtd finishLine(first, last: u64, top, left, right: f32)->f32
    {
        if first >= last do
            return .theme().createDefaultFont(.fontSize()).height * 1.45

        var ascent:  f32
        var descent: f32
        for index in first until last where .atoms[index].visible
        {
            ascent  = Math.max(ascent, .atoms[index].ascent)
            descent = Math.max(descent, .atoms[index].descent)
        }

        let natural = ascent + descent
        let line     = Math.max(natural, .theme().createDefaultFont(.fontSize()).height * 1.45)
        let offset   = (line - natural) * 0.5
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

        let inset = .padding()
        let left  = inset.x
        let right = Math.max(width - inset.z, left + 1)
        var x     = left
        var y     = inset.y
        var first = 0'u64

        for &atom, index in .atoms
        {
            atom.visible = false
            .measureAtom(atom)
            if atom.isBreak
            {
                y     += .finishLine(first, index, y, left, right)
                x      = left
                first  = index + 1
                continue
            }

            if atom.isSpace and x == left do
                continue
            if !atom.isSpace and x > left and x + atom.position.width > right
            {
                y     += .finishLine(first, index, y, left, right)
                x      = left
                first  = index
            }

            atom.visible    = true
            atom.position.x = x
            x              += atom.position.width
        }

        y += .finishLine(first, .atoms.count, y, left, right)
        .layoutWidth  = width
        .layoutHeight = y + inset.w
        return .layoutHeight
    }

    mtd color(atom: const *MarkdownInlineAtom)->Color
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

    mtd atomAt(point: Math.Point)->#null *MarkdownInlineAtom
    {
        for &atom in .atoms where atom.visible and atom.flags.has(.Link) and atom.position.contains(point) do
            return atom
        return null
    }

    mtd preferredHeight(width: f32)->f32 => .layout(width)

    func create(owner: *MarkdownView, parent: *Wnd, source: string, kind: MarkdownBlockKind)->*MarkdownInlineView
    {
        let result = Wnd.create'MarkdownInlineView(parent, "gui.markdown.inline")
        result.owner           = owner
        result.kind            = kind
        result.backgroundStyle = .View
        result.parse(source)
        return result
    }
}

internal impl IWnd for MarkdownInlineView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect    = .clientRect()
        let painter = evt.paintContext.painter
        discard .layout(rect.width)

        if .kind == .Code or .kind == .Table or .kind == .Metadata or .kind == .TableOfContents do
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
            if atom.flags.has(.Code) or atom.flags.has(.Highlight)
            {
                let ground = atom.flags.has(.Highlight) ? .themeColors().edit_SelectedBk : .themeColors().edit_Bk
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

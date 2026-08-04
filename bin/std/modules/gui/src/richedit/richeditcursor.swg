#global public

using Core, Pixel

// Identifies one rune position and preferred horizontal coordinate in a rich document.
struct RichEditCursor
{
    lineIndex:     u64     // Index of line.
    charPosInLine: u64     // Char pos in line associated with this value.
}

impl RichEditCtrl
{
    // Returns text draw info.
    mtd computeTextDrawInfo(styleIdx: RichEditStyleRef)->TextDrawInfo
    {
        let fontR = .font().getFont(.styles[styleIdx].fontMode)
        if fontR do
            return Painter.computeTextDrawInfo(nnFont(fontR), 1.0, .deviceScale())
        return {}
    }

    // Returns line height.
    mtd lineHeight()->f32
    {
        let fontR = .font().getFont(.styles[0].fontMode)
        if !fontR do
            return 0

        let font = nnFont(fontR)
        return Math.max(font.height + .lineSpacing, 1.0)
    }

    // Advances the cached horizontal position by one rune.
    mtd advanceRuneX(line: #null *RichEditLine, i: u64, x: f32)->f32
    {
        if !line do
            return x
        if line.chars[i] == '\t' do
            return x + .tabAdvance(cast(s32) x)

        let styleIdx = line.styles[i]
        let info     = .computeTextDrawInfo(styleIdx)
        let drawFont = info.drawFont
        if !drawFont do
            return x

        let glyphIndex = drawFont.glyphIndex(line.chars[i])
        let desc       = drawFont.getGlyphDescByIndex(glyphIndex)

        let hasPrevRune = i and line.chars[i - 1] != '\t' and line.styles[i - 1] == styleIdx

        var offsetX = 0'f32
        if hasPrevRune
        {
            let prevGlyphIndex = drawFont.glyphIndex(line.chars[i - 1])
            offsetX = drawFont.kerning(prevGlyphIndex, glyphIndex)
        }

        let step = Painter.advanceTextX(x, offsetX, desc.advanceX, info, !hasPrevRune)
        return step.rightX
    }

    // Returns rune size.
    mtd runeSize(line: #null *RichEditLine, i: u64, x: f32)->Math.Point
    {
        var size: retval
        size.x = .advanceRuneX(line, i, x) - x
        size.y = .lineHeight()
        return size
    }

    // Returns cursor display pos.
    mtd cursorDisplayPosition(cp: RichEditCursor)->Math.Point
    {
        var result: retval

        let lineIndex = Math.min(cp.lineIndex, .lines.count - 1)
        let line      = notnull .lines[lineIndex]
        result.y = line.drawingRect.bottom()

        result.x = .leftMargin()
        for [i] in Math.min(cp.charPosInLine, line.length()) do
            result.x = .advanceRuneX(line, i, result.x)

        return result
    }

    // Returns tab offset.
    mtd tabAdvance(x: s32, numBlanks: #null *s32 = null)->s32
    {
        let of        = cast(s32) (x - .leftMargin())
        let fontR     = .font().getFont(.styles[0].fontMode)
        let font      = nnFont(fontR)
        let sizeBlank = Painter.measureRune(' ', font)
        let sx        = cast(s32) (sizeBlank.x * .tabSize)

        var tab = (of / sx) * sx
        tab = of - tab
        if numBlanks do
            dref numBlanks = cast(s32) (tab / sizeBlank.x)

        tab = sx - tab
        return tab
    }

    // Returns x extent.
    mtd xGlyphSize()->Math.Point
    {
        let fontR = .font().getFont(.styles[0].fontMode)
        if !fontR do
            return {}

        let font   = nnFont(fontR)
        var result = Painter.measureRune('X', font)
        result.y = .lineHeight()
        return result
    }

    // Returns caret pos.
    mtd caretRect(cp: RichEditCursor)->Math.Rectangle
    {
        let pt   = .cursorDisplayPosition(cp)
        let size = .xGlyphSize()

        var result: retval
        result.x      = pt.x
        result.y      = .overwriteMode ? pt.y - 2 : pt.y - size.y
        result.width  = .overwriteMode ? size.x : 2
        result.height = .overwriteMode ? 2 : size.y
        return result
    }

    private mtd ensureCaretIsVisibleInternal(center: bool)
    {
        .checkSelection()
        .ensureCursorIsVisible(.cursorPos, center)
        .invalidate()
    }

    // Scrolls just enough to reveal the active caret.
    mtd ensureCaretIsVisible(center = false)
    {
        .forceCaretVisible       = true
        .forceCaretVisibleCenter = center
        .ensureCaretIsVisibleInternal(center)
    }

    // Scrolls to reveal a cursor, optionally centering it in the viewport.
    mtd ensureCursorIsVisible(cp: RichEditCursor, center: bool)
    {
        let size   = .xGlyphSize()
        let decalx = size.x * 10

        let clientRect = .edView.clientRect()

        let pos = .cursorDisplayPosition(cp)
        var sx  = .edView.scrollPos.x
        var sy  = .edView.scrollPos.y

        // Need to change horz scroll
        if pos.x < sx + .leftMargin() do
            sx = pos.x - decalx
        elif pos.x + size.x > sx + clientRect.width - .rightMargin() do
            sx = pos.x + decalx - clientRect.width - .rightMargin()

        // Need to change vertical scroll
        if pos.y - size.y < sy
        {
            sy = pos.y - size.y
            if center do
                sy -= clientRect.height / 2
        }
        elif pos.y > sy + clientRect.height
        {
            sy = pos.y - clientRect.height
            if center do
                sy += clientRect.height / 2
        }

        if sy != .edView.scrollPos.y do
            .dirtyFirstLineView = true

        .scrollWnd.setScrollPos(sx, sy)
    }

    // Returns cursor pos from point.
    mtd cursorAt(pt: Math.Point)->RichEditCursor
    {
        var cp: retval

        var found = false

        // Before the first visible line
        if pt.y < .lines[0]!.drawingRect.y
        {
            cp.lineIndex     = 0
            cp.charPosInLine = 0
            found            = true
        }
        else
        {
            var i  = 0'u64
            var pi = Swag.U64.Max
            while i != pi and i != .lines.count
            {
                let line  = notnull .lines[i]
                let count = line.length()
                var rect  = line.drawingRect

                // Before the first character
                if pt.y >= rect.y and pt.y < rect.bottom() and (pt.x < rect.x or !count)
                {
                    found            = true
                    cp.lineIndex     = i
                    cp.charPosInLine = 0
                    break
                }

                if count
                {
                    for [j] in count
                    {
                        let size = .runeSize(line, j, rect.x)
                        rect.width = size.x
                        if rect.contains(pt)
                        {
                            cp.lineIndex     = i
                            cp.charPosInLine = j
                            if pt.x >= rect.horzCenter() do
                                cp.charPosInLine += 1
                            found = true
                            break
                        }

                        rect.x = rect.right()
                    }
                }

                if found do
                    break

                // At the end of line
                if pt.y >= rect.y and pt.y < rect.bottom() and pt.x >= rect.x
                {
                    cp.lineIndex     = i
                    cp.charPosInLine = count
                    found            = true
                    break
                }

                pi = i
                i  += 1
            }
        }

        // At the end of file
        if !found
        {
            cp.lineIndex     = .lines.count - 1
            cp.charPosInLine = .lines[cp.lineIndex]!.length()
        }

        // Check visibility
        if !.lines[cp.lineIndex]!.isVisible() do
            .moveCursorDown(&cp)
        if !.lines[cp.lineIndex]!.isVisible() do
            .moveCursorUp(&cp)

        return cp
    }

    // Sets cursor pos.
    mtd setCursorPos(cp: RichEditCursor)
    {
        .cursorPos = cp
    }

    // Moves a cursor one rune to the left and reports whether it changed.
    #[Swag.Discardable]
    mtd moveCursorLeft(cp: *RichEditCursor)->bool
    {
        if cp.charPosInLine == 0
        {
            let prev = .previousVisibleLine(cp.lineIndex)
            if prev == cp.lineIndex do
                return false
            cp.lineIndex     = prev
            cp.charPosInLine = .lines[prev]!.length()
        }
        else
        {
            cp.charPosInLine -= 1
        }

        return true
    }

    // Moves a cursor one rune to the right and reports whether it changed.
    #[Swag.Discardable]
    mtd moveCursorRight(cp: *RichEditCursor)->bool
    {
        if cp.charPosInLine == .lines[cp.lineIndex]!.length()
        {
            let next = .nextVisibleLine(cp.lineIndex)
            if next == cp.lineIndex do
                return false
            cp.lineIndex     = next
            cp.charPosInLine = 0
        }
        else
        {
            cp.charPosInLine += 1
        }

        return true
    }

    // Moves a cursor to the closest position on the preceding visual line.
    #[Swag.Discardable]
    mtd moveCursorUp(cp: *RichEditCursor)->bool
    {
        let pt = .cursorDisplayPosition(cp)
        return .moveCursorUp(cp, pt)
    }

    // Moves a cursor to the closest position on the following visual line.
    #[Swag.Discardable]
    private mtd moveCursorUp(cp: *RichEditCursor, posPrev: Math.Point)->bool
    {
        let prev = .previousVisibleLine(cp.lineIndex)
        if prev == cp.lineIndex do
            return false

        cp.lineIndex = prev
        var line = notnull .lines[cp.lineIndex]
        cp.charPosInLine = Math.min(line.length(), cp.charPosInLine)
        var posNew = .cursorDisplayPosition(cp)

        if posPrev.x == posNew.x do
            return true
        if posNew.x < posPrev.x
        {
            while posNew.x < posPrev.x and cp.charPosInLine < line.length()
            {
                posNew.x         += .runeSize(line, cp.charPosInLine, posNew.x).x
                cp.charPosInLine += 1
            }
        }
        else
        {
            line = notnull .lines[cp.lineIndex]
            while posNew.x > posPrev.x and cp.charPosInLine
            {
                cp.charPosInLine -= 1
                posNew.x         -= .runeSize(line, cp.charPosInLine, posNew.x).x
            }
        }

        return true
    }

    #[Swag.Discardable]
    // Moves the cursor one visual line downward.
    mtd moveCursorDown(cp: *RichEditCursor)->bool
    {
        let pt = .cursorDisplayPosition(cp)
        return .moveCursorDown(cp, pt)
    }

    #[Swag.Discardable]
    private mtd moveCursorDown(cp: *RichEditCursor, posPrev: Math.Point)->bool
    {
        let next = .nextVisibleLine(cp.lineIndex)
        if next == cp.lineIndex do
            return false

        cp.lineIndex = next
        var line = notnull .lines[cp.lineIndex]
        cp.charPosInLine = Math.min(line.length(), cp.charPosInLine)
        var posNew = .cursorDisplayPosition(cp)

        if posPrev.x == posNew.x do
            return true
        if posNew.x < posPrev.x
        {
            while posNew.x < posPrev.x and cp.charPosInLine < line.length()
            {
                posNew.x         += .runeSize(line, cp.charPosInLine, posNew.x).x
                cp.charPosInLine += 1
            }
        }
        else
        {
            line = notnull .lines[cp.lineIndex]
            while posNew.x > posPrev.x and cp.charPosInLine
            {
                cp.charPosInLine -= 1
                posNew.x         -= .runeSize(line, cp.charPosInLine, posNew.x).x
            }
        }

        return true
    }

    // Moves a cursor to the start of its logical line.
    mtd moveCursorStartLine(cp: *RichEditCursor)
    {
        let line = notnull .lines[cp.lineIndex]
        var i    = cast(s32) cp.charPosInLine

        var firstBlank: bool
        if !i
        {
            firstBlank = true
        }
        else
        {
            firstBlank = false
            i          -= 1
            while i >= 0
            {
                if !Unicode.isSpace(line.chars[i])
                {
                    firstBlank = true
                    break
                }

                i -= 1
            }
        }

        cp.charPosInLine = 0
        if firstBlank
        {
            while cp.charPosInLine < line.length() and Unicode.isSpace(line.chars[cp.charPosInLine]) do
                cp.charPosInLine += 1
        }
    }

    // Moves a cursor to the end of its logical line.
    mtd moveCursorEndLine(cp: *RichEditCursor)
    {
        cp.charPosInLine = .lines[cp.lineIndex]!.length()
    }

    // Moves a cursor to the start of the document.
    mtd moveCursorStartFile(cp: *RichEditCursor)
    {
        cp.lineIndex     = .firstVisibleLine()
        cp.charPosInLine = 0
    }

    // Moves a cursor to the end of the document.
    mtd moveCursorEndFile(cp: *RichEditCursor)
    {
        if .lines.isEmpty()
        {
            cp.lineIndex, cp.charPosInLine = 0
            return
        }

        cp.lineIndex     = .lastVisibleLine()
        cp.charPosInLine = .lines[cp.lineIndex]!.length()
    }

    // Moves a cursor upward by one viewport page.
    mtd moveCursorPageUp(cp: *RichEditCursor)
    {
        let client = .edView.clientRect()
        var count  = cast(s64) (client.height / .xGlyphSize().y)
        while count
        {
            if cp.lineIndex == 0 do
                break
            .moveCursorUp(cp)
            count -= 1
        }
    }

    // Moves a cursor downward by one viewport page.
    mtd moveCursorPageDown(cp: *RichEditCursor)
    {
        let client = .edView.clientRect()
        var count  = cast(s64) (client.height / .xGlyphSize().y)
        while count
        {
            if cp.lineIndex == .lines.count - 1 do
                break
            .moveCursorDown(cp)
            count -= 1
        }
    }

    // Moves a cursor to the preceding word boundary.
    mtd moveCursorWordLeft(cp: *RichEditCursor)
    {
        var line = notnull .lines[cp.lineIndex]
        if cp.charPosInLine == 0
        {
            .moveCursorLeft(cp)
            return
        }

        if Unicode.isSpace(line.chars[cp.charPosInLine - 1])
        {
            if !.moveCursorLeft(cp) do
                return
            line = notnull .lines[cp.lineIndex]
            while cp.charPosInLine != 0 and Unicode.isSpace(line.chars[cp.charPosInLine - 1])
            {
                if !.moveCursorLeft(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }

            if !cp.charPosInLine do
                return
        }

        if isWord(line.chars[cp.charPosInLine - 1])
        {
            while cp.charPosInLine != 0 and isWord(line.chars[cp.charPosInLine - 1])
            {
                if !.moveCursorLeft(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }
        }
        elif zapWordChar(line.chars[cp.charPosInLine - 1])
        {
            while cp.charPosInLine != 0 and zapWordChar(line.chars[cp.charPosInLine - 1])
            {
                if !.moveCursorLeft(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }
        }
        else
        {
            .moveCursorLeft(cp)
        }
    }

    // Moves a cursor to the following word boundary, optionally including trailing space.
    mtd moveCursorWordRight(cp: *RichEditCursor, withSpace: bool)
    {
        var line = notnull .lines[cp.lineIndex]
        if cp.charPosInLine == line.length() or Unicode.isSpace(line.chars[cp.charPosInLine])
        {
            if !.moveCursorRight(cp) do
                return
            line = notnull .lines[cp.lineIndex]
            while cp.charPosInLine != line.length() and Unicode.isSpace(line.chars[cp.charPosInLine])
            {
                if !.moveCursorRight(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }
        }
        elif isWord(line.chars[cp.charPosInLine])
        {
            while cp.charPosInLine != line.length() and isWord(line.chars[cp.charPosInLine])
            {
                if !.moveCursorRight(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }

            if withSpace
            {
                while cp.charPosInLine != line.length() and Unicode.isSpace(line.chars[cp.charPosInLine])
                {
                    if !.moveCursorRight(cp) do
                        return
                    line = notnull .lines[cp.lineIndex]
                }
            }
        }
        elif zapWordChar(line.chars[cp.charPosInLine])
        {
            while cp.charPosInLine != line.length() and zapWordChar(line.chars[cp.charPosInLine])
            {
                if !.moveCursorRight(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }

            while cp.charPosInLine != line.length() and Unicode.isSpace(line.chars[cp.charPosInLine])
            {
                if !.moveCursorRight(cp) do
                    return
                line = notnull .lines[cp.lineIndex]
            }
        }
        else
        {
            .moveCursorRight(cp)
        }
    }
}

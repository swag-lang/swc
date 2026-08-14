using Core, Pixel

// Paints a [[Gui.RichEditCtrl]] document and handles its direct input gestures.
#[Swag.Opaque]
public struct RichEditView
{
    public using wnd: Wnd     // Embedded wnd state.

    // The control this view paints for, and the transient state of one editing gesture.
    internal
    {
        ed:               #null *RichEditCtrl     // Control owning the document.
        visibleCaret:     bool                    // Whether the blinking caret is currently drawn.
        selMode:          bool                    // Whether a mouse selection gesture is in progress.
        timerCaret:       #null *Timer            // Timer driving the caret blink.
        firstLineSelMode: u64                     // Line the current selection gesture started on.
        lastClientRect:   Math.Rectangle          // Client rectangle of the last layout.
    }
}

impl IWnd for RichEditView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .timerCaret
        {
            let srf = .surface!
            srf.app.removeTimer(.timerCaret)
            .timerCaret = null
        }

        if .selMode
        {
            .selMode = false
            if .mouseCapture() == me do
                .releaseMouse()
        }

        if .focusedWindow() == me
        {
            let srf = .surface!
            srf.app.keyboardFocusWnd = null
        }

        .ed = null
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        let ed = .ed
        if ed and ed.flags & .WordWrap do
            ed.recomputeScroll = true
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let edn = .ed!
        evt.accepted = false
        switch evt.kind
        {
        case .DoubleClick:
            if evt.button == .Left
            {
                edn.selectWord()
                evt.accepted = true
            }

        case .Pressed:
            if evt.button == .Left
            {
                evt.accepted = true
                let pt = .surfaceToLocal(evt.surfacePos) + .scrollPos
                let cp = edn.cursorAt(pt)
                .firstLineSelMode = cp.lineIndex
                edn.setCursorPos(cp)
                if !(evt.modifiers & .Shift) do
                    edn.selBeg = cp
                .selMode = true
                edn.setRectangularSelection(evt.modifiers & .Alt ? true : false)
                edn.ensureCaretIsVisible()
                .captureMouse()
            }

        case .Released:
            if .selMode
            {
                evt.accepted = true
                .selMode     = false
                .releaseMouse()
            }

        case .Move:
            if .selMode
            {
                evt.accepted = true
                let pt = .surfaceToLocal(evt.surfacePos) + .scrollPos
                let cp = edn.cursorAt(pt)
                if edn.cursorPos.lineIndex != cp.lineIndex or edn.cursorPos.charPosInLine != cp.charPosInLine
                {
                    if edn.hasSelRect
                    {
                        if cp.charPosInLine >= edn.selBeg.charPosInLine do
                            edn.setCursorPos(cp)
                        edn.checkSelection()
                    }
                    else
                    {
                        edn.setCursorPos(cp)
                    }

                    edn.ensureCaretIsVisible()
                }
            }
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        let edn = .ed!
        if evt.kind == .Pressed
        {
            // Lose focus with escape or enter
            if edn.flags & .AutoLoseFocus
            {
                if evt.key == .Escape or (evt.key == .Enter and evt.modifiers.equals(.None))
                {
                    evt.accepted = false
                    .topView().setFocus()
                    return
                }
            }

            evt.accepted = true
            edn.keyPressed(evt.key, evt.modifiers)
            .forceVisibleCaret()
        }
        elif evt.kind == .Character
        {
            evt.accepted = true
            edn.charPressed(evt.key, evt.character, evt.modifiers)
            .forceVisibleCaret()
        }
    }

    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        switch evt.kind
        {
        case .Gained:
            .timerCaret   = .surface!.app.addTimer(500'ms, me)
            .visibleCaret = true
            .invalidate()

        case .Lost:
            let srf = .surface!
            srf.app.removeTimer(.timerCaret!)
            .timerCaret   = null
            .visibleCaret = false
            .invalidate()
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        .visibleCaret = !.visibleCaret
        .invalidate()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let edn     = .ed!
        let painter = evt.paintContext.painter
        let colors  = .themeColors()

        let marginLeft = edn.leftMargin()
        var x          = 0'f32
        var y          = 0'f32
        let size       = edn.xGlyphSize()

        // Force visible caret
        if edn.forceCaretVisible do
            edn.ensureCaretIsVisibleInternal(edn.forceCaretVisibleCenter)

        // Start to the first visible line, if known
        var i: u64
        if edn.dirtyFirstLineView or edn.recomputeScroll
        {
            i = 0
            edn.firstVisibleLineView = Swag.U64.Max
        }
        else
        {
            i = edn.firstVisibleLineView
            y = edn.lines[i]!.drawingRect.y
        }

        if edn.recomputeScroll do
            edn.countVisibleLines = 0
        edn.dirtyFirstLineView = false

        let clientRect  = .clientRect()
        let firstHidden = true
        var maxx        = 0'f32

        let sizeChanged = .lastClientRect != clientRect
        .lastClientRect = clientRect

        // All lines
        while i < edn.lines.count
        {
            // Is the line visible ?
            var bvis = true
            if y + size.y < .scrollPos.y or y - .scrollPos.y > clientRect.bottom() do
                bvis = false

            // Store the first visible line index
            if bvis and edn.firstVisibleLineView == Swag.U64.Max and (edn.lines[i]!.isVisible() or firstHidden) do
                edn.firstVisibleLineView = i

            if edn.recomputeScroll do
                edn.countVisibleLines += 1
            edn.lastVisibleLineView = i

            let l = edn.lines[i]!

            l.drawingRect.x      = marginLeft
            l.drawingRect.y      = y
            l.drawingRect.width  = x - marginLeft
            l.drawingRect.height = size.y

            // Current line
            if bvis and edn.isSelectionEmpty() and i == edn.cursorPos.lineIndex and edn.flags & .CurLineBorder
            {
                var fullRect = l.drawingRect
                fullRect.y -= .scrollPos.y
                fullRect.setRight(clientRect.right() - edn.rightMargin())
                fullRect.inflate(-1)
                painter.drawRect(fullRect, colors.richEdit_CurLineBorder, 1)
            }

            // Lex the line
            if !l.wordWrap and (l.dirtyStyle or sizeChanged or edn.recomputeScroll)
            {
                edn.unwrap(i)

                if edn.lexer
                {
                    let prevLine = i ? edn.lines[i - 1] : null
                    let nextLine = i != edn.lines.count - 1 ? edn.lines[i + 1] : null
                    edn.lexer.compute(prevLine, l, nextLine)
                }

                edn.wrap(i)
                l.dirtyStyle = false
            }

            if bvis or edn.recomputeScroll
            {
                x = .paintLine(evt.paintContext, i, y - .scrollPos.y, bvis)
            }

            maxx = Math.max(maxx, x)
            y    += size.y
            i    += 1
            if !edn.recomputeScroll and y >= .scrollPos.y + clientRect.bottom() do
                break
        }

        // Caret
        if .visibleCaret
        {
            let colorCaret = .themeColors().richEdit_Caret
            if edn.hasSelRect
            {
                let selBeg = edn.selectionStart()
                let selEnd = edn.selectionEnd()
                for caretI in selBeg.lineIndex to selEnd.lineIndex
                {
                    var cp = edn.cursorPos
                    cp.lineIndex = caretI
                    if cp.charPosInLine > edn.lines[cp.lineIndex]!.length() do
                        continue
                    var posCaret = edn.caretRect(cp)
                    posCaret.x -= .scrollPos.x
                    posCaret.y -= .scrollPos.y
                    painter.fillRect(posCaret, colorCaret)
                }
            }
            else
            {
                var posCaret = edn.caretRect(edn.cursorPos)
                posCaret.x -= .scrollPos.x
                posCaret.y -= .scrollPos.y
                painter.fillRect(posCaret, colorCaret)
            }
        }

        // Scroll size
        y = cast(f32) (edn.countVisibleLines * size.y)
        if edn.flags & .WordWrap do
            maxx = 0
        elif !edn.recomputeScroll do
            maxx = edn.scrollWnd.scrollSize.x
        else
        {
            let posCaret = edn.caretRect(edn.cursorPos)
            maxx += posCaret.width + 32
        }

        edn.recomputeScroll = false
        edn.scrollWnd.setScrollSize(maxx, y)

        // Force visible caret
        if edn.forceCaretVisible
        {
            edn.forceCaretVisible = false
            edn.ensureCaretIsVisibleInternal(edn.forceCaretVisibleCenter)
        }
    }
}

impl RichEditView
{
    mtd forceVisibleCaret()
    {
        if .timerCaret
        {
            .visibleCaret = true
            .timerCaret.restart()
            .invalidate()
        }
    }

    mtd paintString(bc: *PaintContext, x, y: f32, str: String, strStyle: RichEditRuneStyle, visible: bool)->f32
    {
        let edn     = .ed!
        let painter = bc.painter

        let fontR = edn.font().getFont(strStyle.fontMode)
        if !fontR or str.isEmpty() do
            return x
        let font = nnFont(fontR)

        var shaped     = Painter.shapeRun(str, font)
        let info       = Painter.computeTextDrawInfo(font, 1.0, .deviceScale())
        let drawFont   = info.drawFont
        let snapPixels = info.snapPixels

        var drawShape: ShapedRun
        var runToDraw = &shaped
        if shaped.font != drawFont
        {
            drawShape = Painter.shapeRunForFont(&shaped, drawFont)
            runToDraw = &drawShape
        }

        let left  = snapPixels ? Math.round(x * info.deviceScale) / info.deviceScale : x
        var right = left
        for glyph, idx in runToDraw.glyphs
        {
            let step = Painter.advanceTextX(right, glyph.offsetX, glyph.advanceX, info, idx == 0)
            right = step.rightX
        }

        // Background rectangle
        if visible and strStyle.colBk.a
        {
            var rect: Math.Rectangle
            rect.x      = left
            rect.y      = y
            rect.width  = Math.max(right - left, 0.0)
            rect.height = edn.xGlyphSize().y
            painter.fillRect(rect, strStyle.colBk)
        }

        painter.drawShapedRun(x, y, &shaped, font, Brush.createSolid(strStyle.colFg), strStyle.underline)
        return right
    }

    mtd paintLine(bc: *PaintContext, lineIndex: u64, py: f32, visible: bool)->f32
    {
        let edn  = .ed!
        let line = edn.lines[lineIndex]!
        let y    = py

        // Dummy character for empty lines, so that a selected line display something
        var dummyChar  = ' 'rune
        var dummyStyle = 0'u8
        var count      = line.length()
        var pChar      = cast([*] rune) &dummyChar
        var pStyle     = cast([*] u8) &dummyStyle
        if count
        {
            pChar  = line.chars.buffer!
            pStyle = line.styles.buffer!
        }
        else do
            count = 1

        var str: String
        str.reserve(line.length())

        var oldStyle, newStyle: RichEditRuneStyle
        oldStyle = edn.styles[0]
        var x = edn.leftMargin() - .scrollPos.x

        let sel0 = edn.selectionStart()
        let sel1 = edn.selectionEnd()
        let size = edn.xGlyphSize()

        var i = 0
        while i < count
        {
            defer
            {
                i      += 1
                pChar  += 1
                pStyle += 1
            }

            newStyle = edn.styles[pStyle[]]

            var cr           = pChar[]
            let isTabulation = cr == '\t'

            var selected = false
            if edn.hasSelRect
            {
                var cp1: RichEditCursor
                cp1.charPosInLine = i
                cp1.lineIndex     = lineIndex
                var charPos = edn.cursorDisplayPosition(cp1)
                charPos.y -= size.y * 0.5
                if edn.selRectangle.contains(charPos) do
                    selected = true
            }
            else
            {
                if (lineIndex > sel0.lineIndex and lineIndex < sel1.lineIndex) or
                   (lineIndex != sel1.lineIndex and lineIndex == sel0.lineIndex and i >= sel0.charPosInLine) or
                   (lineIndex != sel0.lineIndex and lineIndex == sel1.lineIndex and i < sel1.charPosInLine) or
                   (lineIndex == sel0.lineIndex and sel0.lineIndex == sel1.lineIndex and i >= sel0.charPosInLine and i < sel1.charPosInLine)
                {
                    selected = true
                }
            }

            if selected
            {
                if .hasFocus() do
                    newStyle = edn.stylesSelect[0]
                elif edn.flags & .ShowFocusSel do
                    newStyle = edn.stylesSelect[1]
                if !newStyle.colFg.a do
                    newStyle.colFg = edn.styles[pStyle[]].colFg
                newStyle.fontMode  = edn.styles[pStyle[]].fontMode
                newStyle.underline = edn.styles[pStyle[]].underline
            }

            if edn.flags & .DrawBlanks
            {
                if cr == ' ' and pChar != &dummyChar
                {
                    newStyle.colFg = .themeColors().richEdit_TextSpecial
                    cr             = '.'
                }
                elif isTabulation
                {
                    newStyle.colFg = .themeColors().richEdit_TextSpecial
                }
            }

            // Paint accumulated string if we have a change of style
            let styleChange = newStyle != oldStyle
            if styleChange or isTabulation
            {
                x        = .paintString(bc, x, y, str, oldStyle, visible)
                oldStyle = newStyle
                str.clear()
            }

            if isTabulation
            {
                let x1 = x
                x += edn.tabAdvance(cast(s32) x)

                // Background color for tabulations
                if visible and oldStyle.colBk.a do
                    bc.painter.fillRect({x1, y, x - x1, size.y}, oldStyle.colBk)
            }
            else
            {
                str += cr
            }
        }

        // Remaining string
        if !str.isEmpty()
        {
            let x1 = .paintString(bc, x, y, str, oldStyle, visible)
            x = x1
        }

        return x + .scrollPos.x
    }
}

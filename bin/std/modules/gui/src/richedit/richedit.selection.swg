#global public

using Core

private impl RichEditCtrl
{
    mtd getSelectionRectRange(lineIndex: u64, rankBeg, rankEnd: *u64)->bool
    {
        let line = notnull .lines[lineIndex]
        let len  = line.length()

        var x  = .getMarginLeft()
        var rb = 0'u64
        while x < .selRectangle.x and rb < len
        {
            x  += .getRuneSize(line, rb, x).x
            rb += 1
        }

        // Line is not concerned
        if x < .selRectangle.x do
            return false

        var re = rb
        while x < .selRectangle.right() and re < len
        {
            x  += .getRuneSize(line, re, x).x
            re += 1
        }

        dref rankBeg = rb
        dref rankEnd = re
        return true
    }

    mtd deleteSelectionPrivate(posStart, posEnd: RichEditCursor, selRect: bool)
    {
        let undo = Memory.new'RichEditUndo()
        undo.type                 = .Delete
        {undo.runes, undo.styles} = .getTextPrivate(posStart, posEnd)
        undo.selBeg               = .selBeg
        undo.cursorPos            = .cursorPos
        undo.hasSelRect           = selRect
        undo.serial               = 0
        .resetUndo()
        .toUndo.add(undo)
        .deleteTextPrivate(posStart, posEnd, selRect)
    }

    mtd undoRestoreSelection()
    {
        let undo = Memory.new'RichEditUndo()
        undo.type      = .Selection
        undo.selBeg    = .selBeg
        undo.cursorPos = .cursorPos
        undo.serial    = 0
        .resetUndo()
        .toUndo.add(undo)
    }

    mtd computeRectangularSelection(beg, end: RichEditCursor)
    {
        if !.hasSelRect do
            return

        let size = .getXExtent()

        var ptBeg = .getCursorDisplayPos(beg)
        var ptEnd = .getCursorDisplayPos(end)

        if ptBeg.x > ptEnd.x do
            swap(&ptBeg, &ptEnd)

        .selRectangle.x = ptBeg.x
        .selRectangle.y = Math.min(ptBeg.y, ptEnd.y) - size.y
        .selRectangle.setRight(ptEnd.x)
        .selRectangle.setBottom(Math.max(ptBeg.y, ptEnd.y))
    }
}

impl RichEditCtrl
{
    // Performs the select all operation.
    mtd selectAll()
    {
        .moveCursorStartFile(&.selBeg)
        .moveCursorEndFile(&.cursorPos)
        .setRectangularSelection(false)
    }

    // Sets rectangular selection.
    mtd setRectangularSelection(selRect: bool)
    {
        .hasSelRect = selRect
    }

    // Performs the clear selection operation.
    mtd clearSelection()
    {
        .selBeg = .cursorPos
        .setRectangularSelection(false)
    }

    // Sets selection.
    mtd setSelection(start, end: RichEditCursor)
    {
        .selBeg    = start
        .cursorPos = end
        .checkSelection()
    }

    // Returns whether selection empty.
    mtd isSelectionEmpty()->bool
    {
        if .selBeg.lineIndex != .cursorPos.lineIndex do
            return false
        if .selBeg.charPosInLine != .cursorPos.charPosInLine do
            return false
        return true
    }

    // Returns beg selection.
    mtd getBegSelection()->RichEditCursor
    {
        if .hasSelRect
        {
            var result: retval
            result.lineIndex     = Math.min(.selBeg.lineIndex, .cursorPos.lineIndex)
            result.charPosInLine = Math.min(.selBeg.charPosInLine, .cursorPos.charPosInLine)
            return result
        }

        if .selBeg.lineIndex < .cursorPos.lineIndex do
            return .selBeg
        if .selBeg.lineIndex > .cursorPos.lineIndex do
            return .cursorPos
        if .selBeg.charPosInLine <= .cursorPos.charPosInLine do
            return .selBeg
        return .cursorPos
    }

    // Returns end selection.
    mtd getEndSelection()->RichEditCursor
    {
        if .hasSelRect
        {
            var result: retval
            result.lineIndex     = Math.max(.selBeg.lineIndex, .cursorPos.lineIndex)
            result.charPosInLine = Math.max(.selBeg.charPosInLine, .cursorPos.charPosInLine)
            return result
        }

        if .selBeg.lineIndex < .cursorPos.lineIndex do
            return .cursorPos
        if .selBeg.lineIndex > .cursorPos.lineIndex do
            return .selBeg
        if .selBeg.charPosInLine <= .cursorPos.charPosInLine do
            return .cursorPos
        return .selBeg
    }

    // Performs the check selection operation.
    mtd checkSelection()
    {
        if .selBeg.lineIndex >= .lines.count do
            .selBeg.lineIndex = .lines.count - 1
        if .cursorPos.lineIndex >= .lines.count do
            .cursorPos.lineIndex = .lines.count - 1

        if .firstVisibleLineView >= .lines.count or .lastVisibleLineView >= .lines.count
        {
            .firstVisibleLineView = 0
            .lastVisibleLineView  = 0
            .dirtyFirstLineView   = true
            .invalidate()
        }

        let back = notnull .lines.back()
        if .selBeg.lineIndex == .lines.count - 1 and .selBeg.charPosInLine > back.length() do
            .selBeg.charPosInLine = back.length()

        if .cursorPos.lineIndex == .lines.count - 1 and .cursorPos.charPosInLine > back.length() do
            .cursorPos.charPosInLine = back.length()

        .computeRectangularSelection(.getBegSelection(), .getEndSelection())
    }

    // Performs the delete selection operation.
    mtd deleteSelection()
    {
        if .isReadOnly() do
            return
        if .isSelectionEmpty() do
            return

        .pushUndo()
        let cp = .getBegSelection()
        .deleteSelectionPrivate(cp, .getEndSelection(), .hasSelRect)
        .computeScrollY()

        if .hasSelRect
        {
            .cursorPos.charPosInLine = Math.min(.cursorPos.charPosInLine, .selBeg.charPosInLine)
            .selBeg.charPosInLine    = .cursorPos.charPosInLine
        }
        else
        {
            .setCursorPos(cp)
            .selBeg = cp
        }

        .popUndo()
    }

    // Performs the delete left operation.
    mtd deleteLeft()
    {
        .pushUndo()

        if .isSelectionEmpty()
        {
            .moveCursorLeft(&.cursorPos)
        }
        elif .hasSelRect and .selBeg.charPosInLine == .cursorPos.charPosInLine
        {
            var cp = .cursorPos
            .moveCursorLeft(&cp)
            if cp.lineIndex == .cursorPos.lineIndex
            {
                .cursorPos = cp
                .computeRectangularSelection(.getBegSelection(), .getEndSelection())
            }
        }

        .deleteSelection()
        .popUndo()
    }

    // Performs the delete right operation.
    mtd deleteRight()
    {
        .pushUndo()
        if .isSelectionEmpty() or (.hasSelRect and .selBeg.charPosInLine == .cursorPos.charPosInLine)
        {
            .moveCursorRight(&.selBeg)
            .computeRectangularSelection(.getBegSelection(), .getEndSelection())
        }

        .deleteSelection()
        .popUndo()
    }

    // Performs the delete word left operation.
    mtd deleteWordLeft()
    {
        .pushUndo()
        .deleteSelection()
        .moveCursorWordLeft(&.cursorPos)
        .deleteSelection()
        .clearSelection()
        .popUndo()
    }

    // Performs the delete word right operation.
    mtd deleteWordRight()
    {
        .pushUndo()
        .deleteSelection()
        .moveCursorWordRight(&.cursorPos, true)
        .deleteSelection()
        .clearSelection()
        .popUndo()
    }

    private mtd registerClipboardFormat()
    {
        .clipFormat = catch Clipboard.registerFormat("std.richedit.style")
    }

    // Performs the copy to clipboard operation.
    mtd copyToClipboard()
    {
        if .isSelectionEmpty() do
            return
        let res = .getTextPrivate(.getBegSelection(), .getEndSelection())

        .registerClipboardFormat()
        if .clipFormat do
            Clipboard.addTypedData(.clipFormat, null, res.styles.toSlice())

        let txt = Utf8.fromUnicode(res.text.toSlice())
        Clipboard.addString(txt)
    }

    // Performs the paste from clipboard operation.
    mtd pasteFromClipboard()
    {
        let txt = Clipboard.getString()
        .registerClipboardFormat()

        .pushUndo()
        .deleteSelection()

        if .clipFormat and Clipboard.hasFormat(.clipFormat)
        {
            let st = Clipboard.getTypedData(.clipFormat, null)
            .insertText(txt, st)
        }
        else do
            .insertText(txt)

        .popUndo()
        .forceCaretVisible = true
    }

    // Performs the delete line operation.
    mtd deleteLine()
    {
        .pushUndo()
        var beg = .getBegSelection()
        var end = .getEndSelection()
        if end.charPosInLine == 0 and beg.lineIndex != end.lineIndex do
            .moveCursorLeft(&end)
        beg.charPosInLine = 0
        end.charPosInLine = (notnull .lines[end.lineIndex]).length()
        .selBeg           = beg
        .setCursorPos(end)
        .moveCursorRight(&.cursorPos)
        .copyToClipboard()
        .deleteSelection()
        .popUndo()
    }

    // Performs the select word operation.
    mtd selectWord()
    {
        let line = notnull .lines[.cursorPos.lineIndex]
        let len  = line.length()
        if !len do
            return

        if .cursorPos.charPosInLine == len do
            .cursorPos.charPosInLine -= 1
        let cp = .cursorPos.charPosInLine ? line.chars[.selBeg.charPosInLine - 1] : 0'rune
        let c  = .selBeg.charPosInLine == len ? 0'rune : line.chars[.selBeg.charPosInLine]
        let cn = .cursorPos.charPosInLine != len - 1 ? line.chars[.selBeg.charPosInLine + 1] : 0'rune

        if Unicode.isSpace(c) and !Unicode.isSpace(cp) and !Unicode.isSpace(cn) and .cursorPos.charPosInLine do
            .cursorPos.charPosInLine -= 1

        .selBeg = .cursorPos

        // Blanks
        if Unicode.isSpace(line.chars[.selBeg.charPosInLine])
        {
            while .selBeg.charPosInLine and Unicode.isSpace(line.chars[.selBeg.charPosInLine - 1]) do
                .selBeg.charPosInLine -= 1
            while .cursorPos.charPosInLine < len and Unicode.isSpace(line.chars[.cursorPos.charPosInLine]) do
                .cursorPos.charPosInLine += 1
            return
        }

        // A word
        if isWord(line.chars[.cursorPos.charPosInLine])
        {
            while .selBeg.charPosInLine and isWord(line.chars[.selBeg.charPosInLine - 1]) do
                .selBeg.charPosInLine -= 1
            while .cursorPos.charPosInLine < len and isWord(line.chars[.cursorPos.charPosInLine]) do
                .cursorPos.charPosInLine += 1
            return
        }

        // Nothing
        if !zapWordChar(line.chars[.selBeg.charPosInLine])
        {
            if .selBeg.charPosInLine == len do
                .selBeg.charPosInLine -= 1
            else do
                .cursorPos.charPosInLine += 1
            return
        }

        while .selBeg.charPosInLine and zapWordChar(line.chars[.selBeg.charPosInLine - 1]) do
            .selBeg.charPosInLine -= 1
        while .cursorPos.charPosInLine < len and zapWordChar(line.chars[.cursorPos.charPosInLine]) do
            .cursorPos.charPosInLine += 1
    }

    // Performs the scroll line up operation.
    mtd scrollLineUp()
    {
        let pt   = .scrollWnd.getScrollPos()
        let size = .getXExtent()

        var sy = (pt.y / size.y) * size.y
        sy -= size.y

        .scrollWnd.setScrollPos(pt.x, sy)
        sy = .scrollWnd.getScrollPos().y

        let clientRect = .edView.getClientRect()
        var pos        = .getCaretPos(.cursorPos)
        while pos.bottom() > sy + clientRect.height
        {
            if !.moveCursorUp(&.cursorPos) do
                break
            .clearSelection()
            pos = .getCaretPos(.cursorPos)
        }
    }

    // Performs the scroll line down operation.
    mtd scrollLineDown()
    {
        let pt   = .scrollWnd.getScrollPos()
        let size = .getXExtent()

        var sy = (pt.y / size.y) * size.y
        sy += size.y

        .scrollWnd.setScrollPos(pt.x, sy)
        sy = .scrollWnd.getScrollPos().y

        var pos = .getCaretPos(.cursorPos)
        while pos.y < sy
        {
            if !.moveCursorDown(&.cursorPos) do
                break
            .clearSelection()
            pos = .getCaretPos(.cursorPos)
        }
    }
}

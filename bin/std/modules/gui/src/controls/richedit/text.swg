using Core, Pixel

impl RichEditCtrl
{
    mtd textRangeData(start, end: RichEditCursor)->{ text: Array'rune, styles: Array'u8 }
    {
        var result: retval

        // An empty document (no line) has no text to extract.
        if .lines.isEmpty() do
            return result

        if not .hasSelRect
        {
            // First line
            var line  = .lines[start.lineIndex]!
            var count = line.length()
            if count
            {
                let pchar  = line.chars.storage()
                let pstyle = line.styles.storage()
                if start.lineIndex == end.lineIndex do
                    count = end.charPosInLine
                for var i = start.charPosInLine; i < count; i += 1
                {
                    result.text.add(pchar[i])
                    result.styles.add(pstyle[i])
                }
            }

            if start.lineIndex != end.lineIndex and not .lines[start.lineIndex + 1]!.wordWrap
            {
                result.text.add('\n')
                result.styles.add(0)
            }

            // Inside lines
            if end.lineIndex > start.lineIndex + 1
            {
                // Pre allocate string to optimize append
                count = 0
                for var i = start.lineIndex + 1; i < end.lineIndex; i += 1 do
                    count += .lines[i]!.length()
                result.text.reserve(result.text.count + count)
                result.styles.reserve(result.styles.count + count)

                for var i = start.lineIndex + 1; i < end.lineIndex; i += 1
                {
                    result.text.add(.lines[i]!.chars.toSlice())
                    result.styles.add(.lines[i]!.styles.toSlice())
                    if not .lines[i + 1]!.wordWrap
                    {
                        result.text.add('\n')
                        result.styles.add(0)
                    }
                }
            }

            // Last line
            if start.lineIndex != end.lineIndex
            {
                line  = .lines[end.lineIndex]!
                count = line.length()
                if count
                {
                    let pchar  = line.chars.storage()
                    let pstyle = line.styles.storage()
                    for var i = 0; i < end.charPosInLine; i += 1
                    {
                        result.text.add(pchar[i])
                        result.styles.add(pstyle[i])
                    }
                }
            }
        }
        else
        {
            var li = start.lineIndex
            while li <= end.lineIndex
            {
                var rankBeg, rankEnd: u64
                if .selectionRectRange(li, &rankBeg, &rankEnd)
                {
                    for i in rankEnd - rankBeg
                    {
                        result.text.add(.lines[li]!.chars[rankBeg + i])
                        result.styles.add(.lines[li]!.styles[rankBeg + i])
                    }
                }

                result.text.add('\n')
                result.styles.add(0)
                li += 1
            }
        }

        return result
    }

    mtd unwrap(lineIndex: u64)
    {
        // Make one single line with current wrapped lines
        var i       = lineIndex + 1
        let dstLine = .lines[lineIndex]!
        while i < .lines.count
        {
            let srcLine = .lines[i]!
            if not srcLine.wordWrap do
                break

            if .cursorPos.lineIndex == i
            {
                .cursorPos.lineIndex     = lineIndex
                .cursorPos.charPosInLine += dstLine.chars.count
            }

            if .selBeg.lineIndex == i
            {
                .selBeg.lineIndex     = lineIndex
                .selBeg.charPosInLine += dstLine.chars.count
            }

            dstLine.chars.add(srcLine.chars.toSlice())
            dstLine.styles.add(srcLine.styles.toSlice())
            i += 1
        }

        // A cursor below the joined block keeps the place it points at: the display lines removed
        // above it move it up by as many. Without this a selection revealed on a later line drifts
        // toward the top of the document every time a line above it stops being wrapped.
        let removed = i - lineIndex - 1
        if removed
        {
            if .cursorPos.lineIndex >= i do
                .cursorPos.lineIndex -= removed
            if .selBeg.lineIndex >= i do
                .selBeg.lineIndex -= removed
        }

        // Remove current wrapped lines
        while i != lineIndex + 1
        {
            .deleteLine(lineIndex + 1)
            i -= 1
        }
    }

    mtd wrap(lineIndex: u64)
    {
        if not .flags.has(.WordWrap) do
            return

        if not .font().getFont(.styles[0].fontMode) do
            return
        let line  = .lines[lineIndex]!
        let right = .scrollWnd.paddedClientRect().width - .scrollWnd.paddingZ - .rightMargin()
        var cuts: Array'u64
        var start, i, wordEnd: u64
        var x     = .leftMargin()

        // Advance once per rune instead of shaping every growing prefix. A word longer than
        // the viewport also needs a cut, including input interpreted with the wrong encoding.
        while i < line.length()
        {
            var next = .advanceRuneX(line, i, x)
            if i == start and start and line.chars[i] != '\t'
            {
                // A new display line has no preceding glyph to kern against.
                let info  = .computeTextDrawInfo(line.styles[i])
                let font  = info.drawFont.resolveRune(line.chars[i])
                let glyph = font.getGlyphDescByIndex(font.glyphIndex(line.chars[i]))
                next = Painter.advanceTextX(x, 0, glyph.advanceX, info, true).rightX
            }

            if next > right and i > start
            {
                let cut = wordEnd > start ? wordEnd : i
                cuts.add(cut)
                start   = cut
                i       = cut
                wordEnd = cut
                x       = .leftMargin()
                continue
            }

            x = next
            i += 1
            if not Unicode.isLetterOrDigit(line.chars[i - 1]) do
                wordEnd = i
        }

        // Split from the end so every rune is copied once, even for a single huge logical line.
        var end = line.length()
        for cut in cuts.reversed()
        {
            // A cursor below the line being split keeps the place it points at, one display
            // line further down; one on the split line follows the runes it sits among.
            // Leaving the first case out is what made a search reveal land on whatever
            // sentence happened to carry the same index once a line above it wrapped.
            if .cursorPos.lineIndex > lineIndex do
                .cursorPos.lineIndex += 1
            elif .cursorPos.lineIndex == lineIndex and .cursorPos.charPosInLine >= cut
            {
                .cursorPos.lineIndex     += 1
                .cursorPos.charPosInLine -= cut
            }

            if .selBeg.lineIndex > lineIndex do
                .selBeg.lineIndex += 1
            elif .selBeg.lineIndex == lineIndex and .selBeg.charPosInLine >= cut
            {
                .selBeg.lineIndex     += 1
                .selBeg.charPosInLine -= cut
            }

            with let nextLine = .newLine(lineIndex + 1)
            {
                .wordWrap = true
                .chars.add(line.chars.toSlice()[cut until end])
                .styles.add(line.styles.toSlice()[cut until end])
                .dirtyStyle       = false
                .lexerEndingState = line.lexerEndingState
                .lexerCptCmt      = line.lexerCptCmt
            }

            end = cut
        }

        line.chars.resize(end)
        line.styles.resize(end)
    }

    mtd insertRunePrivate(cp: *RichEditCursor, c: rune, txtStyle: RichEditStyleRef)
    {
        if c == '\r' do
            return

        if c == '\n'
        {
            let linep = .lines[cp.lineIndex]!
            discard .newLine(cp.lineIndex + 1)
            let line = (.lines[cp.lineIndex + 1])!
            if cp.charPosInLine < linep.length() do
                line.insertRunes(0, linep, cp.charPosInLine, linep.length() - cp.charPosInLine)
            linep.setLength(cp.charPosInLine)
            cp.lineIndex     += 1
            cp.charPosInLine = 0
        }
        elif c == '\t' and .flags.has(.TabToSpaces)
        {
            let line = .lines[cp.lineIndex]!
            for .tabSize
            {
                let posIns = Math.min(cp.charPosInLine, line.length())
                line.insertRune(posIns, ' ', txtStyle)
                cp.charPosInLine += 1
            }
        }
        else
        {
            let line   = .lines[cp.lineIndex]!
            let posIns = Math.min(cp.charPosInLine, line.length())
            line.insertRune(posIns, c, txtStyle)
            cp.charPosInLine += 1
        }

        .recomputeScroll = true
    }

    mtd insertTextPrivate(cp: *RichEditCursor, runes: Array'rune, nstyles: Array'u8, selRect: bool)
    {
        if runes.isEmpty() do
            return
        Swag.assert(runes.count == nstyles.count)
        if .lines.isEmpty() do
            .newLine(0)

        if not selRect
        {
            for i in runes.count
            {
                let c = runes[i]
                let s = nstyles[i]
                .insertRunePrivate(cp, c, s)
            }
        }
        else
        {
            var lineIndex = cp.lineIndex
            var posInLine = cp.charPosInLine

            var rankBeg, rankEnd: u64
            for
            {
                let line = .lines[lineIndex]!
                if rankEnd == runes.count or runes[rankEnd] == '\n'
                {
                    var posIns = posInLine
                    if posIns > line.length() do
                        posIns = line.length()
                    line.insertRunes(posIns, Swag.makeSlice(runes.buffer + rankBeg, rankEnd - rankBeg), Swag.makeSlice(nstyles.buffer + rankBeg, rankEnd - rankBeg))
                    if rankEnd == runes.count do
                        break
                    if rankEnd >= runes.count - 1 do
                        break

                    lineIndex += 1
                    if lineIndex == .lines.count
                    {
                        .newLine(lineIndex)
                        posInLine = 0
                    }

                    rankEnd += 1
                    rankBeg = rankEnd
                    continue
                }

                if rankEnd == runes.count do
                    break
                rankEnd += 1
            }

            cp.lineIndex     = lineIndex
            cp.charPosInLine = posInLine + (rankEnd - rankBeg)
        }

        .recomputeScroll = true
    }

    mtd insertTextPrivate(cp: *RichEditCursor, text: string, txtStyle: RichEditStyleRef)
    {
        if .lines.isEmpty() do
            .newLine(0)
        elif cp.lineIndex == .lines.count do
            .newLine(cp.lineIndex)

        var str = text
        for
        {
            let {c, eat} = Utf8.decodeRune(str)
            if not eat do
                break
            str = Tokenize.eatCount(str, cast(u64) eat)
            .insertRunePrivate(cp, c, txtStyle)
        }

        .recomputeScroll = true
    }

    mtd deleteTextPrivate(posStart, posEnd: RichEditCursor, selRect: bool)
    {
        // Nothing to delete
        if posStart.lineIndex == posEnd.lineIndex and posStart.charPosInLine == posEnd.charPosInLine do
            return

        if not selRect
        {
            let ps = posStart
            var pe = posEnd

            // Remove inside lines
            while pe.lineIndex > ps.lineIndex + 1
            {
                .deleteLine(ps.lineIndex + 1)
                pe.lineIndex -= 1
            }

            let lineSrc = .lines[ps.lineIndex]!
            let lineEnd = .lines[pe.lineIndex]!

            if ps.lineIndex == pe.lineIndex
            {
                lineSrc.removeRunes(ps.charPosInLine, pe.charPosInLine - ps.charPosInLine)
            }
            else
            {
                lineSrc.removeRunes(ps.charPosInLine, lineSrc.length() - ps.charPosInLine)
                lineEnd.removeRunes(0, pe.charPosInLine)
                if lineEnd.length() do
                    lineSrc.insertRunes(ps.charPosInLine, lineEnd, 0, lineEnd.length())
                .deleteLine(pe.lineIndex)
            }
        }
        else
        {
            var ps = posStart
            var pe = posEnd
            if ps.lineIndex > pe.lineIndex do
                swap(&ps, &pe)

            var li = ps.lineIndex
            while li <= pe.lineIndex
            {
                var rankBeg, rankEnd: u64
                if .selectionRectRange(li, &rankBeg, &rankEnd)
                {
                    let ln = .lines[li]!
                    ln.removeRunes(rankBeg, rankEnd - rankBeg)
                }

                li += 1
            }
        }

        .recomputeScroll = true
    }

    func isWord(c: rune)->bool => Unicode.isLetterOrDigit(c) or c == '_'

    func zapWordChar(c: rune)->bool
    {
        if isWord(c) do
            return false
        if Unicode.isSpace(c) do
            return false
        if c != '(' and c != ')' and c != '[' and c != ']' and c != '{' and c != '}' do
            return true
        return false
    }
}

public impl RichEditCtrl
{
    // Removes the whole document, its undo history, and the selection.
    mtd clear()
    {
        .clearUndo()
        for l in .lines do
            .freeLines.add(l)

        // Ownership moved to the free list above: detach without freeing,
        // otherwise the recycled pointers in .freeLines would dangle.
        .lines.detachAll()
        .countVisibleLines      = 0
        .cursorPos              = {}
        .selBeg                 = {}
        .dirtyFirstLineView     = true
        .firstVisibleLineView   = 0
        .lastVisibleLineView    = 0
        .loadedContentHeight    = 0
        .residentContentOffset  = 0
        .estimatedContentHeight = 0
    }

    // Returns the selected plain text.
    mtd selectedText()->String
    {
        let res = .textRangeData(.selectionStart(), .selectionEnd())
        return Utf8.fromUnicode(res.text.toSlice())
    }

    // Returns the complete plain text.
    mtd text()->String
    {
        var sel0: RichEditCursor
        var sel1: RichEditCursor
        .moveCursorStartFile(&sel0)
        .moveCursorEndFile(&sel1)
        let res = .textRangeData(sel0, sel1)
        return Utf8.fromUnicode(res.text.toSlice())
    }

    // Returns the complete text and one style reference per rune.
    mtd textAndStyles()->{ text: Core.Array'rune, styles: Core.Array'u8 }
    {
        var sel0: RichEditCursor
        var sel1: RichEditCursor
        .moveCursorStartFile(&sel0)
        .moveCursorEndFile(&sel1)
        return .textRangeData(sel0, sel1)
    }

    // Replaces the complete document text and clears incompatible cursor state.
    mtd setText(text: string)
    {
        .clear()

        var cp: RichEditCursor
        .insertTextPrivate(&cp, text, 0)

        .resetModified()
        .invalidate()
    }

    // Appends `text` at the end of the document with the style index `txtStyle`, without recording an undo step.
    mtd addText(text: string, txtStyle: RichEditStyleRef = 0)
    {
        var cp: RichEditCursor
        if .lines.count
        {
            cp.lineIndex     = .lines.count - 1
            cp.charPosInLine = .lines[cp.lineIndex]!.length()
        }

        .insertTextPrivate(&cp, text, txtStyle)
        .setModified(true)
    }

    // Selects the next case-insensitive occurrence of `text` and keeps it visible.
    //
    // Search starts after the current selection and wraps once at the end of the document.
    mtd findText(text: string)->bool
    {
        if not text.count or not .lines.count do
            return false

        let origin = .selectionEnd()
        for pass in 2
        {
            let firstLine = pass ? 0 : origin.lineIndex
            let lastLine  = pass ? origin.lineIndex : .lines.count - 1
            for lineIndex in firstLine to lastLine
            {
                let utf8      = Utf8.fromUnicode(.lines[lineIndex]!.chars.toSlice())
                var byteStart = 0'u64
                if not pass and lineIndex == origin.lineIndex
                {
                    let converted = Utf8.byteIndex(utf8.toSlice(), origin.charPosInLine)
                    if converted.success do
                        byteStart = converted.index
                }

                let found = Utf8.indexOf(utf8.toSlice(), text, byteStart, .Latin1NoCase)
                if found == Swag.U64.Max do
                    continue

                var start: RichEditCursor
                start.lineIndex     = lineIndex
                start.charPosInLine = Utf8.countRunes(utf8.toSlice()[0 until found])
                var end = start
                end.charPosInLine += Utf8.countRunes(text)
                .setSelection(start, end)
                .forceCaretVisibleCenter = true
                .invalidate()
                return true
            }

            if origin.lineIndex == 0 do
                break
        }

        return false
    }

    // Inserts `text` at the caret with style index zero.
    //
    // Call it between [[Gui.RichEditCtrl.pushUndo]] and [[Gui.RichEditCtrl.popUndo]], which
    // commit the undo record it prepares.
    mtd insertText(text: string)
    {
        let undo = Memory.new'RichEditUndo()
        undo.type  = .Insert
        undo.runes = Unicode.fromUtf8(text)
        undo.styles.resize(undo.runes.count)
        undo.selBeg     = .selBeg
        undo.cursorPos  = .cursorPos
        undo.hasSelRect = .hasSelRect
        undo.serial     = 0
        .resetUndo()
        .toUndo.add(undo)
        .insertTextPrivate(&.cursorPos, text, 0)
        .clearSelection()
        .setModified(true)
    }

    // Inserts `text` at the caret with one style index per rune from `txtStyles`.
    mtd insertText(text: string, txtStyles: Array'u8)
    {
        let undo = Memory.new'RichEditUndo()
        undo.type       = .Insert
        undo.runes      = Unicode.fromUtf8(text)
        undo.styles     = txtStyles
        undo.selBeg     = .selBeg
        undo.cursorPos  = .cursorPos
        undo.hasSelRect = .hasSelRect
        undo.serial     = 0
        .resetUndo()
        .toUndo.add(undo)
        .insertTextPrivate(&.cursorPos, undo.runes, undo.styles, .hasSelRect)
        .clearSelection()
        .setModified(true)
    }

    // Returns the rune and style at a document cursor.
    mtd runeAt(cp: RichEditCursor)->{ char: rune, style: RichEditStyleRef }
    {
        var result: retval
        if cp.lineIndex >= .lines.count do
            return result
        let len = .lines[cp.lineIndex]!.chars.count
        if cp.charPosInLine > len do
            return result
        if cp.charPosInLine == len do
            return {'\n', 0}
        result.char  = .lines[cp.lineIndex]!.chars[cp.charPosInLine]
        result.style = .lines[cp.lineIndex]!.styles[cp.charPosInLine]
        return result
    }

    // Types `ch` at the caret, replacing the selection, as one undoable step with the runes typed next to it.
    mtd insertRune(ch: rune)
    {
        let c = ch
        if .lines.isEmpty() do
            .newLine(0)

        // A new undo action needs to be regenerate ?
        var forceUndo = false
        var pundo     = .currentUndo ? .undoMgr[.currentUndo - 1] : null
        if not .hasSelRect and not .isSelectionEmpty() do
            forceUndo = true
        elif .hasSelRect and .cursorPos.charPosInLine != .selBeg.charPosInLine do
            forceUndo = true
        elif not .currentUndo do
            forceUndo = true
        elif pundo and not pundo.concatChars do
            forceUndo = true
        elif pundo and pundo.cursorPos.lineIndex != .cursorPos.lineIndex do
            forceUndo = true
        elif pundo and .cursorPos.charPosInLine != pundo.cursorPos.charPosInLine + pundo.runes.count do
            forceUndo = true

        if forceUndo
        {
            .resetUndo()

            // Delete actual selection
            if not .hasSelRect and not .isSelectionEmpty() do
                .deleteSelection()
            elif .hasSelRect and .cursorPos.charPosInLine != .selBeg.charPosInLine do
                .deleteSelection()
            else do
                .serialUndo += 1

            // Register action of deletion for overmode
            if .overwriteMode and .cursorPos.charPosInLine != .lines[.cursorPos.lineIndex]!.length()
            {
                pundo                    = Memory.new'RichEditUndo()
                pundo.type               = .Delete
                pundo.concatChars        = true
                pundo.selBeg             = .selBeg
                pundo.cursorPos          = .cursorPos
                pundo.serial             = .serialUndo
                pundo.begSelectionBefore = .selBeg
                pundo.endSelectionBefore = .cursorPos
                .undoMgr.add(pundo)
                .currentUndo += 1
            }

            // Register action of insertion
            pundo                    = Memory.new'RichEditUndo()
            pundo.type               = .Insert
            pundo.concatChars        = true
            pundo.selBeg             = .selBeg
            pundo.cursorPos          = .cursorPos
            pundo.serial             = .serialUndo
            pundo.begSelectionBefore = .selBeg
            pundo.endSelectionBefore = .cursorPos
            pundo.hasSelRect         = .hasSelRect
            .undoMgr.add(pundo)
            .currentUndo += 1
        }

        var az: [4] u8
        let cpt = Utf8.encodeRune(az, c)

        // Add a deletion
        if .currentUndo > 1
        {
            pundo = (.undoMgr[.currentUndo - 2])!
            if pundo.type == .Delete and pundo.concatChars
            {
                if .cursorPos.charPosInLine != .lines[.cursorPos.lineIndex]!.length()
                {
                    let r = .runeAt(.cursorPos)
                    pundo.runes.add(r.char)
                    pundo.styles.add(r.style)
                    discard .moveCursorRight(&pundo.selBeg)
                    .deleteTextPrivate(.cursorPos, pundo.selBeg, false)
                    .clearSelection()
                }
            }
        }

        // Append the character to the last undo
        pundo = (.undoMgr[.currentUndo - 1])!
        pundo.runes.add(c)

        // Get the style from the previous character
        let line = .lines[.cursorPos.lineIndex]!
        var st: u8
        if not .cursorPos.charPosInLine and line.length() do
            st = line.styles[0]
        elif .cursorPos.charPosInLine and .cursorPos.charPosInLine - 1 < line.length() do
            st = line.styles[.cursorPos.charPosInLine - 1]
        pundo.styles.add(st)

        // Do action
        if .hasSelRect
        {
            let sb = .selectionStart()
            let se = .selectionEnd()
            for caretI in sb.lineIndex to se.lineIndex
            {
                var cp = se
                cp.lineIndex = caretI
                if cp.charPosInLine > .lines[cp.lineIndex]!.length() do
                    continue
                .insertTextPrivate(&cp, Swag.makeString(&az[0], cpt), st)
            }

            .moveCursorRight(&.selBeg)
            .moveCursorRight(&.cursorPos)
        }
        else
        {
            .insertTextPrivate(&.cursorPos, Swag.makeString(&az[0], cpt), st)
            .clearSelection()
        }

        pundo.begSelectionAfter = .selBeg
        pundo.endSelectionAfter = .cursorPos
        .setModified(true)
    }

    // Inserts `txt` at the start of each selected line, as one undoable step.
    mtd insertBegLine(txt: string)
    {
        var first       = true
        let insertedLen = Utf8.countRunes(cast(const [..] u8) txt)

        var beg = .selectionStart()
        let end = .selectionEnd()

        var savepos0 = .selBeg
        var savepos1 = .cursorPos
        beg.charPosInLine = 0

        let multiline = end.lineIndex > beg.lineIndex

        while beg.lineIndex <= end.lineIndex
        {
            if beg.lineIndex == end.lineIndex and end.charPosInLine == 0 and multiline do
                break

            .pushUndo()
            if not first do
                .serialUndo -= 1

            .setCursorPos(beg)
            .selBeg = beg
            .insertText(txt)

            .popUndo()

            if beg.lineIndex == savepos0.lineIndex and savepos0.charPosInLine do
                savepos0.charPosInLine += insertedLen
            if beg.lineIndex == savepos1.lineIndex and savepos1.charPosInLine do
                savepos1.charPosInLine += insertedLen

            beg.lineIndex += 1
            first         = false
        }

        .selBeg = savepos0
        .setCursorPos(savepos1)

        // A dummy undo just to restore the selection
        if not first
        {
            .pushUndo()
            .serialUndo -= 1
            .undoRestoreSelection()
            .popUndo()
        }

        .setModified(true)
    }

    // Removes `txt`, or the whitespace up to the previous tab stop, before the text of each selected line.
    //
    // The removals form one undoable step. Unless `lastLine` is true, a selection within one line
    // that starts at its first column leaves the line unchanged.
    mtd deleteBegLine(txt: string, lastLine: bool)
    {
        let arrR   = Unicode.fromUtf8(txt)
        var first  = true
        let lenTxt = arrR.count
        var beg    = .selectionStart()
        let end    = .selectionEnd()

        if not lastLine
        {
            if beg.charPosInLine == 0 and beg.lineIndex == end.lineIndex do
                return
        }
        else
        {
            beg.charPosInLine = 0
        }

        let multiline = beg.lineIndex != end.lineIndex
        let size      = .xGlyphSize()
        var savepos0  = .selBeg
        var savepos1  = .cursorPos

        while beg.lineIndex <= end.lineIndex
        {
            // Go to the first non white character
            let line = .lines[beg.lineIndex]!
            if multiline
            {
                while beg.charPosInLine < line.length() and Unicode.isSpace(line.chars[beg.charPosInLine])
                {
                    if beg.charPosInLine + lenTxt <= line.length() and Slice.equals(line.chars.toSlice()[beg.charPosInLine until beg.charPosInLine + lenTxt], arrR.toSlice()) do
                        break
                    beg.charPosInLine += 1
                }
            }

            var beg1 = beg
            if beg.charPosInLine + lenTxt <= line.length() and Slice.equals(line.chars.toSlice()[beg.charPosInLine until beg.charPosInLine + lenTxt], arrR.toSlice())
            {
                beg1.charPosInLine += lenTxt
            }
            elif line.length() and beg.charPosInLine
            {
                if Unicode.isSpace(line.chars[beg.charPosInLine - 1])
                {
                    // X is the request position
                    var charPt = .cursorDisplayPosition(beg)
                    var x      = cast(f32) .tabAdvance(cast(s32) charPt.x)
                    x = (.tabSize * size.x) - x
                    if x == 0 do
                        x = .tabSize * size.x
                    x = charPt.x - x

                    while charPt.x > x and beg.charPosInLine and Unicode.isSpace(line.chars[beg.charPosInLine - 1])
                    {
                        beg.charPosInLine -= 1
                        charPt = .cursorDisplayPosition(beg)
                    }
                }
            }

            // Delete
            if beg1.charPosInLine != beg.charPosInLine
            {
                .pushUndo()
                if not first do
                    .serialUndo -= 1
                .selBeg = beg
                .setCursorPos(beg1)
                .deleteSelectionPrivate(beg, beg1, false)
                .popUndo()

                if beg.lineIndex == savepos0.lineIndex and savepos0.charPosInLine do
                    savepos0.charPosInLine -= beg1.charPosInLine - beg.charPosInLine
                if beg.lineIndex == savepos1.lineIndex and savepos1.charPosInLine do
                    savepos1.charPosInLine -= beg1.charPosInLine - beg.charPosInLine
            }

            first = false

            // Next line
            if beg.lineIndex == end.lineIndex do
                break
            beg.lineIndex     += 1
            beg.charPosInLine = 0
            if beg.lineIndex == end.lineIndex and end.charPosInLine == 0 do
                break
        }

        .selBeg = savepos0
        .setCursorPos(savepos1)

        // A dummy undo just to restore the selection
        if not first
        {
            .pushUndo()
            .serialUndo -= 1
            .undoRestoreSelection()
            .popUndo()
        }

        .setModified(true)
    }

    // Returns the size the whole document needs, margins and padding included, in logical pixels.
    mtd evaluateSize()->{ w: f32, h: f32 }
    {
        var result: retval

        let x = .xGlyphSize()

        result.h = cast(f32) (.lines.count * x.y)

        let fontR = .font().getFont(.styles[0].fontMode)
        if fontR
        {
            let font = nnFont(fontR)
            for l in .lines
            {
                let arr     = Painter.glyphs(l!.chars, font)
                let measure = Painter.measureString(arr, font)
                result.w = Math.max(result.w, measure.width)
            }
        }

        result.w += .leftMargin() + .rightMargin()
        result.h += .themeMetrics().richEdit_Padding * 2
        result.w += .themeMetrics().richEdit_Padding * 2
        return result
    }
}

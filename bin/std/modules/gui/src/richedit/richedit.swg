#global public

using Core, Pixel

// Selects rich edit flags.
#[Swag.EnumFlags]
enum RichEditFlags
{
    Zero = 0          // No flags are enabled.
    ReadOnly          // Enables read only.
    ShowFocusSel      // Enables show focus sel.
    CurLineBorder     // Enables cur line border.
    DrawBlanks        // Enables draw blanks.
    TabToSpaces       // Enables tab to spaces.
    WordWrap          // Enables word wrap.
    AutoLoseFocus     // Enables auto lose focus.
}

// Selects rich edit form.
enum RichEditForm
{
    RichEditCtrl     // Uses the rich edit ctrl form.
    Edit             // Uses the edit form.
}

// Represents rich edit mapping.
struct RichEditMapping
{
    key:       Input.Key          = undefined     // Key associated with this value.
    modifiers: Input.KeyModifiers = undefined     // Modifiers associated with this value.
    command:   RichEditCommand    = undefined     // Command associated with this value.
}

// Represents rich edit ctrl.
struct RichEditCtrl
{
    using frameWnd: FrameWnd                            // Embedded frame wnd state.
    richEdFlags         = RichEditFlags.Zero            // Rich ed flags associated with this value.
    lineSpacing:    f32                                 // Line spacing associated with this value.
    overwriteMode:  bool                                // Overwrite mode associated with this value.
    tabSize:        s32 = 4                             // Tab size associated with this value.
    marginLeft:     f32                                 // Margin left associated with this value.
    marginRight:    f32                                 // Margin right associated with this value.
    lexer:          #null IRichEditLexer                // Lexer associated with this value.
    form                = RichEditForm.RichEditCtrl     // Form associated with this value.
    sigIsReadOnly:  SigArray'func||(*bool)              // Signal emitted when is read only.
    sigChanged:     SigArray'func||(*RichEditCtrl)      // Signal emitted when changed.
    sigModified:    SigArray'func||(*RichEditCtrl)      // Signal emitted when modified.
    bkColorModel:   String                              // Bk color model associated with this value.

    styles:       [256] RichEditRuneStyle     // Styles associated with this value.
    stylesSelect: [2] RichEditRuneStyle       // Styles select associated with this value.
    cursorPos:    RichEditCursor              // Cursor pos associated with this value.
    selBeg:       RichEditCursor              // Sel beg associated with this value.
    lines:        ArrayPtr'RichEditLine       // Lines associated with this value.
    freeLines:    ArrayPtr'RichEditLine       // Free lines associated with this value.
    #[Swag.Late]
    scrollWnd: *ScrollWnd     // Scroll wnd associated with this value.
    #[Swag.Late]
    edView:       *RichEditView      // Ed view associated with this value.
    selRectangle: Math.Rectangle     // Sel rectangle associated with this value.

    hasSelRect:              bool     // Whether this value has sel rect.
    modified:                bool     // Modified associated with this value.
    recomputeScroll:         bool     // Recompute scroll associated with this value.
    dirtyFirstLineView:      bool     // Dirty first line view associated with this value.
    forceCaretVisible:       bool     // Force caret visible associated with this value.
    forceCaretVisibleCenter: bool     // Force caret visible center associated with this value.

    undoMgr:              ArrayPtr'RichEditUndo     // Undo mgr associated with this value.
    toUndo:               ArrayPtr'RichEditUndo     // To undo associated with this value.
    mapping:              Array'RichEditMapping     // Mapping associated with this value.
    currentUndo:          u64                       // Current undo associated with this value.
    undoCounter:          u64                       // Undo counter associated with this value.
    modifiedUndoMarker:   u64                       // Modified undo marker associated with this value.
    serialUndo:           u64                       // Serial undo associated with this value.
    countVisibleLines:    u64                       // Count visible lines associated with this value.
    firstVisibleLineView: u64                       // First visible line view associated with this value.
    lastVisibleLineView:  u64                       // Last visible line view associated with this value.
    clipFormat:           Clipboard.ValueFormat     // Clip format associated with this value.
    cursorPosUndo:        RichEditCursor            // Cursor pos undo associated with this value.
    selBegUndo:           RichEditCursor            // Sel beg undo associated with this value.
}

private impl IWnd for RichEditCtrl
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.ntfyKind == .ThemeChanged
        {
            .setDefaultStyles()
            if .lexer do
                .lexer.setupTheme(me)
        }
    }
}

private impl RichEditCtrl
{
    mtd getMarginLeft()->f32
    {
        return .marginLeft
    }

    mtd getMarginRight()->f32
    {
        return .marginRight
    }

    mtd setDefaultStyles()
    {
        let colors = .getThemeColors()
        for [i] in @countof(.styles) do
            .styles[i].colFg = colors.richEdit_Text
        .setForm(.RichEditCtrl)
    }

    mtd computeScrollY()
    {
        let size = .getXExtent()
        if !.recomputeScroll do
            return

        var y           = 0'f32
        var firstHidden = true
        .countVisibleLines = 0
        for [i] in @countof(.lines)
        {
            let ln = notnull .lines[i]
            ln.drawingRect.clear()

            if ln.isVisible()
            {
                .countVisibleLines    += 1
                ln.drawingRect.y      = y
                ln.drawingRect.height = size.y
                y                     += size.y
                firstHidden           = true
            }
            elif firstHidden
            {
                .countVisibleLines    += 1
                ln.drawingRect.y      = y
                ln.drawingRect.height = size.y
                y                     += size.y
                firstHidden           = false
            }
        }
    }

    mtd setModified(mdf: bool)
    {
        if mdf do
            .sigChanged.call(me)
        if .modified == mdf do
            return
        .modified = mdf
        .sigModified.call(me)
    }

    mtd resetModified()
    {
        .setModified(false)
        .modifiedUndoMarker = .currentUndo
    }

    // Performs the create operation.
    // Performs the create operation.
    #[Swag.Discardable]
    mtd newLine(index: u64)->*RichEditLine
    {
        var p: #null *RichEditLine

        if .freeLines.count do
            p = .freeLines.popBack()
        else do
            p = Memory.new'RichEditLine()

        let pn = notnull p
        pn.resetInternal()

        if .lines.count
        {
            let insLine = notnull (index == .lines.count ? .lines.back() : .lines[index])
            pn.drawingRect   = insLine.drawingRect
            pn.drawingRect.y += pn.drawingRect.height
        }

        .lines.insertAt(index, pn)
        .recomputeScroll = true

        return pn
    }

    mtd deleteLine(lineIndex: u64)
    {
        .freeLines.add(.lines[lineIndex])
        .lines.removeAtOrdered(lineIndex)
        .recomputeScroll = true
    }

    mtd getFirstVisibleLine()->u64
    {
        for [i] in .lines.count where (notnull .lines[i]).isVisible() do
            return i
        return 0
    }

    mtd getLastVisibleLine()->u64
    {
        if !.lines.count do
            return 0
        for var i = .lines.count - 1; i >= 0; i -= 0
        {
            if (notnull .lines[i]).isVisible() do
                return i
        }

        return 0
    }

    mtd getPreviousVisibleLine(lineIndex: u64)->u64
    {
        if !lineIndex do
            return 0
        var i = lineIndex - 1
        for
        {
            if (notnull .lines[i]).isVisible() do
                return i
            if !i do
                break
            i -= 1
        }

        return lineIndex
    }

    mtd getNextVisibleLine(lineIndex: u64)->u64
    {
        let count = .lines.count
        if lineIndex == count - 1 do
            return lineIndex

        var i = lineIndex + 1
        for
        {
            if (notnull .lines[i]).isVisible() do
                return i
            if i == count - 1 do
                break
            i += 1
        }

        return lineIndex
    }
}

impl RichEditCtrl
{
    // Creates a rich-text editor as a child of the requested window.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*RichEditCtrl
    {
        var pos = position
        if pos.height == 0 do
            pos.height = parent.getThemeMetrics().editBox_Height
        if pos.width == 0 do
            pos.width = parent.getThemeMetrics().editBox_Width

        let ed = Wnd.create'RichEditCtrl(parent, "", pos, id)

        with ed
        {
            .scrollWnd               = .createView'ScrollWnd()
            .scrollWnd.dockStyle     = .Center
            .scrollWnd.focusStrategy = .None
            .scrollWnd.setAllPaddings(.getThemeMetrics().richEdit_Padding)
            .scrollWnd.sigScrollPosChanged += func|ed|(scrollWnd, op, np)
            {
                if op.y != np.y do
                    ed.dirtyFirstLineView = true
            }

            .edView          = .scrollWnd.createView'RichEditView()
            .edView.ed       = ed
            .edView.wndFlags |= .NoScroll

            .setDefaultMapping()
            .setDefaultStyles()
        }

        return ed
    }

    // Sets focus.
    mtd setFocus()
    {
        .edView.setFocus()
    }

    // Set richedit flags
    mtd setRichEdFlags(flags: RichEditFlags)
    {
        .richEdFlags.set(flags)
        .recomputeScroll = true
        .invalidate()
    }

    // Set form
    mtd setForm(form: RichEditForm)
    {
        .form = form
        let colors = .getThemeColors()

        switch .form
        {
        case .RichEditCtrl:
            .style.setFont((notnull .parent).getTheme().res.fontDefaultFs)

            var mdlBk = .bkColorModel
            if .bkColorModel.length == 0 do
                mdlBk = String.from("$richEdit_Bk")

            .frameWnd.style.clearStyleSheetColors()
            .scrollWnd.style.clearStyleSheetColors()

            .frameWnd.style.addStyleSheetColors(Format.toString("frameWnd_FocusBk %", mdlBk))
            .frameWnd.style.addStyleSheetColors(Format.toString("frameWnd_Bk %", mdlBk))
            .scrollWnd.style.addStyleSheetColors(Format.toString("scrollBar_Bk %", mdlBk))

            .stylesSelect[0].colFg = colors.richEdit_SelText
            .stylesSelect[0].colBk = colors.richEdit_SelBk
            .stylesSelect[1].colFg = colors.richEdit_SelTextNoFocus
            .stylesSelect[1].colBk = colors.richEdit_SelBkNoFocus

        case .Edit:
            .style.clearFont()

            var mdlBk = .bkColorModel
            if .bkColorModel.length == 0 do
                mdlBk = String.from("$edit_Bk")

            .frameWnd.style.clearStyleSheetColors()
            .scrollWnd.style.clearStyleSheetColors()

            .frameWnd.style.addStyleSheetColors(Format.toString("frameWnd_FocusBk %", mdlBk))
            .frameWnd.style.addStyleSheetColors(Format.toString("frameWnd_Bk %", mdlBk))
            .scrollWnd.style.addStyleSheetColors(Format.toString("scrollBar_Bk %", mdlBk))

            .stylesSelect[0].colFg = colors.edit_Text
            .stylesSelect[0].colBk = colors.edit_SelectedBk
            .stylesSelect[1].colFg = 0
            .stylesSelect[1].colBk = 0
        }

        .invalidate()
    }

    // Returns true if the rich edit is read only
    mtd isReadOnly()->bool
    {
        var ro = false
        .sigIsReadOnly.call(&ro)
        return ro or .richEdFlags.has(.ReadOnly)
    }

    // Simulate a keyboard character pressed
    mtd charPressed(key: Input.Key, ch: rune, mdf: Input.KeyModifiers)
    {
        var isChar = false
        if mdf == .Zero and ch >= '0' and ch <= '9' do
            isChar = true

        // If there is a corresponding command,: nothing
        if !isChar
        {
            let cmd = .getMappingCommand(key, mdf)
            if cmd != .None do
                return
        }

        if .isReadOnly() do
            return

        var c = ch
        if c == '\r' do
            c = '\n'

        if c == '\n' and mdf.equals(.Zero) and .richEdFlags.has(.AutoLoseFocus) do
            return

        if .lexer and .lexer.insertRune(me, c) do
            return

        .insertRune(c)
        .forceCaretVisible = true
    }

    // Simulate a keyboard pressed
    mtd keyPressed(key: Input.Key, mdf: Input.KeyModifiers)
    {
        let cmd = .getMappingCommand(key, mdf)
        if cmd == .None do
            return
        .executeCommand(cmd)
        .forceCaretVisible = true
        .invalidate()
    }

    // Associate a lexer
    mtd setLexer(lex: IRichEditLexer)
    {
        .lexer = lex
        .lexer.setup(me)
        .lexer.setupTheme(me)
    }

    // Lex the full text
    mtd lexAll()
    {
        if !.lexer do
            return

        var prev, cur, next: #null *RichEditLine
        for [i] in @countof(.lines)
        {
            cur  = notnull .lines[i]
            next = i == .lines.count - 1 ? null : .lines[i + 1]
            .lexer.compute(prev, notnull cur, next)
            prev = cur
        }
    }
}

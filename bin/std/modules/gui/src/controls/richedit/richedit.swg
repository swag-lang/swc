#global public

using Core, Pixel

// Configures editing, selection display, wrapping, and keyboard behavior.
#[Swag.EnumFlags]
enum RichEditFlags
{
    None = 0          // No flags are enabled.
    ReadOnly          // Rejects operations that would modify the document.
    ShowFocusSel      // Keeps the selection visible while the editor is unfocused.
    CurLineBorder     // Draws a border around the line containing the caret.
    DrawBlanks        // Draws visible markers for spaces and tab characters.
    TabToSpaces       // Inserts spaces instead of a tab character.
    WordWrap          // Wraps long logical lines to the available view width.
    AutoLoseFocus     // Releases focus when an unmodified Enter key is pressed.
}

// Selects the editor's theme treatment.
enum RichEditForm
{
    RichEditCtrl     // Uses the framed rich-text-editor appearance.
    Edit             // Uses the compact single-field editor appearance.
}

// Associates one keyboard shortcut with an editor command.
#[Swag.Opaque, Swag.NoDoc]
struct RichEditMapping
{
    public
    {
        key:       Input.Key
        modifiers: Input.KeyModifiers
        command:   RichEditCommand
    }
}

// Provides a multiline rich-text editor with styling, selection, undo, and pluggable lexing.
struct RichEditCtrl
{
    public
    {
        using frameWnd:           FrameWnd                                                   // Embedded frame behavior and presentation.
        flags = RichEditFlags.None                                                           // Active editor behavior flags.
        lineSpacing:              f32                                                        // Extra vertical spacing, in logical pixels, between display lines.
        overwriteMode:            bool                                                       // Whether typed text replaces the rune under the caret.
        tabSize:                  s32 = 4                                                    // Width of a tab stop in space advances.
        marginLeft:               f32                                                        // Blank space between the view and the left text edge.
        marginRight:              f32                                                        // Blank space between the right text edge and the view.
        lexer:                    IRichEditLexer?                                            // Optional lexer responsible for assigning style indices.
        form  = RichEditForm.RichEditCtrl                                                    // Current theme treatment.
        sigIsReadOnly:            SigArray'func||(*bool)                                     // Lets owners impose read-only state in addition to `flags`.
        sigChanged:               SigArray'func||(*RichEditCtrl)                             // Emitted after document content changes.
        sigModified:              SigArray'func||(*RichEditCtrl)                             // Emitted when the modified state toggles.
        sigScrollPositionChanged: SigArray'func||(*RichEditCtrl, Math.Point, Math.Point)     // Emitted with old and new scroll positions.
        backgroundColorModel:     String                                                     // Optional theme color expression used for the editor background.

        // Appearance of each style index a lexer can assign to a rune, and of the selection. Fill
        // these in to give the control its syntax colors.
        styles:       [256] RichEditRuneStyle     // Style of each index a lexer assigns.
        stylesSelect: [2] RichEditRuneStyle       // Style of selected text, unfocused then focused.
    }

    // The document and everything the control derives from it: the line pool, the cursor and
    // selection, the visible window, and the undo timeline. Edit through the methods and
    // connect to the signals; this state only makes sense together.
    cursorPos:      RichEditCursor            // Caret, the moving end of the selection.
    selBeg:         RichEditCursor            // Anchor, the fixed end of the selection.
    lines:          ArrayPtr'RichEditLine     // Logical lines of the document.
    freeLines:      ArrayPtr'RichEditLine     // Removed lines kept for reuse.
    late scrollWnd: *ScrollWnd                // Scrolling container of the text view.
    late edView:    *RichEditView             // View that paints the text and reads the input.
    selRectangle:   Math.Rectangle            // Bounds of a rectangular selection.

    hasSelRect:              bool     // Whether the selection is rectangular.
    modified:                bool     // Whether the document differs from its last saved state.
    recomputeWrap:           bool     // Reflow every logical line after flags or font metrics change.
    recomputeScroll:         bool     // Whether the scroll extent must be computed again.
    dirtyFirstLineView:      bool     // Whether the first visible line must be found again.
    forceCaretVisible:       bool     // Whether the next layout scrolls the caret into view.
    forceCaretVisibleCenter: bool     // Whether that scroll centers the caret.

    undoMgr:                ArrayPtr'RichEditUndo     // Committed undo records, oldest first.
    toUndo:                 ArrayPtr'RichEditUndo     // Records of the open undo group, committed by `popUndo`.
    mapping:                Array'RichEditMapping     // Keyboard shortcuts and the commands they run.
    currentUndo:            u64                       // Number of committed records currently applied.
    undoCounter:            u64                       // Nesting depth of `pushUndo` groups.
    modifiedUndoMarker:     u64                       // Undo position at which the document was last marked unmodified.
    serialUndo:             u64                       // Group number given to the next committed records.
    countVisibleLines:      u64                       // Number of lines not hidden by a fold.
    firstVisibleLineView:   u64                       // First line the view shows.
    lastVisibleLineView:    u64                       // Last line the view shows.
    loadedContentHeight:    f32                       // Height laid out from the text currently held in memory.
    residentContentOffset:  f32                       // Virtual y origin of the resident text window.
    estimatedContentHeight: f32                       // Optional larger virtual height published by a streaming owner.
    clipFormat:             Clipboard.ValueFormat     // Clipboard format carrying the rune styles of a copy.
    cursorPosUndo:          RichEditCursor            // Caret when the outermost undo group opened.
    selBegUndo:             RichEditCursor            // Anchor when the outermost undo group opened.
}

private impl IWnd for RichEditCtrl
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged
        {
            .recomputeWrap = true
            .setDefaultStyles()
            .lexer?.setupTheme(me)
        }
    }
}

private impl RichEditCtrl
{
    mtd leftMargin()->f32 => .marginLeft

    mtd rightMargin()->f32 => .marginRight

    mtd setDefaultStyles()
    {
        let colors = .themeColors()
        for i in .styles.count do
            .styles[i].colFg = colors.richEdit_Text
        .setForm(.RichEditCtrl)
    }

    mtd computeScrollY()
    {
        let size = .xGlyphSize()
        if not .recomputeScroll do
            return

        var y = .residentContentOffset
        var firstHidden = true
        .countVisibleLines = 0
        for i in .lines.count
        {
            let ln = .lines[i]!
            ln.drawingRect.clear()

            if ln.isVisible()
            {
                .countVisibleLines    += 1
                ln.drawingRect.y      = y
                ln.drawingRect.height = size.y
                y += size.y
                firstHidden           = true
            }
            elif firstHidden
            {
                .countVisibleLines    += 1
                ln.drawingRect.y      = y
                ln.drawingRect.height = size.y
                y += size.y
                firstHidden           = false
            }
        }
    }

    mtd setModified(modifiers: bool)
    {
        if modifiers do
            .sigChanged.call(me)
        if .modified == modifiers do
            return
        .modified = modifiers
        .sigModified.call(me)
    }

    mtd resetModified()
    {
        .setModified(false)
        .modifiedUndoMarker = .currentUndo
    }

    // Creates an empty rich text editor.
    #[Swag.Discardable]
    mtd newLine(index: u64)->*RichEditLine
    {
        var p: *RichEditLine?

        if .freeLines.count do
            p = .freeLines.popBack()
        else do
            p = Memory.new'RichEditLine()

        let pn = p!
        pn.resetInternal()

        if .lines.count
        {
            let insLine = (index == .lines.count ? .lines.back() : .lines[index])!
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

    mtd firstVisibleLine()->u64
    {
        for i in .lines.count where .lines[i]!.isVisible() do
            return i
        return 0
    }

    mtd lastVisibleLine()->u64
    {
        for i in reversed(.lines.count) where .lines[i]!.isVisible() do
            return i
        return 0
    }

    mtd previousVisibleLine(lineIndex: u64)->u64
    {
        if not lineIndex do
            return 0
        var i = lineIndex - 1
        for
        {
            if .lines[i]!.isVisible() do
                return i
            if not i do
                break
            i -= 1
        }

        return lineIndex
    }

    mtd nextVisibleLine(lineIndex: u64)->u64
    {
        let count = .lines.count
        if lineIndex == count - 1 do
            return lineIndex

        var i = lineIndex + 1
        for
        {
            if .lines[i]!.isVisible() do
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
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*RichEditCtrl
    {
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().editBox_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().editBox_Width

        with let ed = Wnd.create'RichEditCtrl(parent, "", pos, id)
        {
            // One stop of the keyboard traversal for the whole editor, on the view that owns the
            // caret and the key mapping.
            .focusPolicy         = .Tab
            .wndFlags            |= .NoFocusRing
            .scrollWnd           = .createView'ScrollWnd()
            .scrollWnd.dockStyle = .Center
            .scrollWnd.setAllPaddings(.themeMetrics().richEdit_Padding)
            .scrollWnd.sigScrollPositionChanged += func|ed|(scrollWnd, op, np)
            {
                if op.y != np.y do
                    ed.dirtyFirstLineView = true
                ed.sigScrollPositionChanged.call(ed, op, np)
            }

            .edView             = .scrollWnd.createView'RichEditView()
            .edView.ed          = ed
            .edView.focusPolicy = .Inner
            .edView.wndFlags    |= .NoScroll
            .focusDelegate      = .edView

            .setDefaultMapping()
            .setDefaultStyles()
        }

        return ed
    }

    // Replaces the behavior flags and refreshes layout and painting.
    mtd setFlags(flags: RichEditFlags)
    {
        .flags.set(flags)
        .recomputeWrap   = true
        .recomputeScroll = true
        .invalidate()
    }

    // Applies one of the predefined editor theme treatments.
    mtd setForm(form: RichEditForm)
    {
        .form = form
        let colors = .themeColors()

        // An explicit background color model wins over the one each form defaults to.
        var mdlBk = .backgroundColorModel
        switch .form
        {
        case .RichEditCtrl:
            .style.setFont(.parent!.theme().res.fontDefaultFs)
            if mdlBk.isEmpty() do
                mdlBk = String.from("$richEdit_Bk")
            .stylesSelect[0].colFg = colors.richEdit_SelText
            .stylesSelect[0].colBk = colors.richEdit_SelBk
            .stylesSelect[1].colFg = colors.richEdit_SelTextNoFocus
            .stylesSelect[1].colBk = colors.richEdit_SelBkNoFocus

        case .Edit:
            .style.clearFont()
            if mdlBk.isEmpty() do
                mdlBk = String.from("$edit_Bk")
            .stylesSelect[0].colFg = colors.edit_Text
            .stylesSelect[0].colBk = colors.edit_SelectedBk
            .stylesSelect[1].colFg = 0
            .stylesSelect[1].colBk = 0
        }

        .frameWnd.style.clearStyleSheetColors()
        .scrollWnd.style.clearStyleSheetColors()
        .frameWnd.style.addStyleSheetColors(Format.toString("frameWnd_FocusBk %", mdlBk))
        .frameWnd.style.addStyleSheetColors(Format.toString("frameWnd_Bk %", mdlBk))
        .scrollWnd.style.addStyleSheetColors(Format.toString("scrollBar_Bk %", mdlBk))
        .invalidate()
    }

    // Returns whether the editor rejects edits, through its flags or a [[Gui.RichEditCtrl.sigIsReadOnly]] handler.
    mtd isReadOnly()->bool
    {
        var ro = false
        .sigIsReadOnly.call(&ro)
        return ro or .flags.has(.ReadOnly)
    }

    // Returns the current viewport origin in document coordinates.
    mtd const scrollPosition()->Math.Point => .scrollWnd.scrollPosition()

    // Moves the viewport to `position`, clamped to the current scrollable document.
    mtd setScrollPosition(position: Math.Point)
    {
        .scrollWnd.setScrollPos(position)
    }

    // Returns the complete scrollable document rectangle.
    mtd const scrollableClientRect()->Math.Rectangle => .scrollWnd.scrollableClientRect()

    // Returns the height laid out from the text currently held by the editor.
    //
    // A streaming owner can compare this value with its consumed input before publishing an
    // estimated full height through [[Gui.RichEditCtrl.setEstimatedDocumentHeight]].
    mtd const loadedDocumentHeight()->f32 => .loadedContentHeight

    // Sets a provisional full document height for incrementally supplied text.
    //
    // The editor always keeps enough room for the text it already holds. A positive estimate can
    // make the scrollbar represent unloaded text without retaining that text in memory; zero
    // clears the estimate. Appending text preserves the current viewport while the estimate is
    // refined.
    mtd setEstimatedDocumentHeight(height: f32)
    {
        .residentContentOffset  = 0
        .estimatedContentHeight = Math.max(height, 0)
        .scrollWnd.setScrollSize(.scrollWnd.scrollSize.x, Math.max(.loadedContentHeight, .estimatedContentHeight))
        .edView.invalidate()
    }

    // Places the resident text at `offset` inside a larger virtual document of `height`.
    //
    // This lets file-backed viewers reveal a distant window without materializing the bytes that
    // precede it. The next layout pass positions lines and the caret in those virtual coordinates.
    mtd setVirtualDocumentRange(offset, height: f32)
    {
        let origin = Math.max(offset, 0)
        let extent = Math.max(height, origin + .loadedContentHeight)
        if .residentContentOffset == origin and .estimatedContentHeight == extent do
            return
        .residentContentOffset  = origin
        .estimatedContentHeight = extent
        .recomputeScroll        = true
        .dirtyFirstLineView     = true
        .scrollWnd.setScrollSize(.scrollWnd.scrollSize.x, .estimatedContentHeight)
        .edView.invalidate()
    }

    // Processes a typed character the way the keyboard does.
    //
    // A key combination bound to a command is left to [[Gui.RichEditCtrl.keyPressed]]. Otherwise,
    // unless the editor is read-only, the lexer may consume `ch`, and the text receives it.
    mtd charPressed(key: Input.Key, ch: rune, modifiers: Input.KeyModifiers)
    {
        var isChar = false
        if modifiers == .None and ch >= '0' and ch <= '9' do
            isChar = true

        // A key combination bound to a command is not text.
        if not isChar
        {
            let cmd = .commandForShortcut(key, modifiers)
            if cmd != .None do
                return
        }

        if .isReadOnly() do
            return

        var c = ch
        if c == '\r' do
            c = '\n'

        if c == '\n' and modifiers.equals(.None) and .flags.has(.AutoLoseFocus) do
            return

        if .lexer and .lexer.insertRune(me, c) do
            return

        .insertRune(c)
        .forceCaretVisible = true
    }

    // Runs the command bound to the key combination, if any, as the keyboard does.
    mtd keyPressed(key: Input.Key, modifiers: Input.KeyModifiers)
    {
        let cmd = .commandForShortcut(key, modifiers)
        if cmd == .None do
            return
        .executeCommand(cmd)
        .forceCaretVisible = true
        .invalidate()
    }

    // Installs `lex` as the lexer and lets it set up its styles for the current theme.
    mtd setLexer(lex: IRichEditLexer)
    {
        .lexer = lex
        .lexer.setup(me)
        .lexer.setupTheme(me)
    }

    // Runs the lexer over every line, in order.
    mtd lexAll()
    {
        if not .lexer do
            return

        var prev, cur, next: *RichEditLine?
        for i in .lines.count
        {
            cur  = .lines[i]!
            next = i == .lines.count - 1 ? null : .lines[i + 1]
            .lexer.compute(prev, cur, next)
            prev = cur
        }
    }
}

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
        key:       Input.Key          = undefined
        modifiers: Input.KeyModifiers = undefined
        command:   RichEditCommand    = undefined
    }
}

// Provides a multiline rich-text editor with styling, selection, undo, and pluggable lexing.
struct RichEditCtrl
{
    public
    {
        using frameWnd:           FrameWnd                                                   // Embedded frame wnd state.
        flags = RichEditFlags.None                                                           // Active editor behavior flags.
        lineSpacing:              f32                                                        // Extra vertical spacing, in logical pixels, between display lines.
        overwriteMode:            bool                                                       // Whether typed text replaces the rune under the caret.
        tabSize:                  s32 = 4                                                    // Width of a tab stop in space advances.
        marginLeft:               f32                                                        // Blank space between the view and the left text edge.
        marginRight:              f32                                                        // Blank space between the right text edge and the view.
        lexer:                    #null IRichEditLexer                                       // Optional lexer responsible for assigning style indices.
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

        // The document and everything the control derives from it: the line pool, the cursor and
        // selection, the visible window, and the undo timeline. Edit through the methods and
        // connect to the signals; this state only makes sense together.
        internal
        {
            cursorPos: RichEditCursor            // Cursor pos associated with this value.
            selBeg:    RichEditCursor            // Sel beg associated with this value.
            lines:     ArrayPtr'RichEditLine     // Lines associated with this value.
            freeLines: ArrayPtr'RichEditLine     // Free lines associated with this value.
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

            undoMgr:                ArrayPtr'RichEditUndo     // Undo mgr associated with this value.
            toUndo:                 ArrayPtr'RichEditUndo     // To undo associated with this value.
            mapping:                Array'RichEditMapping     // Mapping associated with this value.
            currentUndo:            u64                       // Current undo associated with this value.
            undoCounter:            u64                       // Undo counter associated with this value.
            modifiedUndoMarker:     u64                       // Modified undo marker associated with this value.
            serialUndo:             u64                       // Serial undo associated with this value.
            countVisibleLines:      u64                       // Count visible lines associated with this value.
            firstVisibleLineView:   u64                       // First visible line view associated with this value.
            lastVisibleLineView:    u64                       // Last visible line view associated with this value.
            loadedContentHeight:    f32                       // Height laid out from the text currently held in memory.
            estimatedContentHeight: f32                       // Optional larger virtual height published by a streaming owner.
            clipFormat:             Clipboard.ValueFormat     // Clip format associated with this value.
            cursorPosUndo:          RichEditCursor            // Cursor pos undo associated with this value.
            selBegUndo:             RichEditCursor            // Sel beg undo associated with this value.
        }
    }
}

private impl IWnd for RichEditCtrl
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged
        {
            .setDefaultStyles()
            if .lexer do
                .lexer.setupTheme(me)
        }
    }
}

private impl RichEditCtrl
{
    mtd leftMargin()->f32
    {
        return .marginLeft
    }

    mtd rightMargin()->f32
    {
        return .marginRight
    }

    mtd setDefaultStyles()
    {
        let colors = .themeColors()
        for i in @countof(.styles) do
            .styles[i].colFg = colors.richEdit_Text
        .setForm(.RichEditCtrl)
    }

    mtd computeScrollY()
    {
        let size = .xGlyphSize()
        if !.recomputeScroll do
            return

        var y           = 0'f32
        var firstHidden = true
        .countVisibleLines = 0
        for i in @countof(.lines)
        {
            let ln = .lines[i]!
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
        var p: #null *RichEditLine

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
        if !.lines.count do
            return 0
        for var i = .lines.count - 1; i >= 0; i -= 0
        {
            if .lines[i]!.isVisible() do
                return i
        }

        return 0
    }

    mtd previousVisibleLine(lineIndex: u64)->u64
    {
        if !lineIndex do
            return 0
        var i = lineIndex - 1
        for
        {
            if .lines[i]!.isVisible() do
                return i
            if !i do
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
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*RichEditCtrl
    {
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().editBox_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().editBox_Width

        let ed = Wnd.create'RichEditCtrl(parent, "", pos, id)

        with ed
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
        .recomputeScroll = true
        .invalidate()
    }

    // Applies one of the predefined editor theme treatments.
    mtd setForm(form: RichEditForm)
    {
        .form = form
        let colors = .themeColors()

        switch .form
        {
        case .RichEditCtrl:
            .style.setFont(.parent!.theme().res.fontDefaultFs)

            var mdlBk = .backgroundColorModel
            if .backgroundColorModel.length == 0 do
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

            var mdlBk = .backgroundColorModel
            if .backgroundColorModel.length == 0 do
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
        .estimatedContentHeight = Math.max(height, 0)
        .scrollWnd.setScrollSize(.scrollWnd.scrollSize.x, Math.max(.loadedContentHeight, .estimatedContentHeight))
        .edView.invalidate()
    }

    // Simulate a keyboard character pressed
    mtd charPressed(key: Input.Key, ch: rune, modifiers: Input.KeyModifiers)
    {
        var isChar = false
        if modifiers == .None and ch >= '0' and ch <= '9' do
            isChar = true

        // If there is a corresponding command,: nothing
        if !isChar
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

    // Simulate a keyboard pressed
    mtd keyPressed(key: Input.Key, modifiers: Input.KeyModifiers)
    {
        let cmd = .commandForShortcut(key, modifiers)
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
        for i in @countof(.lines)
        {
            cur  = .lines[i]!
            next = i == .lines.count - 1 ? null : .lines[i + 1]
            .lexer.compute(prev, cur!, next)
            prev = cur
        }
    }
}

#global public

using Core

// Selects rich edit command.
public enum RichEditCommand
{
    None                // No option is selected.
    CursorLeft          // Selects cursor left.
    CursorRight         // Selects cursor right.
    CursorUp            // Selects cursor up.
    CursorDown          // Selects cursor down.
    CursorStartLine     // Selects cursor start line.
    CursorEndLine       // Selects cursor end line.
    CursorStartFile     // Selects cursor start file.
    CursorEndFile       // Selects cursor end file.
    CursorWordLeft      // Selects cursor word left.
    CursorWordRight     // Selects cursor word right.
    CursorPageUp        // Selects cursor page up.
    CursorPageDown      // Selects cursor page down.

    // CMD_CURSOR_MATCH_PAIR
    ScrollLineUp       // Selects scroll line up.
    ScrollLineDown     // Selects scroll line down.
    DeleteLeft         // Selects delete left.
    DeleteRight        // Selects delete right.
    DeleteLine         // Selects delete line.

    // CMD_EDIT_DELETE_LINE
    EditTabulation         // Selects edit tabulation.
    EditBackTabulation     // Selects edit back tabulation.
    DeleteWordLeft         // Selects delete word left.
    DeleteWordRight        // Selects delete word right.

    // CMD_EDIT_DELETE_LINE_LEFT
    // CMD_EDIT_DELETE_LINE_RIGHT
    ToggleOverwrite     // Selects toggle overwrite.
    ClipboardCopy       // Selects clipboard copy.
    ClipboardPaste      // Selects clipboard paste.
    ClipboardCut        // Selects clipboard cut.
    Undo                // Selects undo.
    Redo                // Selects redo.
    SelectRuneLeft      // Selects select rune left.
    SelectRuneRight     // Selects select rune right.
    SelectRuneUp        // Selects select rune up.
    SelectRuneDown      // Selects select rune down.
    SelectRectLeft      // Selects select rect left.
    SelectRectRight     // Selects select rect right.
    SelectRectUp        // Selects select rect up.
    SelectRectDown      // Selects select rect down.
    SelectStartLine     // Selects select start line.
    SelectEndLine       // Selects select end line.
    SelectStartFile     // Selects select start file.
    SelectEndFile       // Selects select end file.
    SelectAllFile       // Selects select all file.
    SelectWordLeft      // Selects select word left.
    SelectWordRight     // Selects select word right.
    SelectPageUp        // Selects select page up.
    SelectPageDown      // Selects select page down.
}

impl RichEditCtrl
{
    // Performs the clear mapping operation.
    mtd clearMapping()
    {
        .mapping.clear()
    }

    // Adds mapping.
    mtd addMapping(key: Input.Key, mdf: Input.KeyModifiers, cmd: RichEditCommand)
    {
        var m: RichEditMapping
        m.key       = key
        m.modifiers = mdf
        m.command   = cmd
        .mapping.add(m)
    }

    // Returns mapping command.
    mtd getMappingCommand(key: Input.Key, mdf: Input.KeyModifiers)->RichEditCommand
    {
        for &p in .mapping
        {
            if p.key == key and p.modifiers == mdf do
                return p.command
        }

        return RichEditCommand.None
    }

    // Sets default mapping.
    mtd setDefaultMapping()
    {
        .addMapping(.Left, .Zero, .CursorLeft)
        .addMapping(.Left, .Shift, .SelectRuneLeft)
        .addMapping(.Left, .Control, .CursorWordLeft)
        .addMapping(.Left, .CtrlShift, .SelectWordLeft)
        .addMapping(.Left, .Alt, .SelectRectLeft)
        .addMapping(.Right, .Zero, .CursorRight)
        .addMapping(.Right, .Shift, .SelectRuneRight)
        .addMapping(.Right, .Control, .CursorWordRight)
        .addMapping(.Right, .CtrlShift, .SelectWordRight)
        .addMapping(.Right, .Alt, .SelectRectRight)
        .addMapping(.Up, .Zero, .CursorUp)
        .addMapping(.Up, .Shift, .SelectRuneUp)
        .addMapping(.Up, .Control, .ScrollLineUp)
        .addMapping(.Up, .Alt, .SelectRectUp)
        .addMapping(.Down, .Zero, .CursorDown)
        .addMapping(.Down, .Shift, .SelectRuneDown)
        .addMapping(.Down, .Shift, .SelectRuneDown)
        .addMapping(.Down, .Control, .ScrollLineDown)
        .addMapping(.Down, .Alt, .SelectRectDown)
        .addMapping(.PageUp, .Zero, .CursorPageUp)
        .addMapping(.PageUp, .Shift, .SelectPageUp)
        .addMapping(.PageDown, .Zero, .CursorPageDown)
        .addMapping(.PageDown, .Shift, .SelectPageDown)
        .addMapping(.Home, .Zero, .CursorStartLine)
        .addMapping(.Home, .Control, .CursorStartFile)
        .addMapping(.Home, .Shift, .SelectStartLine)
        .addMapping(.Home, .CtrlShift, .SelectStartFile)
        .addMapping(.End, .Zero, .CursorEndLine)
        .addMapping(.End, .Control, .CursorEndFile)
        .addMapping(.End, .Shift, .SelectEndLine)
        .addMapping(.End, .CtrlShift, .SelectEndFile)
        .addMapping(.Back, .Zero, .DeleteLeft)
        .addMapping(.Back, .Control, .DeleteWordLeft)
        .addMapping(.Delete, .Zero, .DeleteRight)
        .addMapping(.Delete, .Control, .DeleteWordRight)
        .addMapping(.Tab, .Zero, .EditTabulation)
        .addMapping(.Tab, .Shift, .EditBackTabulation)
        .addMapping(.Insert, .Zero, .ToggleOverwrite)
        .addMapping(.Insert, .Control, .ClipboardCopy)
        .addMapping(.Insert, .Shift, .ClipboardPaste)
        .addMapping(.A, .Control, .SelectAllFile)
        .addMapping(.C, .Control, .ClipboardCopy)
        .addMapping(.L, .Control, .DeleteLine)
        .addMapping(.V, .Control, .ClipboardPaste)
        .addMapping(.X, .Control, .ClipboardCut)
        .addMapping(.Y, .Control, .Redo)
        .addMapping(.Z, .Control, .Undo)
    }

    // Execute a command
    mtd executeCommand(cmd: RichEditCommand)
    {
        switch cmd
        {
        case .CursorLeft:
            if .isSelectionEmpty() do
                .moveCursorLeft(&.cursorPos)
            else do
                .setCursorPos(.getBegSelection())
            .clearSelection()

        case .CursorRight:
            if .isSelectionEmpty() do
                .moveCursorRight(&.cursorPos)
            else do
                .setCursorPos(.getEndSelection())
            .clearSelection()

        case .CursorUp:
            if !.isSelectionEmpty()
            {
                let pt = .getCursorDisplayPos(.cursorPos)
                .setCursorPos(.getBegSelection())
                .moveCursorUp(&.cursorPos, pt)
            }
            else do
                .moveCursorUp(&.cursorPos)
            .clearSelection()

        case .CursorDown:
            if !.isSelectionEmpty()
            {
                let pt = .getCursorDisplayPos(.cursorPos)
                .setCursorPos(.getEndSelection())
                .moveCursorDown(&.cursorPos, pt)
            }
            else do
                .moveCursorDown(&.cursorPos)
            .clearSelection()

        case .CursorStartLine:
            .moveCursorStartLine(&.cursorPos)
            .clearSelection()

        case .CursorEndLine:
            .moveCursorEndLine(&.cursorPos)
            .clearSelection()

        case .CursorStartFile:
            .moveCursorStartFile(&.cursorPos)
            .clearSelection()

        case .CursorEndFile:
            .moveCursorEndFile(&.cursorPos)
            .clearSelection()

        case .CursorWordLeft:
            .moveCursorWordLeft(&.cursorPos)
            .clearSelection()

        case .CursorWordRight:
            .moveCursorWordRight(&.cursorPos, true)
            .clearSelection()

        case .CursorPageUp:
            .moveCursorPageUp(&.cursorPos)
            .clearSelection()

        case .CursorPageDown:
            .moveCursorPageDown(&.cursorPos)
            .clearSelection()

        case .ScrollLineUp:
            .scrollLineUp()

        case .ScrollLineDown:
            .scrollLineDown()

        case .SelectRuneLeft:
            .moveCursorLeft(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectRuneRight:
            .moveCursorRight(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectRuneUp:
            .moveCursorUp(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectRuneDown:
            .moveCursorDown(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectStartLine:
            .moveCursorStartLine(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectEndLine:
            .moveCursorEndLine(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectStartFile:
            .moveCursorStartFile(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectEndFile:
            .moveCursorEndFile(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectAllFile:
            .moveCursorStartFile(&.selBeg)
            .moveCursorEndFile(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectWordLeft:
            .moveCursorWordLeft(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectWordRight:
            .moveCursorWordRight(&.cursorPos, false)
            .setRectangularSelection(false)

        case .SelectPageUp:
            .moveCursorPageUp(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectPageDown:
            .moveCursorPageDown(&.cursorPos)
            .setRectangularSelection(false)

        case .SelectRectLeft:
            var cp = .cursorPos
            .moveCursorLeft(&cp)
            if cp.lineIndex == .cursorPos.lineIndex
            {
                .cursorPos = cp
                .setRectangularSelection(true)
            }

        case .SelectRectRight:
            var cp = .cursorPos
            .moveCursorRight(&cp)
            if cp.lineIndex == .cursorPos.lineIndex
            {
                .cursorPos = cp
                .setRectangularSelection(true)
            }

        case .SelectRectUp:
            var cp = .cursorPos
            .moveCursorUp(&cp)
            if cp.charPosInLine == .cursorPos.charPosInLine
            {
                .cursorPos = cp
                .setRectangularSelection(true)
            }

        case .SelectRectDown:
            var cp = .cursorPos
            .moveCursorDown(&cp)
            if cp.charPosInLine == .cursorPos.charPosInLine
            {
                .cursorPos = cp
                .setRectangularSelection(true)
            }

        case .DeleteLeft:
            if .isReadOnly() do
                return
            .deleteLeft()

        case .DeleteRight:
            if .isReadOnly() do
                return
            .deleteRight()

        case .DeleteWordLeft:
            if .isReadOnly() do
                return
            .deleteWordLeft()

        case .DeleteWordRight:
            if .isReadOnly() do
                return
            .deleteWordRight()

        case .DeleteLine:
            if .isReadOnly() do
                return
            .deleteLine()

        case .EditTabulation:
            if .isReadOnly() do
                return
            if .getBegSelection().lineIndex == .getEndSelection().lineIndex
            {
                .pushUndo()
                .deleteSelection()
                .insertText("\t")
                .popUndo()
            }
            else do
                .insertBegLine("\t")

        case .EditBackTabulation:
            if .isReadOnly() do
                return
            .deleteBegLine("\t", false)

        case .Undo:
            if .isReadOnly() do
                return
            .undo()

        case .Redo:
            if .isReadOnly() do
                return
            .redo()

        case .ToggleOverwrite:
            .overwriteMode = !.overwriteMode
            .invalidate()

        case .ClipboardCopy:
            .copyToClipboard()

        case .ClipboardPaste:
            if .isReadOnly() do
                return
            .pasteFromClipboard()

        case .ClipboardCut:
            if .isReadOnly() do
                return
            .copyToClipboard()
            .deleteSelection()
        }
    }
}

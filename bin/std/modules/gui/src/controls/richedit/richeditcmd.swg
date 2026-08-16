#global public

using Core

// Identifies an editor action that can be bound to a keyboard shortcut.
public enum RichEditCommand
{
    None                // No option is selected.
    CursorLeft          // Moves the caret one rune left.
    CursorRight         // Moves the caret one rune right.
    CursorUp            // Moves the caret one display line up.
    CursorDown          // Moves the caret one display line down.
    CursorStartLine     // Moves the caret to the start of its logical line.
    CursorEndLine       // Moves the caret to the end of its logical line.
    CursorStartFile     // Moves the caret to the start of the document.
    CursorEndFile       // Moves the caret to the end of the document.
    CursorWordLeft      // Moves the caret to the previous word boundary.
    CursorWordRight     // Moves the caret to the next word boundary.
    CursorPageUp        // Moves the caret one viewport page up.
    CursorPageDown      // Moves the caret one viewport page down.

    // CMD_CURSOR_MATCH_PAIR
    ScrollLineUp       // Scrolls the viewport one display line up.
    ScrollLineDown     // Scrolls the viewport one display line down.
    DeleteLeft         // Deletes the selection or the rune before the caret.
    DeleteRight        // Deletes the selection or the rune after the caret.
    DeleteLine         // Deletes the logical line containing the caret.

    // CMD_EDIT_DELETE_LINE
    EditTabulation         // Indents the selection or inserts a tabulation.
    EditBackTabulation     // Removes one indentation level from selected lines.
    DeleteWordLeft         // Deletes through the previous word boundary.
    DeleteWordRight        // Deletes through the next word boundary.

    // CMD_EDIT_DELETE_LINE_LEFT
    // CMD_EDIT_DELETE_LINE_RIGHT
    ToggleOverwrite     // Toggles insert and overwrite modes.
    ClipboardCopy       // Copies the selection to the clipboard.
    ClipboardPaste      // Inserts compatible clipboard text.
    ClipboardCut        // Copies then deletes the selection.
    Undo                // Reverts the most recent undo group.
    Redo                // Reapplies the next reverted undo group.
    SelectRuneLeft      // Extends the linear selection one rune left.
    SelectRuneRight     // Extends the linear selection one rune right.
    SelectRuneUp        // Extends the linear selection one display line up.
    SelectRuneDown      // Extends the linear selection one display line down.
    SelectRectLeft      // Extends the rectangular selection one rune left.
    SelectRectRight     // Extends the rectangular selection one rune right.
    SelectRectUp        // Extends the rectangular selection one display line up.
    SelectRectDown      // Extends the rectangular selection one display line down.
    SelectStartLine     // Extends the selection to the start of the logical line.
    SelectEndLine       // Extends the selection to the end of the logical line.
    SelectStartFile     // Extends the selection to the start of the document.
    SelectEndFile       // Extends the selection to the end of the document.
    SelectAllFile       // Selects the complete document.
    SelectWordLeft      // Extends the selection to the previous word boundary.
    SelectWordRight     // Extends the selection to the next word boundary.
    SelectPageUp        // Extends the selection one viewport page up.
    SelectPageDown      // Extends the selection one viewport page down.
}

impl RichEditCtrl
{
    // Removes every keyboard shortcut mapping.
    mtd clearMapping()
    {
        .mapping.clear()
    }

    // Binds `key` and `modifiers` to `cmd`; existing entries are retained.
    mtd addMapping(key: Input.Key, modifiers: Input.KeyModifiers, cmd: RichEditCommand)
    {
        var m: RichEditMapping
        m.key       = key
        m.modifiers = modifiers
        m.command   = cmd
        .mapping.add(m)
    }

    // Returns the command bound to a shortcut, or [RichEditCommand.None] when unbound.
    mtd commandForShortcut(key: Input.Key, modifiers: Input.KeyModifiers)->RichEditCommand
    {
        for &p in .mapping
        {
            if p.key == key and p.modifiers == modifiers do
                return p.command
        }

        return RichEditCommand.None
    }

    // Replaces all mappings with the editor's conventional shortcut table.
    mtd setDefaultMapping()
    {
        .clearMapping()
        .addMapping(.Left, .None, .CursorLeft)
        .addMapping(.Left, .Shift, .SelectRuneLeft)
        .addMapping(.Left, .Control, .CursorWordLeft)
        .addMapping(.Left, .CtrlShift, .SelectWordLeft)
        .addMapping(.Left, .Alt, .SelectRectLeft)
        .addMapping(.Right, .None, .CursorRight)
        .addMapping(.Right, .Shift, .SelectRuneRight)
        .addMapping(.Right, .Control, .CursorWordRight)
        .addMapping(.Right, .CtrlShift, .SelectWordRight)
        .addMapping(.Right, .Alt, .SelectRectRight)
        .addMapping(.Up, .None, .CursorUp)
        .addMapping(.Up, .Shift, .SelectRuneUp)
        .addMapping(.Up, .Control, .ScrollLineUp)
        .addMapping(.Up, .Alt, .SelectRectUp)
        .addMapping(.Down, .None, .CursorDown)
        .addMapping(.Down, .Shift, .SelectRuneDown)
        .addMapping(.Down, .Control, .ScrollLineDown)
        .addMapping(.Down, .Alt, .SelectRectDown)
        .addMapping(.PageUp, .None, .CursorPageUp)
        .addMapping(.PageUp, .Shift, .SelectPageUp)
        .addMapping(.PageDown, .None, .CursorPageDown)
        .addMapping(.PageDown, .Shift, .SelectPageDown)
        .addMapping(.Home, .None, .CursorStartLine)
        .addMapping(.Home, .Control, .CursorStartFile)
        .addMapping(.Home, .Shift, .SelectStartLine)
        .addMapping(.Home, .CtrlShift, .SelectStartFile)
        .addMapping(.End, .None, .CursorEndLine)
        .addMapping(.End, .Control, .CursorEndFile)
        .addMapping(.End, .Shift, .SelectEndLine)
        .addMapping(.End, .CtrlShift, .SelectEndFile)
        .addMapping(.Back, .None, .DeleteLeft)
        .addMapping(.Back, .Control, .DeleteWordLeft)
        .addMapping(.Delete, .None, .DeleteRight)
        .addMapping(.Delete, .Control, .DeleteWordRight)
        .addMapping(.Tab, .None, .EditTabulation)
        .addMapping(.Tab, .Shift, .EditBackTabulation)
        .addMapping(.Insert, .None, .ToggleOverwrite)
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
                .setCursorPos(.selectionStart())
            .clearSelection()

        case .CursorRight:
            if .isSelectionEmpty() do
                .moveCursorRight(&.cursorPos)
            else do
                .setCursorPos(.selectionEnd())
            .clearSelection()

        case .CursorUp:
            if !.isSelectionEmpty()
            {
                let pt = .cursorDisplayPosition(.cursorPos)
                .setCursorPos(.selectionStart())
                .moveCursorUp(&.cursorPos, pt)
            }
            else do
                .moveCursorUp(&.cursorPos)
            .clearSelection()

        case .CursorDown:
            if !.isSelectionEmpty()
            {
                let pt = .cursorDisplayPosition(.cursorPos)
                .setCursorPos(.selectionEnd())
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
            if .selectionStart().lineIndex == .selectionEnd().lineIndex
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

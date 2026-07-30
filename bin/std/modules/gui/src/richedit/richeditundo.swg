#global public

using Core

// Selects rich edit undo type.
enum RichEditUndoType
{
    Delete        // Selects delete.
    Insert        // Selects insert.
    Selection     // Selects selection.
    Show          // Selects show.
    Hide          // Selects hide.
}

// Represents rich edit undo.
struct RichEditUndo
{
    type:        RichEditUndoType = Selection     // Type associated with this value.
    concatChars: bool                             // Concat chars associated with this value.
    selBeg:      RichEditCursor                   // Sel beg associated with this value.
    cursorPos:   RichEditCursor                   // Cursor pos associated with this value.
    runes:       Array'rune                       // Runes associated with this value.
    styles:      Array'u8                         // Styles associated with this value.
    serial:      u64                              // Serial associated with this value.
    hasSelRect:  bool                             // Whether this value has sel rect.

    begSelectionBefore: RichEditCursor     // Beg selection before associated with this value.
    endSelectionBefore: RichEditCursor     // End selection before associated with this value.
    begSelectionAfter:  RichEditCursor     // Beg selection after associated with this value.
    endSelectionAfter:  RichEditCursor     // End selection after associated with this value.
}

private impl RichEditCtrl
{
    mtd getLastModificationUndo()->u64
    {
        var count = .currentUndo
        while count
        {
            if ((notnull .undoMgr[count - 1]).type == .Delete) or
               ((notnull .undoMgr[count - 1]).type == .Insert) do
                return count
            count -= 1
        }

        return count
    }

    mtd resetUndo()
    {
        // Its impossible to restore an unmodified state in that case
        if .modifiedUndoMarker > .currentUndo do
            .modifiedUndoMarker = Swag.U64.Max

        while .undoMgr.count > .currentUndo
        {
            let back = .undoMgr.popBack()
            Memory.delete(back)
        }
    }
}

impl RichEditCtrl
{
    // Performs the clear undo operation.
    mtd clearUndo()
    {
        .undoMgr.clear()
        .toUndo.clear()
        .currentUndo        = 0
        .serialUndo         = 0
        .modifiedUndoMarker = Swag.U64.Max
    }

    // Performs the push undo operation.
    mtd pushUndo()
    {
        // Nested undo,: not increment serial
        if .undoCounter == 0
        {
            .serialUndo    += 1
            .selBegUndo    = .selBeg
            .cursorPosUndo = .cursorPos
        }

        .undoCounter += 1
    }

    // Performs the pop undo operation.
    mtd popUndo()
    {
        Debug.assert(.undoCounter != 0)
        .undoCounter -= 1

        for [i] in .toUndo.count
        {
            let undo = notnull .toUndo[i]
            undo.serial             = .serialUndo
            undo.begSelectionBefore = .selBegUndo
            undo.endSelectionBefore = .cursorPosUndo
            undo.begSelectionAfter  = .selBeg
            undo.endSelectionAfter  = .cursorPos
            .undoMgr.add(undo)
            .currentUndo += 1
        }

        .toUndo.count = 0
    }

    // Returns whether this value can undo.
    mtd canUndo()->bool
    {
        if .undoMgr.count == 0 do
            return false
        if !.currentUndo do
            return false
        return true
    }

    // Performs the undo operation.
    mtd undo()
    {
        if !.canUndo() do
            return

        .currentUndo -= 1
        var undo   = notnull .undoMgr[.currentUndo]
        let serial = undo.serial

        for
        {
            if undo.type == .Delete
            {
                .selBeg    = undo.selBeg
                .cursorPos = undo.cursorPos
                var cp = .getBegSelection()
                .insertTextPrivate(&cp, undo.runes, undo.styles, undo.hasSelRect)
            }
            elif undo.type == .Insert
            {
                .selBeg    = undo.selBeg
                .cursorPos = undo.cursorPos
                .setRectangularSelection(undo.hasSelRect)
                .computeRectangularSelection(.cursorPos, undo.begSelectionAfter)
                .deleteTextPrivate(.cursorPos, undo.begSelectionAfter, undo.hasSelRect)
            }

            .selBeg    = undo.begSelectionBefore
            .cursorPos = undo.endSelectionBefore
            .setRectangularSelection(undo.hasSelRect)
            if !.currentUndo do
                break
            undo = notnull .undoMgr[.currentUndo - 1]
            if undo.serial != serial do
                break
            .currentUndo -= 1
        }

        if .getLastModificationUndo() == .modifiedUndoMarker do
            .setModified(false)
        else do
            .setModified(true)
        .computeScrollY()
    }

    // Returns whether this value can redo.
    mtd canRedo()->bool
    {
        if .undoMgr.count == 0 do
            return false
        if .currentUndo == .undoMgr.count do
            return false
        return true
    }

    // Performs the redo operation.
    mtd redo()
    {
        if !.canRedo() do
            return

        var undo   = notnull .undoMgr[.currentUndo]
        let serial = undo.serial
        .currentUndo += 1

        for
        {
            if undo.type == .Delete
            {
                .selBeg = undo.selBeg
                .setCursorPos(undo.cursorPos)
                .setRectangularSelection(undo.hasSelRect)
                .computeRectangularSelection(.getBegSelection(), .getEndSelection())
                .deleteTextPrivate(.getBegSelection(), .getEndSelection(), undo.hasSelRect)
            }
            elif undo.type == .Insert
            {
                .selBeg = undo.selBeg
                .setCursorPos(undo.cursorPos)
                var cp = .getBegSelection()
                .insertTextPrivate(&cp, undo.runes, undo.styles, undo.hasSelRect)
            }

            .selBeg = undo.begSelectionAfter
            .setCursorPos(undo.endSelectionAfter)
            .setRectangularSelection(undo.hasSelRect)

            if .currentUndo == .undoMgr.count do
                break
            undo = notnull .undoMgr[.currentUndo]
            if undo.serial != serial do
                break
            .currentUndo += 1
        }

        if .getLastModificationUndo() == .modifiedUndoMarker do
            .setModified(false)
        else do
            .setModified(true)
        .computeScrollY()
    }
}

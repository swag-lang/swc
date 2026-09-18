#global public

using Core

// Selects what a [[Gui.RichEditUndo]] record reverts.
enum RichEditUndoType
{
    Delete        // Text was deleted; undoing inserts it back.
    Insert        // Text was inserted; undoing deletes it.
    Selection     // Only the selection changed.
    Show          // Not produced by the editor.
    Hide          // Not produced by the editor.
}

// Stores one reversible rich-edit text or selection operation.
struct RichEditUndo
{
    public
    {
        type:        RichEditUndoType = Selection     // What the record reverts.
        concatChars: bool                             // Whether typed runes may still be appended to this record.
        selBeg:      RichEditCursor                   // Selection anchor where the edit applies.
        cursorPos:   RichEditCursor                   // Caret where the edit applies.
        runes:       Array'rune                       // Runes inserted or deleted.
        styles:      Array'u8                         // Style index of each rune in `runes`.
        serial:      u64                              // Group number; records sharing it undo and redo together.
        hasSelRect:  bool                             // Whether the edit applied to a rectangular selection.

        begSelectionBefore: RichEditCursor     // Selection anchor before the edit.
        endSelectionBefore: RichEditCursor     // Caret before the edit.
        begSelectionAfter:  RichEditCursor     // Selection anchor after the edit.
        endSelectionAfter:  RichEditCursor     // Caret after the edit.
    }
}

private impl RichEditCtrl
{
    mtd lastModificationUndoIndex()->u64
    {
        var count = .currentUndo
        while count
        {
            if (.undoMgr[count - 1]!.type == .Delete) or
               (.undoMgr[count - 1]!.type == .Insert) do
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
    // Clears both undo and redo history.
    mtd clearUndo()
    {
        .undoMgr.clear()
        .toUndo.clear()
        .currentUndo        = 0
        .serialUndo         = 0
        .modifiedUndoMarker = Swag.U64.Max
    }

    // Opens an undo group: the edits made until the matching [[Gui.RichEditCtrl.popUndo]] undo and redo as one step.
    //
    // Groups nest; only the outermost one starts a new step and captures the selection.
    mtd pushUndo()
    {
        // A nested group joins the step its outermost group started.
        if .undoCounter == 0
        {
            .serialUndo    += 1
            .selBegUndo    = .selBeg
            .cursorPosUndo = .cursorPos
        }

        .undoCounter += 1
    }

    // Closes the undo group [[Gui.RichEditCtrl.pushUndo]] opened and commits the edits recorded in it.
    mtd popUndo()
    {
        Swag.assert(.undoCounter != 0)
        .undoCounter -= 1

        for i in .toUndo.count
        {
            let undo = .toUndo[i]!
            undo.serial = .serialUndo
            undo.begSelectionBefore = .selBegUndo
            undo.endSelectionBefore = .cursorPosUndo
            undo.begSelectionAfter  = .selBeg
            undo.endSelectionAfter  = .cursorPos
            .undoMgr.add(undo)
            .currentUndo += 1
        }

        .toUndo.count = 0
    }

    // Returns whether an edit can be undone.
    mtd canUndo()->bool => not .undoMgr.isEmpty() and .currentUndo != 0

    // Reverts the newest recorded edit.
    mtd undo()
    {
        if not .canUndo() do
            return

        .currentUndo -= 1
        var undo   = .undoMgr[.currentUndo]!
        let serial = undo.serial

        for
        {
            if undo.type == .Delete
            {
                .selBeg    = undo.selBeg
                .cursorPos = undo.cursorPos
                var cp = .selectionStart()
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
            if not .currentUndo do
                break
            undo = (.undoMgr[.currentUndo - 1])!
            if undo.serial != serial do
                break
            .currentUndo -= 1
        }

        if .lastModificationUndoIndex() == .modifiedUndoMarker do
            .setModified(false)
        else do
            .setModified(true)
        .computeScrollY()
    }

    // Returns whether an undone edit can be redone.
    mtd canRedo()->bool => not .undoMgr.isEmpty() and .currentUndo != .undoMgr.count

    // Reapplies the newest reverted edit.
    mtd redo()
    {
        if not .canRedo() do
            return

        var undo   = .undoMgr[.currentUndo]!
        let serial = undo.serial
        .currentUndo += 1

        for
        {
            if undo.type == .Delete
            {
                .selBeg = undo.selBeg
                .setCursorPos(undo.cursorPos)
                .setRectangularSelection(undo.hasSelRect)
                .computeRectangularSelection(.selectionStart(), .selectionEnd())
                .deleteTextPrivate(.selectionStart(), .selectionEnd(), undo.hasSelRect)
            }
            elif undo.type == .Insert
            {
                .selBeg = undo.selBeg
                .setCursorPos(undo.cursorPos)
                var cp = .selectionStart()
                .insertTextPrivate(&cp, undo.runes, undo.styles, undo.hasSelRect)
            }

            .selBeg = undo.begSelectionAfter
            .setCursorPos(undo.endSelectionAfter)
            .setRectangularSelection(undo.hasSelRect)

            if .currentUndo == .undoMgr.count do
                break
            undo = .undoMgr[.currentUndo]!
            if undo.serial != serial do
                break
            .currentUndo += 1
        }

        if .lastModificationUndoIndex() == .modifiedUndoMarker do
            .setModified(false)
        else do
            .setModified(true)
        .computeScrollY()
    }
}

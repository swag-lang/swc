impl Capture
{
    // Allocates a new (not yet pushed) Undo command. To group several commands into one
    // undo/redo step, mint a shared id with .undoMgr.newSerial() and pass it to pushUndo.
    mtd newUndo(kind: UndoKind)->*Undo
    {
        let ptr = Memory.new'Undo()
        ptr.kind = kind
        return ptr
    }

    mtd canUndo()->bool => .undoMgr.canUndo()
    mtd canRedo()->bool => .undoMgr.canRedo()

    mtd undo()
    {
        .undoMgr.undo()

        // During an interactive drag, apply() calls undo() every move to re-apply the
        // move from scratch; the per-form partial invalidate handles the repaint.
        if not .interactiveMove do
            .editView?.invalidate()
    }

    mtd redo()
    {
        .undoMgr.redo()

        if not .interactiveMove do
            .editView?.invalidate()
    }

    // Pushes a command onto the undo timeline. A non-zero 'serial' groups this command with the
    // others sharing that value into one undo/redo step (0 = its own fresh group); get a shared
    // id from .undoMgr.newSerial().
    mtd pushUndo(u: *Undo, serial: u64 = 0)
    {
        u.capture = me

        // Capture the "before" state, then hand the command to the generic manager which
        // discards the redo tail (freeing those commands) and applies this one via redo()/doIt().
        u.init()
        .undoMgr.pushCmd(u, serial, apply: true)
    }
}

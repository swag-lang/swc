#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Counter every `IncCommand` of these tests moves.
var g_undoCounter: s32

// A trivial command that adds `delta` to a shared counter on redo and subtracts it on undo.
//
// It exercises the generic `UndoManager` independently of any widget.
struct IncCommand
{
    delta: s32
}

impl IUndoCommand for IncCommand
{
    mtd impl redo()
    {
        g_undoCounter += .delta
    }

    mtd impl undo()
    {
        g_undoCounter -= .delta
    }
}

// Pushing applies a command, undo and redo walk the timeline, `canUndo` and `canRedo` track its
// edges, and a push after an undo discards and frees the redo tail.
#test
{
    var mgr: UndoManager
    g_undoCounter = 0

    mgr.push(IncCommand{5})
    Swag.assert(g_undoCounter == 5)
    mgr.push(IncCommand{3})
    Swag.assert(g_undoCounter == 8 and mgr.count() == 2)

    mgr.undo()
    Swag.assert(g_undoCounter == 5 and mgr.canUndo() and mgr.canRedo())
    mgr.undo()
    Swag.assert(g_undoCounter == 0 and not mgr.canUndo())

    mgr.redo()
    Swag.assert(g_undoCounter == 5)

    // A new push after an undo truncates the redo tail.
    mgr.undo()     // -> 0
    mgr.push(IncCommand{10})
    Swag.assert(g_undoCounter == 10 and mgr.count() == 1 and not mgr.canRedo())
}

// Commands sharing a serial are undone and redone together, as one step.
#test
{
    var mgr: UndoManager
    g_undoCounter = 0

    let serial = mgr.newSerial()
    let a      = Memory.new'IncCommand()
    a.delta = 1
    let b = Memory.new'IncCommand()
    b.delta = 2
    mgr.pushCmd(a, serial)
    mgr.pushCmd(b, serial)
    Swag.assert(g_undoCounter == 3 and mgr.count() == 2)

    mgr.undo()     // both revert in one step
    Swag.assert(g_undoCounter == 0 and not mgr.canUndo())
    mgr.redo()     // both re-apply in one step
    Swag.assert(g_undoCounter == 3 and not mgr.canRedo())
}

// `clear` drops the whole history.
#test
{
    var mgr: UndoManager
    g_undoCounter = 0

    mgr.push(IncCommand{4})
    mgr.push(IncCommand{4})
    Swag.assert(mgr.count() == 2)

    mgr.clear()
    Swag.assert(mgr.count() == 0 and not mgr.canUndo() and not mgr.canRedo())
}

#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A trivial command that adds/subtracts a delta from a shared counter, to exercise the
// generic UndoManager independently of any widget.
var g_undoCounter: s32

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

// push() applies on push; undo/redo walk the timeline; canUndo/canRedo track the edges; a
// push after undo discards (and frees) the redo tail.
#test
{
    var mgr: UndoManager
    g_undoCounter = 0

    mgr.push(IncCommand{5})
    @assert(g_undoCounter == 5)
    mgr.push(IncCommand{3})
    @assert(g_undoCounter == 8 and mgr.count() == 2)

    mgr.undo()
    @assert(g_undoCounter == 5 and mgr.canUndo() and mgr.canRedo())
    mgr.undo()
    @assert(g_undoCounter == 0 and !mgr.canUndo())

    mgr.redo()
    @assert(g_undoCounter == 5)

    // A new push after an undo truncates the redo tail.
    mgr.undo()     // -> 0
    mgr.push(IncCommand{10})
    @assert(g_undoCounter == 10 and mgr.count() == 1 and !mgr.canRedo())
}

// Commands sharing a serial are undone/redone together as one step.
#test
{
    var mgr: UndoManager
    g_undoCounter = 0

    let serial = mgr.newSerial()
    let a = Memory.new'IncCommand()
    a.delta = 1
    let b = Memory.new'IncCommand()
    b.delta = 2
    mgr.pushCmd(cast(IUndoCommand) a, serial)
    mgr.pushCmd(cast(IUndoCommand) b, serial)
    @assert(g_undoCounter == 3 and mgr.count() == 2)

    mgr.undo()     // both revert in one step
    @assert(g_undoCounter == 0 and !mgr.canUndo())
    mgr.redo()     // both re-apply in one step
    @assert(g_undoCounter == 3 and !mgr.canRedo())
}

// clear() drops the whole history.
#test
{
    var mgr: UndoManager
    g_undoCounter = 0

    mgr.push(IncCommand{4})
    mgr.push(IncCommand{4})
    @assert(mgr.count() == 2)

    mgr.clear()
    @assert(mgr.count() == 0 and !mgr.canUndo() and !mgr.canRedo())
}

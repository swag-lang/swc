#global public

using Core

// A small, reusable undo/redo manager for GUI apps.
//
// It is command-based and completely agnostic of *what* it undoes: each step is an
// IUndoCommand whose redo()/undo() apply and revert one atomic change. The manager owns
// the commands (heap allocated), keeps them on a linear timeline, and truncates the redo
// tail when a new command is pushed after some undos.
//
// Commands can be grouped into a single user-visible step through a shared serial: undo()
// and redo() process every command that shares the serial of the timeline edge in one shot
// (so e.g. "align 5 shapes" is one undo). Use newSerial() to get a fresh group id and pass
// it to pushCmd for every command of the group; 0 means "give me my own fresh group".
//
// The property grid (Properties) and any app (e.g. captme) build on this by wrapping pushCmd
// with their own command structs implementing IUndoCommand.

// One atomic, reversible change. redo() (re)applies it, undo() reverts it. The concrete
// command struct carries whatever state it needs to do both.
interface IUndoCommand
{
    // (Re)apply the change. Called on redo, and once on push when pushCmd's 'apply' is true.
    mtd redo();

    // Revert the change.
    mtd undo();
}

// One entry of the undo timeline: the owned command plus the group it belongs to.
struct UndoStep
{
    serial: u64
    cmd:    IUndoCommand
}

struct UndoManager
{
    steps:     Array'UndoStep
    next:      u64     // index just past the last applied step (the redo tail starts here)
    serialGen: u64
}

impl UndoManager
{
    mtd opDrop()
    {
        .clear()
    }

    // Drop every command and reset the timeline.
    mtd clear()
    {
        for &s in .steps do
            Memory.delete(@dataof(s.cmd), @kindof(s.cmd))
        .steps.clear()
        .next      = 0
        .serialGen = 0
    }

    // A fresh group id, to push several commands as one undo/redo step.
    mtd newSerial()->u64
    {
        .serialGen += 1
        return .serialGen
    }

    // Number of live steps on the timeline (including the redo tail).
    mtd count()->u64
    {
        return .steps.count
    }

    mtd canUndo()->bool
    {
        return .next != 0
    }

    mtd canRedo()->bool
    {
        return .next != .steps.count
    }

    // Push a command onto the timeline. Any redo tail is discarded first (its commands are
    // freed). 'serial' groups this command with the others sharing the same value (0 = its
    // own fresh group). When 'apply' is true the command's redo() is invoked right away to
    // make the change effective; pass false when the caller has already applied it.
    mtd pushCmd(cmd: IUndoCommand, serial: u64 = 0, apply = true)
    {
        // Discard the redo tail.
        while .steps.count > .next
        {
            let back = .steps.popBack()
            Memory.delete(@dataof(back.cmd), @kindof(back.cmd))
        }

        var s = serial
        if s == 0 do
            s = .newSerial()

        .steps.add({s, cmd})
        .next = .steps.count

        if apply do
            cmd.redo()
    }

    // Allocate a heap copy of 'cmd' (which must implement IUndoCommand), push it as its own
    // group and apply it. Convenience for the common single-command case.
    mtd(T) push(cmd: T)
    {
        let p = Memory.new'T()
        dref p = cmd
        .pushCmd(cast(IUndoCommand) p, 0, true)
    }

    // Revert the step at the timeline edge (and every command sharing its serial).
    mtd undo()
    {
        if !.canUndo() do
            return

        let serial = .steps[.next - 1].serial
        while .next and .steps[.next - 1].serial == serial
        {
            .next -= 1
            .steps[.next].cmd.undo()
        }
    }

    // Re-apply the next step (and every command sharing its serial).
    mtd redo()
    {
        if !.canRedo() do
            return

        let serial = .steps[.next].serial
        while .next != .steps.count and .steps[.next].serial == serial
        {
            .steps[.next].cmd.redo()
            .next += 1
        }
    }
}

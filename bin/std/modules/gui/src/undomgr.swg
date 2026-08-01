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

// One atomic, reversible change owned by an [[UndoManager]].
interface IUndoCommand
{
    // Applies or reapplies the change.
    mtd redo()

    // Reverts the change.
    mtd undo()
}

#[Swag.Opaque, Swag.NoDoc]
struct UndoStep
{
    serial: u64              // Group identifier shared by commands undone together.
    cmd:    IUndoCommand     // Owned reversible command.
}

// Owns a linear undo/redo timeline with optional command grouping.
struct UndoManager
{
    internal
    {
        steps:     Array'UndoStep     // Owned timeline, including its redo tail.
        next:      u64                // Index immediately after the last applied command.
        serialGen: u64                // Last allocated command-group identifier.
    }
}

impl UndoManager
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .clear()
    }

    // Drops every owned command and resets the timeline.
    mtd clear()
    {
        for &s in .steps do
            Memory.delete(@dataof(s.cmd), @kindof(s.cmd))
        .steps.clear()
        .next      = 0
        .serialGen = 0
    }

    // Returns a fresh group identifier for commands that must be undone and redone together.
    mtd newSerial()->u64
    {
        .serialGen += 1
        return .serialGen
    }

    // Returns the number of commands on the timeline, including the redo tail.
    mtd const count()->u64
    {
        return .steps.count
    }

    // Returns the number of commands currently applied.
    mtd const appliedCount()->u64 => .next

    // Reports whether at least one command group can be undone.
    mtd const canUndo()->bool
    {
        return .next != 0
    }

    // Reports whether at least one command group can be redone.
    mtd const canRedo()->bool
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

    // Allocates a heap copy of `cmd` (which must implement [[IUndoCommand]]), pushes it as its own
    // group and apply it. Convenience for the common single-command case.
    mtd(T) push(cmd: T)
    {
        let p = Memory.new'T()
        dref p = cmd
        .pushCmd(cast(IUndoCommand) p, 0, true)
    }

    // Reverts the previous command group, if any.
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

    // Reapplies the next command group, if any.
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

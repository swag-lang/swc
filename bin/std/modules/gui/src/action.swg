// Identifies the window and command currently evaluated by an action.
public struct ActionContext
{
    wnd: #null *Wnd     // Window receiving the command, when available.
    id:  WndId          // Command identifier.
}

// Handles command discovery, presentation-state updates, and execution.
public interface IActionUI
{
    // Reports whether this action handles the command in `context`.
    mtd accept(cxt: ActionContext)->bool

    // Updates presentation state for an accepted command.
    mtd update(cxt: ActionContext, evt: *CommandStateEvent)->bool

    // Executes an accepted command.
    mtd execute(cxt: ActionContext)->bool
}

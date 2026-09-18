// Identifies the window and command currently evaluated by an action.
public struct ActionContext
{
    public
    {
        wnd: *Wnd?     // Window receiving the command, when available.
        id:  WndId     // Command identifier.
    }
}

// Handles command discovery, presentation-state updates, and execution.
public interface IActionUI
{
    // Reports whether this action handles the command in `cxt`.
    mtd accept(cxt: ActionContext)->bool

    // Fills `evt` with the presentation state of an accepted command.
    //
    // Returns `true` when the state is complete: the actions registered after this one and the
    // window's own [[Gui.IWnd.onComputeStateEvent]] are then not asked.
    mtd update(cxt: ActionContext, evt: *CommandStateEvent)->bool

    // Executes an accepted command.
    //
    // Returns `true` when the command is handled: the actions registered after this one and the
    // window's own [[Gui.IWnd.onCommandEvent]] are then not asked.
    mtd execute(cxt: ActionContext)->bool
}

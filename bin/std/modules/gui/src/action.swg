// Represents action context.
public struct ActionContext
{
    wnd: #null *Wnd     // Wnd associated with this value.
    id:  WndId          // Id associated with this value.
}

// Defines the operations supported by i action ui.
public interface IActionUI
{
    // Performs the accept operation.
    mtd accept(cxt: ActionContext)->bool

    // Performs the update operation.
    mtd update(cxt: ActionContext, evt: *CommandStateEvent)->bool

    // Performs the execute operation.
    mtd execute(cxt: ActionContext)->bool
}

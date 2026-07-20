public struct ActionContext
{
    wnd:     #null *Wnd
    id:      #nonull WndId
}

public interface IActionUI
{
    mtd accept(cxt: ActionContext)->bool;
    mtd update(cxt: ActionContext, evt: #nonull *CommandStateEvent)->bool;
    mtd execute(cxt: ActionContext)->bool;
}

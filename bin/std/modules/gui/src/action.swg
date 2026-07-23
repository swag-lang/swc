public struct ActionContext
{
    wnd: #null *Wnd
    id:  WndId
}

public interface IActionUI
{
    mtd accept(cxt: ActionContext)->bool;
    mtd update(cxt: ActionContext, evt: *CommandStateEvent)->bool;
    mtd execute(cxt: ActionContext)->bool;
}

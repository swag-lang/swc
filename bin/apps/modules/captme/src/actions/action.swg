// Every command id minted by newCmdId embeds the owning scope name
// ("ActionSelection.SelectAll"), so an action accepts a command exactly when the
// id starts with its own scope. This mixin generates the accept() implementation
// from that rule; invoke it inside the 'impl IActionUI for X' block.
#[Swag.Mixin]
func acceptOwnCmdIds()
{
    #ast "mtd impl accept(cxt: ActionContext)->bool { return Utf8.startsWith(cxt.id, \"" ++ #scopename ++ ".\") }"
}

// What a purely-mechanical command needs to be enabled; evaluated by updateFromTable
enum CmdNeed
{
    Nothing
    Capture       // an opened capture
    Selection     // at least one selected form
    MultiSel      // at least two selected forms
    Forms         // a capture with at least one form
    PixSel        // at least one selected pixel-selection form
}

struct CmdDesc
{
    id:               WndId
    name:             string
    need:             CmdNeed = .Nothing
    hideDisabled:     bool     // hidden follows disabled (contextual commands)
}

// The update() body for the purely-mechanical commands of an action: set the name
// declared in the table and derive the enabled state from the declared need.
// Returns false when the command is not in the table, so the caller can handle
// its custom commands afterwards.
func updateFromTable(cxt: ActionContext, evt: *CommandStateEvent, table: const [..] CmdDesc)->bool
{
    for &d in table
    {
        if d.id != cxt.id do
            continue

        let main    = cast(*MainWnd) notnull cxt.wnd
        let capture = main.getCapture()

        var disabled = false
        #[Swag.Complete]
        switch d.need
        {
        case Nothing:
            break
        case Capture:
            disabled = !capture
        case Selection:
            disabled = !capture or !capture.selection.count
        case MultiSel:
            disabled = !capture or capture.selection.count < 2
        case Forms:
            disabled = !capture or !capture.forms.count
        case PixSel:
            disabled = !capture or !capture.hasSelectedPixSel()
        }

        evt.setFlags |= .Name | .Disabled
        evt.name     = d.name
        evt.disabled = disabled

        if d.hideDisabled
        {
            evt.setFlags |= .Hidden
            evt.hidden = disabled
        }

        return true
    }

    return false
}

using Gui

// The commands that pick the editor tool.
struct ActionToolMode {}

impl ActionToolMode
{
    newCmdId("Shape")
    newCmdId("Line")
    newCmdId("Arrow")
    newCmdId("Poly")
    newCmdId("Text")
    newCmdId("Favorites")
    newCmdId("Selection")
    newCmdId("Draw")
    newCmdId("Highlight")
    newCmdId("Step")
    newCmdId("Img")
    newCmdId("PixSel")
    newCmdId("Callout")
}

impl ActionToolMode
{
    // Returns the tool the command `id` takes in hand.
    func modeOf(id: WndId)->EditMode
    {
        for mode in EditMode where mode.command() == id do
            return mode
        unreachable
    }
}

impl IActionUI for ActionToolMode
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = mainWndOf(cxt)
        let mode = ActionToolMode.modeOf(cxt.id)
        evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
        evt.icon          = main.toolIcon(mode.glyph())
        evt.name          = mode.name()
        evt.toolTip       = mode.tip()
        evt.checked       = main.editMode == mode

        // Dragging a selection rectangle is the selection tool at work, whatever tool is in hand.
        if mode == .Selection
        {
            let capture = main.getCapture()
            evt.checked = evt.checked or (capture and capture.drawSelRect)
        }

        // The tools belong to the editor: in the library their letters would change it unseen.
        evt.updatedFields |= .Disabled
        evt.disabled      = main.libraryMode

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = mainWndOf(cxt)
        main.editMode = ActionToolMode.modeOf(cxt.id)
        main.updateState()
        return true
    }
}

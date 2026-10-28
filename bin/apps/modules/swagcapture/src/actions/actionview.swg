using Gui

// The commands that choose what the window shows: the lens, the inspector, the strip of recent
// captures, and what lies outside the capture box.
struct ActionView {}

impl ActionView
{
    newCmdId("Clip")
    newCmdId("Lens")
    newCmdId("Inspector")
    newCmdId("Recent")
}

impl IActionUI for ActionView
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = main.getCapture()
        switch cxt.id
        {
        case .Clip:
            evt.updatedFields |= .Name | .Disabled | .Checked
            evt.name          = appStrings().act_HideOutsideBox
            evt.checked       = main.editorOptions.clipToSelection

            // We advertise .Disabled, so provide the state: clipping to the
            // selection is meaningless without a capture.
            evt.disabled = not capture

        // The lens does not list itself: the key that opens it is already in the reader's hand.
        case .Lens:
            evt.updatedFields |= .Name | .Hidden
            evt.name          = appStrings().act_OpenLens
            evt.hidden        = true

        case .Inspector:
            evt.updatedFields |= .Name | .Checked | .Disabled
            evt.name          = appStrings().act_ShowInspector
            evt.checked       = not main.inspector.folded
            evt.disabled      = main.libraryMode

        case .Recent:
            evt.updatedFields |= .Name | .Checked | .Disabled
            evt.name          = appStrings().act_ShowRecent
            evt.checked       = main.showRecent
            evt.disabled      = main.libraryMode
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = mainWndOf(cxt)
        switch cxt.id
        {
        case .Clip:      main.editorOptions.clipToSelection = not main.editorOptions.clipToSelection
        case .Lens:      main.lens.open()
        case .Inspector: main.inspector.toggleFolded()
        case .Recent:    main.showRecentBar(not main.showRecent)
        }

        return true
    }
}

using Gui

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
}

impl IActionUI for ActionToolMode
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd
        let capture = main.getCapture()

        switch cxt.id
        {
        case Shape:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 0)
            evt.name    = "Shape"
            evt.toolTip = "Add circles and rectangle to the capture"
            evt.checked = main.editMode == EditMode.Shape

        case Arrow:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 3)
            evt.name    = "Arrow"
            evt.toolTip = "Add arrows to the capture"
            evt.checked = main.editMode == EditMode.Arrow

        case Line:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 1)
            evt.name    = "Line"
            evt.toolTip = "Add lines to the capture"
            evt.checked = main.editMode == EditMode.Line

        case Poly:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 2)
            evt.name    = "Polygon"
            evt.toolTip = "Add polygons to the capture"
            evt.checked = main.editMode == EditMode.Polygon

        case Text:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 4)
            evt.name    = "Text"
            evt.toolTip = "Add some text to the capture"
            evt.checked = main.editMode == EditMode.Text

        case Draw:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 7)
            evt.name    = "Draw"
            evt.toolTip = "Add some free hand paint to the capture"
            evt.checked = main.editMode == EditMode.Draw

        case Highlight:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 9)
            evt.name    = "Highlight"
            evt.toolTip = "Highlight some parts of the capture"
            evt.checked = main.editMode == EditMode.Highlight

        case Step:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 12)
            evt.name    = "Step"
            evt.toolTip = "Add some steps"
            evt.checked = main.editMode == EditMode.Step

        case Img:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 13)
            evt.name    = "Image"
            evt.toolTip = "Add some images/effects"
            evt.checked = main.editMode == EditMode.Image

        case PixSel:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 17)
            evt.name    = "PixSel"
            evt.toolTip = "Pixel selection"
            evt.checked = main.editMode == EditMode.PixSel

        case Favorites:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 5)
            evt.name    = "Favorites"
            evt.toolTip = "Save multiple quick styles in one single location"
            evt.checked = main.editMode == EditMode.Favorites

        case Selection:
            evt.setFlags |= .Icon | .Checked | .Name | .ToolTip
            evt.icon    = Icon.from(&main.icons48, 10)
            evt.name    = "Select"
            evt.toolTip = "Select forms"
            evt.checked = main.editMode == EditMode.Selection or (capture and capture.drawSelRect)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd
        switch cxt.id
        {
        case Shape:
            main.editMode = EditMode.Shape
        case Arrow:
            main.editMode = EditMode.Arrow
        case Line:
            main.editMode = EditMode.Line
        case Poly:
            main.editMode = EditMode.Polygon
        case Text:
            main.editMode = EditMode.Text
        case Draw:
            main.editMode = EditMode.Draw
        case Highlight:
            main.editMode = EditMode.Highlight
        case Step:
            main.editMode = EditMode.Step
        case Img:
            main.editMode = EditMode.Image
        case PixSel:
            main.editMode = EditMode.PixSel
        case Favorites:
            main.editMode = EditMode.Favorites
        case Selection:
            main.editMode = EditMode.Selection
        }

        main.updateState()
        return true
    }
}

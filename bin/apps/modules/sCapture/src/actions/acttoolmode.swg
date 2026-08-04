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
    newCmdId("Callout")
}

impl IActionUI for ActionToolMode
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) notnull cxt.wnd
        let capture = main.getCapture()

        switch cxt.id
        {
        case .Shape:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 0)
            evt.name          = appStrings().act_Shape
            evt.toolTip       = appStrings().tip_ToolShape
            evt.checked       = main.editMode == EditMode.Shape

        case .Arrow:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 3)
            evt.name          = appStrings().act_Arrow
            evt.toolTip       = appStrings().tip_ToolArrow
            evt.checked       = main.editMode == EditMode.Arrow

        case .Line:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 1)
            evt.name          = appStrings().act_Line
            evt.toolTip       = appStrings().tip_ToolLine
            evt.checked       = main.editMode == EditMode.Line

        case .Poly:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 2)
            evt.name          = appStrings().act_Polygon
            evt.toolTip       = appStrings().tip_ToolPolygon
            evt.checked       = main.editMode == EditMode.Polygon

        case .Text:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 4)
            evt.name          = appStrings().act_Text
            evt.toolTip       = appStrings().tip_ToolText
            evt.checked       = main.editMode == EditMode.Text

        case .Draw:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 7)
            evt.name          = appStrings().act_Draw
            evt.toolTip       = appStrings().tip_ToolDraw
            evt.checked       = main.editMode == EditMode.Draw

        case .Highlight:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 9)
            evt.name          = appStrings().act_Highlight
            evt.toolTip       = appStrings().tip_ToolHighlight
            evt.checked       = main.editMode == EditMode.Highlight

        case .Step:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 12)
            evt.name          = appStrings().act_Step
            evt.toolTip       = appStrings().tip_ToolStep
            evt.checked       = main.editMode == EditMode.Step

        case .Img:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 13)
            evt.name          = appStrings().ui_MenuImage
            evt.toolTip       = appStrings().tip_ToolImage
            evt.checked       = main.editMode == EditMode.Image

        case .PixSel:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 17)
            evt.name          = appStrings().act_PixSel
            evt.toolTip       = appStrings().tip_ToolPixSel
            evt.checked       = main.editMode == EditMode.PixSel

        case .Callout:

            // No sprite for this tool: the toolbar button draws its own bubble glyph
            // via iconPainter, so this state intentionally does not manage the icon.
            evt.updatedFields |= .Checked | .Name | .ToolTip
            evt.name          = appStrings().act_Callout
            evt.toolTip       = appStrings().tip_ToolCallout
            evt.checked       = main.editMode == EditMode.Callout

        case .Favorites:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 5)
            evt.name          = appStrings().act_Favorites
            evt.toolTip       = appStrings().tip_ToolFavorites
            evt.checked       = main.editMode == EditMode.Favorites

        case .Selection:
            evt.updatedFields |= .Icon | .Checked | .Name | .ToolTip
            evt.icon          = Icon.from(&main.icons48, 10)
            evt.name          = appStrings().act_Select
            evt.toolTip       = appStrings().tip_ToolSelect
            evt.checked       = main.editMode == EditMode.Selection or (capture and capture.drawSelRect)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd
        switch cxt.id
        {
        case .Shape:     main.editMode = EditMode.Shape
        case .Arrow:     main.editMode = EditMode.Arrow
        case .Line:      main.editMode = EditMode.Line
        case .Poly:      main.editMode = EditMode.Polygon
        case .Text:      main.editMode = EditMode.Text
        case .Draw:      main.editMode = EditMode.Draw
        case .Highlight: main.editMode = EditMode.Highlight
        case .Step:      main.editMode = EditMode.Step
        case .Img:       main.editMode = EditMode.Image
        case .PixSel:    main.editMode = EditMode.PixSel
        case .Callout:   main.editMode = EditMode.Callout
        case .Favorites: main.editMode = EditMode.Favorites
        case .Selection: main.editMode = EditMode.Selection
        }

        main.updateState()
        return true
    }
}

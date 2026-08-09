using Gui

struct ActionRecentSize {}

impl ActionRecentSize
{
    newCmdId("RecentSmall")
    newCmdId("RecentMedium")
    newCmdId("RecentBig")
    newCmdId("LibSmall")
    newCmdId("LibMedium")
    newCmdId("LibBig")
}

impl IActionUI for ActionRecentSize
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        switch cxt.id
        {
        // The three preview sizes live in the View menu, so each one says its name and
        // reads as one choice among three. Announced without a wording, they were three
        // blank lines carrying a mark and nothing a reader could act on.
        case .RecentSmall:
            evt.updatedFields |= .Name | .ToolTip | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SmallView
            evt.toolTip       = appStrings().tip_SmallRecent
            evt.checked       = main.bottomSize == .Small

        case .RecentMedium:
            evt.updatedFields |= .Name | .ToolTip | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_MediumView
            evt.toolTip       = appStrings().tip_MediumRecent
            evt.checked       = main.bottomSize == .Medium

        case .RecentBig:
            evt.updatedFields |= .Name | .ToolTip | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_BigView
            evt.toolTip       = appStrings().tip_BigRecent
            evt.checked       = main.bottomSize == .Big

        case .LibSmall:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SmallView
            evt.checked       = main.libWnd.previewSize == PreviewSize.Small

        case .LibMedium:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_MediumView
            evt.checked       = main.libWnd.previewSize == PreviewSize.Medium

        case .LibBig:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_BigView
            evt.checked       = main.libWnd.previewSize == PreviewSize.Big
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        switch cxt.id
        {
        case .RecentSmall:  main.setBottomSize(.Small)
        case .RecentMedium: main.setBottomSize(.Medium)
        case .RecentBig:    main.setBottomSize(.Big)
        case .LibSmall:     main.libWnd.setPreviewSize(PreviewSize.Small)
        case .LibMedium:    main.libWnd.setPreviewSize(PreviewSize.Medium)
        case .LibBig:       main.libWnd.setPreviewSize(PreviewSize.Big)
        }

        return true
    }
}

impl MainWnd
{
    mtd setBottomSize(bottomSize: BottomSize, animated = true)
    {
        .bottomSize = bottomSize
        var height: f32
        switch .bottomSize
        {
        case .Small:  height = 80
        case .Medium: height = 128
        case .Big:    height = 224
        }

        if animated do
            discard .app().animator.animateLayoutHeight(.recentBar, height)
        else
        {
            .recentBar.resize(0, height)
            .applyLayout({.position.width, .position.height})
        }
    }
}

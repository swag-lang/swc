#global internal

using Core, Gui, Pixel

namespace ComparisonCommands
{
    const Next         = "scope.compare.next"
    const Previous     = "scope.compare.previous"
    const Swap         = "scope.compare.swap"
    const Whitespace   = "scope.compare.whitespace"
    const Case         = "scope.compare.case"
    const Endings      = "scope.compare.endings"
    const Unified      = "scope.compare.unified"
    const Fit          = "scope.compare.fit"
    const Pixels       = "scope.compare.pixels"
    const ZoomIn       = "scope.compare.zoomIn"
    const ZoomOut      = "scope.compare.zoomOut"
    const PictureModes = ["scope.compare.sideBySide", "scope.compare.curtain", "scope.compare.onionSkin",
                          "scope.compare.difference", "scope.compare.flip"]
    const Modes = [PictureComparisonMode.SideBySide, .Curtain, .OnionSkin, .Difference, .Flip]
    const Zooms = [Fit, Pixels, ZoomIn, ZoomOut]
    const Text  = [Next, Previous, Whitespace, Case, Endings, Unified]
}

impl ViewerWindow
{
    mtd addComparisonCommands()
    {
        let group = func()->string => appStrings().scene_Compare
        .lens.addCommands(group, ComparisonCommands.Text)
        .lens.addCommand(group, ComparisonCommands.Swap)
        .lens.addCommands(group, ComparisonCommands.PictureModes)
        .lens.addCommands(group, ComparisonCommands.Zooms)
        .registerKeyShortcut(.None, .F7, ComparisonCommands.Next)
        .registerKeyShortcut(.Shift, .F7, ComparisonCommands.Previous)
    }

    mtd computeComparisonCommand(evt: *CommandStateEvent)->bool
    {
        let comparison   = .workspace?.comparison
        let visible      = comparison?.isLocallyVisible() orelse false
        let picture      = comparison?.isPicture() orelse false
        let binary       = comparison and (comparison.kind == .Binary or comparison.kind == .Structured)
        let text         = appStrings()
        var name: string = ""
        var hidden       = not visible
        var checked      = false
        var checkable    = false
        switch evt.id
        {
        case ComparisonCommands.Next:
            name   = text.scene_NextDifference
            hidden = hidden or picture

        case ComparisonCommands.Previous:
            name   = text.scene_PreviousDifference
            hidden = hidden or picture

        case ComparisonCommands.Whitespace:
            name      = text.scene_IgnoreWhitespace
            checkable = true
            checked   = comparison?.options.ignoreWhitespace orelse false
            hidden    = hidden or picture or binary

        case ComparisonCommands.Case:
            name      = text.scene_IgnoreCase
            checkable = true
            checked   = comparison?.options.ignoreCase orelse false
            hidden    = hidden or picture or binary

        case ComparisonCommands.Endings:
            name      = text.scene_IgnoreEndings
            checkable = true
            checked   = comparison?.options.ignoreEndings orelse false
            hidden    = hidden or picture or binary

        case ComparisonCommands.Unified:
            name      = text.scene_Unified
            checkable = true
            checked   = comparison?.options.unified orelse false
            hidden    = hidden or picture

        case ComparisonCommands.Swap:
            name = text.scene_Swap

        case ComparisonCommands.Fit:
            name      = text.scene_Fit
            checkable = true
            checked   = comparison and not comparison.pixelAligned
            hidden    = hidden or not picture

        case ComparisonCommands.Pixels:
            name      = text.scene_Pixels
            checkable = true
            checked   = comparison?.pixelAligned orelse false
            hidden    = hidden or not picture

        case ComparisonCommands.ZoomIn:
            name   = text.scene_ZoomIn
            hidden = hidden or not picture

        case ComparisonCommands.ZoomOut:
            name   = text.scene_ZoomOut
            hidden = hidden or not picture

        default:
            for id, index in ComparisonCommands.PictureModes where id == evt.id
            {
                let mode = ComparisonCommands.Modes[index]
                name      = pictureModeTitle(mode)
                checkable = true
                checked   = comparison and comparison.mode == mode
                hidden    = hidden or not picture
                break
            }
        }

        if not name.count do
            return false
        evt.name          = name
        evt.hidden        = hidden
        evt.updatedFields |= .Name | .Hidden
        if checkable
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        evt.accepted = true
        return true
    }

    mtd runComparisonCommand(id: WndId)->bool
    {
        let workspace  = .workspace
        let comparison = workspace?.comparison
        if not workspace or not comparison or not comparison.isLocallyVisible() do
            return false
        let scene  = unwrap workspace.scene()
        var reread = false
        switch id
        {
        case ComparisonCommands.Next:
            comparison.step(1)

        case ComparisonCommands.Previous:
            comparison.step(-1)

        case ComparisonCommands.Whitespace:
            comparison.options.ignoreWhitespace = not comparison.options.ignoreWhitespace
            reread = true

        case ComparisonCommands.Case:
            comparison.options.ignoreCase = not comparison.options.ignoreCase
            reread = true

        case ComparisonCommands.Endings:
            comparison.options.ignoreEndings = not comparison.options.ignoreEndings
            reread = true

        case ComparisonCommands.Unified:
            comparison.options.unified = not comparison.options.unified

        case ComparisonCommands.Swap:
            scene.swapViews(0, 1)
            scene.active = 1 - scene.active
            workspace.showScene()

        case ComparisonCommands.Fit, ComparisonCommands.Pixels:
            comparison.pixelAligned = id == ComparisonCommands.Pixels
            comparison.pan          = {}
            comparison.zoom         = 1

        case ComparisonCommands.ZoomIn, ComparisonCommands.ZoomOut:
            comparison.zoom = Math.clamp(comparison.zoom * (id == ComparisonCommands.ZoomIn ? 1.25 : 0.8), 0.1, 20)

        default:
            for item, index in ComparisonCommands.PictureModes where item == id
            {
                comparison.setPictureMode(ComparisonCommands.Modes[index])
                return true
            }

            return false
        }

        if reread do
            comparison.requestDiff()
        comparison.refresh()
        return true
    }
}

impl ViewerWorkspace
{
    mtd routeComparisonKey(evt: *KeyEvent, source: *Wnd)->bool
    {
        let comparison = .comparison
        if not comparison or
           not comparison.isLocallyVisible() or
           source is EditBox or
           .activeDocument().lens.isOpen() do
            return false
        if evt.key == .F7 and (evt.modifiers == .None or evt.modifiers == .Shift)
        {
            comparison.step(evt.modifiers == .Shift ? -1 : 1)
            return true
        }

        if not comparison.isPicture() or evt.modifiers != .None do
            return false
        switch evt.key
        {
        case .D1:
            comparison.setPictureMode(.Curtain)

        case .D2:
            comparison.setPictureMode(.OnionSkin)

        case .D3:
            comparison.setPictureMode(.Difference)

        case .D4:
            comparison.setPictureMode(.Flip)

        case .Space where comparison.mode == .Flip and comparison.kind == .Picture:
            comparison.shownRight = not comparison.shownRight
            comparison.showFlippedName()

        default:
            return false
        }

        return true
    }
}

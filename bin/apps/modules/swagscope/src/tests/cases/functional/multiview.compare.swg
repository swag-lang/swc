#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

func finishComparison(host: *Testing.HeadlessHost, comparison: *SceneComparison)
{
    for 8 where comparison.operation.started
    {
        comparison.operation.task.wait()
        host.pump()
    }

    Swag.require(not comparison.operation.started)
    Swag.require(comparison.error.isEmpty(), comparison.error)
}

#test
{
    let first  = Testing.tempFilePath("scope-diff-left-", ".txt")
    let second = Testing.tempFilePath("scope-diff-right-", ".txt")
    defer catch File.delete(first)
    defer catch File.delete(second)
    discard expect File.writeAllText(first, " ALPHA \r\nkeep\r\nold\r\n")
    discard expect File.writeAllText(second, "alpha\nkeep\nnew\n")

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([first, second], .SideBySide)
    openViews(&host, workspace)
    host.keyPress(.D, .Control)
    let comparison = unwrap workspace.comparison
    finishComparison(&host, comparison)
    for command in [ComparisonCommands.Whitespace, ComparisonCommands.Case, ComparisonCommands.Endings]
    {
        Swag.require(workspace.activeDocument().runCommand(command))
        finishComparison(&host, comparison)
    }

    Swag.require(comparison.text.changes.count == 1 and comparison.text.changes[0] == 2)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.Unified))
    Swag.require(comparison.options.unified)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.Swap))
    finishComparison(&host, comparison)
    Swag.require(comparison.paths[0] == second and comparison.paths[1] == first)
    host.keyPress(.D, .Control)
    Swag.require(not workspace.comparisonVisible() and workspace.scene()!.layout == .SideBySide)

    Swag.require(workspace.activeDocument().runCommand(SceneCommands.Compare))
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.Case))
    comparison.operation.task.wait()
    workspace.openDocument(scopeTestDataPath("viewer.srt"))
    workspace.selectScene(0)
    openViews(&host, workspace)
    finishComparison(&host, comparison)
    Swag.require(workspace.comparisonVisible() and comparison.text.changes.count == 2)
    let survivor = comparison.paths[0]
    host.clickWnd(comparison.captions[1].close)
    Swag.require(workspace.documentCount() == 1 and workspace.activeDocument().currentFile == survivor)
    Swag.require(not workspace.comparisonVisible())
}

#test
{
    let first  = Testing.tempFilePath("scope-diff-hex-left-", ".bin")
    let second = Testing.tempFilePath("scope-diff-hex-right-", ".bin")
    defer catch File.delete(first)
    defer catch File.delete(second)
    var left, right: [112] u8
    right[17] = 0xFF
    right[81] = 0xAA
    expect File.writeAllBytes(first, left)
    expect File.writeAllBytes(second, right)

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([first, second], .SideBySide)
    openViews(&host, workspace)
    for view in workspace.scene()!.views
    {
        let document = unwrap view.document
        for choice, index in document.choices where choice.key == "hex" do
            document.selectViewer(cast(u32, index))
    }

    openViews(&host, workspace)
    host.keyPress(.D, .Control)
    let comparison = unwrap workspace.comparison
    finishComparison(&host, comparison)
    Swag.require(comparison.kind == .Binary and comparison.text.changes.count == 2)
    comparison.jump(0)
    host.keyPress(.F7)
    Swag.require(comparison.selectedChange == 1)
    host.keyPress(.F7, .Shift)
    Swag.require(comparison.selectedChange == 0)

    let area      = comparison.clientRect()
    let top       = comparison.stripInset() + ViewerWorkspace.ViewTitleHeight
    let height    = area.height - SceneComparison.FooterHeight - top
    let ratio     = cast(f32, comparison.text.changes[1]) / cast(f32, comparison.text.rows.count)
    var bandPoint = comparison.localToSurface(Math.Point{area.horzCenter(), top + ratio * height})
    host.surface.surfaceToScreen(&bandPoint)
    host.paint(&host.surfaceWnd)
    host.click(bandPoint)
    Swag.require(comparison.selectedChange == 1 and comparison.firstRow <= comparison.text.changes[1])
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("sample.svg"), scopeTestDataPath("viewer.png")], .SideBySide, compare: true)
    openViews(&host, workspace)
    let comparison = unwrap workspace.comparison
    host.paint(&host.surfaceWnd)
    let area  = comparison.clientRect()
    var point = comparison.localToSurface(Math.Point{area.width * 0.27, area.vertCenter()})
    host.surface.surfaceToScreen(&point)

    host.keyPress(.D1)
    Swag.require(comparison.mode == .Curtain)
    host.click(point)
    Swag.require(Math.abs(comparison.separator - 0.27) < 0.01)
    host.drag(point, point + Math.Point{area.width * 0.35, 0})
    Swag.require(Math.abs(comparison.separator - 0.62) < 0.01)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.Pixels) and comparison.pixelAligned)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.Fit) and not comparison.pixelAligned)

    host.keyPress(.D2)
    Swag.require(comparison.mode == .OnionSkin)
    let opacity = comparison.opacity
    host.mouseWheel(point, 120, .Alt)
    Swag.require(Math.abs(comparison.opacity - opacity - 0.05) < 0.001)

    host.keyPress(.D3)
    host.paint(&host.surfaceWnd)
    Swag.require(comparison.mode == .Difference and comparison.diffTexture.isValid())
    host.keyPress(.D4)
    Swag.require(comparison.mode == .Flip)
    let shownRight = comparison.shownRight
    host.keyPress(.Space)
    Swag.require(comparison.shownRight != shownRight)
    let visible = comparison.shownRight ? 1'u64 : 0'u64
    let scene = unwrap workspace.scene()
    Swag.require(scene.active == visible and comparison.captions[visible].close.isVisible())
    Swag.require(not comparison.captions[1 - visible].close.isVisible())
    Swag.require(workspace.dropRect(scene, visible).width == workspace.clientRect().width)
    Swag.require(workspace.dropRect(scene, 1 - visible).isEmpty())
    Swag.require(comparison.captions[visible].title.isVisible())

    host.keyPress(.I)
    let sheet = unwrap workspace.comparisonSheet
    Swag.require(sheet.panel.isLocallyVisible() and sheet.different > 0)

    workspace.openScene([scopeTestDataPath("viewer.arabic.ttf"), scopeTestDataPath("font-fixture-cjk.otf")], .SideBySide, compare: true)
    openViews(&host, workspace)
    host.keyPress(.I)
    Swag.require(sheet.panel.isLocallyVisible() and sheet.different > 0)
    var typeface: bool
    for &fact, index in sheet.facts
    {
        Swag.require((fact.left != fact.right) == (index < sheet.different))
        if fact.label == mediaInfoStrings().typeface
        {
            Swag.require(not fact.left.isEmpty() and not fact.right.isEmpty() and fact.left != fact.right)
            typeface = true
        }
    }

    Swag.require(typeface)
}

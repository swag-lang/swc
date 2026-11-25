#global if #command == Swag.CompilerCommand.Test
#global private

using Audio, Core, Gui

// Close a solo video tab while it is opening, then close another once it has shown a frame.
#[Swag.TestTag("integration.application.journey")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var journey: ScopeJourney
    journey.setup(withWorkspace: true)
    let workspace = unwrap journey.window.workspace
    let first = journey.copyData("comprehensive.txt", "first.txt")
    let other = journey.copyData("sample.cpp", "other.cpp")
    let film  = journey.copyData("viewer.avi", "film.avi")

    workspace.openScene([first, other], .Grid2, manual: true)
    let grid = unwrap workspace.scene()
    journey.waitForFile(first, unwrap grid.views[0].document)
    journey.waitForFile(other, unwrap grid.views[1].document)
    for loaded in [false, true]
    {
        let selected = loaded ? 1'u64 : 0'u64
        workspace.selectView(selected)
        if not loaded do
            workspace.releaseCellFocus()
        let command = loaded ? TabCommands.OpenFile : ViewerCommands.Open
        journey.chooseFile(workspace.activeDocument(), film, command)
        Swag.require(workspace.scenes.count == 2 and workspace.scene()!.layout == .Single)
        let solo = workspace.activeDocument()
        if loaded do
            journey.waitForFile(film, solo)
        else do
            Swag.require(solo.pendingFile == film)

        solo.sendCommandEvent(TabCommands.Close)
        Swag.require(workspace.scene() == grid and workspace.scenes.count == 1)
        Swag.require(grid.layout == .Grid2 and grid.active == selected and grid.views.count == 2)
        journey.waitForFile(first, unwrap grid.views[0].document)
        journey.waitForFile(other, unwrap grid.views[1].document)
        journey.waitFor("old viewers retired", func|workspace|()->bool => workspace.retiring.isEmpty())
        Swag.require(grid.views[0].document!.isVisible() and grid.views[1].document!.isVisible())
        Swag.require(workspace.activeDocument() == grid.views[selected].document)
    }
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Audio, Core, Gui

// Switch tabs before the video replaces Explorer, then resume the file in its original pane.
#[Swag.TestTag("integration.application.journey")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var journey: ScopeJourney
    journey.setup(withWorkspace: true)
    let workspace = unwrap journey.window.workspace
    let folder = Path.combine(journey.root, "Library")
    expect Directory.create(folder)
    let other = journey.copyData("sample.cpp", "other.cpp")
    let image = journey.copyData("viewer.png", "image.png")
    let film  = journey.copyData("viewer.avi", "film.avi")

    workspace.openScene([folder, other], .Grid4, manual: true)
    let grid = unwrap workspace.scene()
    let explorer = workspace.activeDocument()
    let folderReady = func|explorer, folder = &folder|()->bool
    {
        return explorer.isExploring() and not explorer.explorer!.load.started and
               Path.equals(explorer.explorer!.listing.path, folder[])
    }
    journey.waitFor("Explorer opened in the grid", folderReady)
    journey.waitForFile(other, unwrap grid.views[1].document)

    journey.chooseFile(explorer, image)
    journey.waitForFile(image, explorer)
    explorer.sendCommandEvent(ViewerCommands.ReturnToExplorer)
    journey.waitFor("Explorer restored in the same pane", folderReady)
    Swag.require(Path.equals(grid.views[0].path, folder))

    journey.chooseFile(explorer, film)
    Swag.require(explorer.explorerTransition and explorer.pendingFile == film)
    workspace.newTab()
    Swag.require(workspace.scenes.count == 2 and grid.views[0].explorerState.path.isEmpty())
    workspace.activeDocument().sendCommandEvent(TabCommands.Close)
    Swag.require(workspace.scene() == grid and grid.layout == .Grid4 and grid.active == 0)
    let restored = workspace.activeDocument()
    journey.waitForFile(film, restored)
    journey.waitForFile(other, unwrap grid.views[1].document)
    Swag.require(restored.currentView is Viewers.Film.Panel and grid.views.count == 2)
    Swag.require(grid.cellOf(0) == 0 and grid.cellOf(1) == 1 and grid.viewInCell(15) == Swag.U64.Max)
}

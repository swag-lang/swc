#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// A desktop click in the linked Explorer replaces the file in the content pane.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: ScopeJourney
    journey.setup(withWorkspace: true)
    let window    = journey.window
    let workspace = unwrap window.workspace
    let folder    = Path.combine(journey.root, "Files")
    let selected  = Path.combine(folder, "Selected.txt")
    expect Directory.create(folder)
    discard expect File.writeAllText(selected, "Linked content")
    let previous = journey.copyData("comprehensive.txt", "Previous.txt")

    window.openExplorer(folder)
    let explorer = unwrap window.explorer
    journey.waitFor("Explorer listing", func|explorer|()->bool => not explorer.load.started and explorer.shown.count == 1)
    explorer.setMode(.Details)
    workspace.setLayout(.SideBySide)
    workspace.openBeside(previous)
    let scene   = unwrap workspace.scene()
    let content = unwrap scene.views[1].document
    journey.waitForFile(previous, content)
    workspace.setSceneLink(MediaCommands.Explorer, true)
    workspace.setSceneLink(MediaCommands.ExplorerSingleClick, true)

    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    let list  = explorer.list.listView
    var point = list.localToSurface(explorer.list.cellTextRect(0, 0).center())
    input.moveTo(list, point)
    journey.surface.surfaceToScreen(&point)
    input.clickDesktopPoint(point)

    journey.waitForFile(selected, content)
    Swag.require(workspace.scenes.count == 1 and workspace.scene() == scene and scene.views[1].document == content)
    Swag.require(workspace.activeDocument() == window and window.isExploring())
}

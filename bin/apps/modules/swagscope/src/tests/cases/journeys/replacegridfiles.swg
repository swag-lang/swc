#global if #command == Swag.CompilerCommand.Test
#global private

using Audio, Core, Gui

// Replace each occupied pane in the file dialog, including a video, then fill a distant hole.
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
    let image = journey.copyData("viewer.png", "image.png")

    workspace.openScene([first, other], .SideBySide)
    let scene = unwrap workspace.scene()
    let left  = unwrap scene.views[0].document
    let right = unwrap scene.views[1].document
    journey.waitForFile(first, left)
    journey.waitForFile(other, right)

    journey.chooseFile(left, film, cancel: true)
    Swag.require(scene.views[0].path == first and workspace.activeDocument() == left)
    journey.chooseFile(left, film)
    Swag.require(workspace.scene() == scene and workspace.scenes.count == 1 and scene.views.count == 2)
    journey.waitForFile(film, left)
    Swag.require(left.currentView is Viewers.Film.Panel and scene.views[1].document == right and right.currentFile == other)

    workspace.setLayout(.Stacked)
    workspace.selectView(1)
    journey.chooseFile(right, image)
    Swag.require(workspace.scene() == scene and scene.layout == .Stacked and scene.views.count == 2)
    journey.waitForFile(image, right)
    Swag.require(scene.views[0].document == left and left.currentFile == film)

    workspace.setLayout(.Grid3)
    workspace.focusVacancy(8)
    let corner = workspace.activeDocument()
    journey.chooseFile(corner, film)
    Swag.require(workspace.scene() == scene and scene.views.count == 3 and scene.cellOf(scene.active) == 8)
    journey.waitForFile(film, corner)
    journey.chooseFile(corner, first)
    Swag.require(workspace.scene() == scene and scene.views.count == 3 and scene.cellOf(scene.active) == 8)
    journey.waitForFile(first, corner)
    Swag.require(scene.viewInCell(7) == Swag.U64.Max and left.currentFile == film and right.currentFile == image)
}

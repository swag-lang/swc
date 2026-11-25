#global if #command == Swag.CompilerCommand.Test
#global private

using Audio, Gui

// Click the occupied left pane and use the native Ctrl+O shortcut to replace it with a video.
#[Swag.TestTag("integration.desktop.input")]
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

    workspace.openScene([first, other], .SideBySide)
    let scene = unwrap workspace.scene()
    let left  = unwrap scene.views[0].document
    let right = unwrap scene.views[1].document
    journey.waitForFile(first, left)
    journey.waitForFile(other, right)
    workspace.selectView(1)

    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    input.click(left.cellCaption.title)
    Swag.require(workspace.activeDocument() == left)
    journey.chooseFile(left, film, input: &input)
    Swag.require(workspace.scenes.count == 1 and workspace.scene() == scene and scene.layout == .SideBySide)
    journey.waitForFile(film, left)
    Swag.require(left.currentView is Viewers.Film.Panel and scene.views[1].document == right)
    Swag.require(right.currentFile == other and right.isVisible())
}

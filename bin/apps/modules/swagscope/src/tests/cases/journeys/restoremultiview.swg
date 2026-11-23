#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

func nativeWorkspace(app: *Application, state: string)->*ViewerWorkspace
{
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(state)
    registerAppStrings(&app.resources)
    let surface   = expect app.createSurface(40, 40, 1100, 720, surfaceId: "scope-restore-multiview")
    let workspace = ViewerWorkspace.create(surface.wnd, createViewerPluginRegistry())
    workspace.primary.onlineMovies = false
    workspace.primary.onlineMusic  = false
    return workspace
}

func waitForWorkspace(app: *Application, workspace: *ViewerWorkspace)
{
    let surface = unwrap workspace.surface
    var watch: Time.Stopwatch
    watch.start()
    while true
    {
        app.runFrame()
        var ready = workspace.documentCount() > 0
        for view in workspace.scene()!.views where ready
        {
            let document = view.document
            ready = document and document.currentFile == view.path and document.currentView != null
        }

        if ready and expect Testing.verifyNativePresentation(surface) do
            return
        Swag.require(surface.renderFailure.isEmpty() and watch.elapsedMilliseconds() < 15_000)
    }
}

#[Swag.TestTag("integration.application.journey")]
#test
{
    let state = Testing.tempFilePath("scope-multiview-session-", ".scc")
    defer catch File.delete(state)
    let first  = scopeTestDataPath("sample.cpp")
    let second = scopeTestDataPath("comprehensive.txt")
    let third  = scopeTestDataPath("viewer.srt")
    scope
    {
        var app: Application
        let workspace = nativeWorkspace(&app, state)
        workspace.surface!.show()
        workspace.openScene([first, second], .Stacked)
        waitForWorkspace(&app, workspace)
        workspace.setSceneLink(MediaCommands.Scroll, true)
        workspace.setSceneLink(MediaCommands.Linked, true)
        workspace.setEndMode(.Shortest)
        workspace.scene()!.views[1].document!.setPlayMode(.Folder)
        workspace.toggleMaximized()
        expect app.saveState()
        workspace.surface.destroy()
    }

    var app: Application
    let workspace = nativeWorkspace(&app, state)
    workspace.startupFiles.add(third)
    workspace.startupFiles.add(first)
    workspace.startupLayout = sceneGrid(workspace.startupFiles.count)
    workspace.surface!.show()
    defer workspace.surface!.destroy()
    waitForWorkspace(&app, workspace)
    Swag.require(workspace.scenes.count == 2 and workspace.active == 1)
    Swag.require(workspace.scene()!.layout == .Grid2)
    Swag.require(Path.equals(workspace.activeDocument().currentFile, expect Path.absolute(third)))
    workspace.selectScene(0)
    waitForWorkspace(&app, workspace)
    let restored = unwrap workspace.scene()
    Swag.require(restored.layout == .Stacked and restored.linked and restored.links.scroll and restored.maximized)
    Swag.require(restored.links.end == .Shortest)
    Swag.require(Path.equals(restored.views[0].path, expect Path.absolute(first)))
    Swag.require(Path.equals(restored.views[1].path, expect Path.absolute(second)))
    Swag.require(restored.views[1].document!.playMode == .Folder)

    workspace.selectView(1)
    let remaining = workspace.activeDocument()
    workspace.toggleMaximized()
    waitForWorkspace(&app, workspace)
    Swag.require(restored.visibleLayout() == .Stacked and restored.views[0].document!.isVisible())
    Swag.require(remaining.runCommand(SceneCommands.Layouts[0]))
    waitForWorkspace(&app, workspace)
    Swag.require(restored.visibleLayout() == .Single and not restored.views[0].document!.isVisible())
    Swag.require(remaining.runCommand(SceneCommands.Maximize))
    waitForWorkspace(&app, workspace)
    Swag.require(restored.visibleLayout() == .Stacked)
    Swag.require(remaining.runCommand(ViewerCommands.FullScreen) and workspace.primary.fullScreen)
    workspace.selectView(0)
    Swag.require(workspace.activeDocument().fullScreen)
    Swag.require(workspace.activeDocument().runCommand(ViewerCommands.FullScreen) and not remaining.fullScreen)
    workspace.closeView(0)
    Swag.require(workspace.activeDocument() == remaining and restored.layout == .Single)
    Swag.require(remaining.position == workspace.clientRect() and workspace.tabs.isLocallyVisible())
}

#global if #command == Swag.CompilerCommand.Test
#global internal

using Gui, Pixel

func testWorkspace(host: *Testing.HeadlessHost, light = false, width = 1080, height = 640)->*ViewerWorkspace
{
    host.setup(width, height)
    shipFrame(host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    let workspace = ViewerWorkspace.create(&host.surfaceWnd, createViewerPluginRegistry())
    workspace.primary.applyTheme(cast(u32, light ? AppearanceTheme.Light : AppearanceTheme.Dark))
    return workspace
}

func openViews(host: *Testing.HeadlessHost, workspace: *ViewerWorkspace)
{
    let scene = unwrap workspace.scene()
    for &view in scene.views do
        completeQueuedViewerFile(host, unwrap view.document)
}

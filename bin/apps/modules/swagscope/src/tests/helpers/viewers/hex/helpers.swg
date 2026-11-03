#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Viewers

// Builds the hexadecimal viewer test surface after its background load completes.
func hexTestViewer(host: *Testing.HeadlessHost, fileName: string, width, height: f32)->*Hex.Panel
{
    Hex.registerTexts(&host.app)
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 640, 36})
    var session  = openTestViewer(Hex.viewerPlugin(), &host.root, fileName, commandParent: commands, infoParent: commands)
    let view     = assume cast(*Hex.Panel, session.view)
    completeViewerBackgroundLoad(host, &view.load)
    assertViewerInfoButton(unwrap view.zoomLabel)
    view.dockStyle = .Center
    view.resize(width, height)
    view.applyLayout()
    view.grid.refreshLayout()
    return view
}

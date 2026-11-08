#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Viewers

// Writes a file whose byte at each offset is that offset truncated to eight bits.
func writeStreamedFile(size: u64)->String
{
    let fileName = Testing.tempFilePath("viewer-hex-stream-", ".bin")
    var payload: Array'u8
    payload.resize(size)
    for index in size do
        payload[index] = cast(u8, index & 0xFF)
    expect File.writeAllBytes(fileName, payload.toSlice())
    return fileName
}

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

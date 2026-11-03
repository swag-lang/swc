#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Viewers

// Completes the binary document load and its delayed activity indicator.
func finishBinaryViewer(host: *Testing.HeadlessHost, view: *Binary.Panel)
{
    view.loadTask.wait()
    host.pump()

    var attempts: u32
    while view.loadTimer and attempts < 10_000
    {
        host.fireTimer(view.loadTimer)
        attempts += 1
    }

    Swag.require(not view.isLoading())
}

// Builds the binary viewer test surface after its background load completes.
func binaryTestViewer(host: *Testing.HeadlessHost, fileName: string, width, height: f32)->*Binary.Panel
{
    var session = openTestViewer(Binary.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*Binary.Panel, session.view)
    finishBinaryViewer(host, view)
    view.dockStyle = .Center
    view.resize(width, height)
    view.applyLayout()
    view.layoutColumns()
    return view
}

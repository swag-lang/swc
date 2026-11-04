#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

struct XdndCatcher
{
    using wnd: Wnd
    drops:     u32
    text:      String
    files:     Array'String
}

impl IWnd for XdndCatcher
{
    mtd impl onDragDropEvent(event: *DragDropEvent)
    {
        event.effect = pickDropEffect(event.allowed, event.modifiers)
        if event.kind == .Drop
        {
            .drops += 1
            .text  = event.data.text
            .files = event.data.files
        }
    }
}

func xdndPeerPath()->String => Path.combine(testSourceRoot(), "datas/dragdrop.x11.peer.py")

func stopXdndPeer(peer: *Env.Process)
{
    discard catch peer.kill()
    discard catch peer.waitForExit()
}

#[Swag.TestTag("integration.dragdrop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1", "XDND integration requires an isolated X11 server")
    var app: Application
    let surface = expect app.createSurface(40, 40, 220, 180, surfaceId: "xdnd-target")
    let catcher = Wnd.create'XdndCatcher(surface.wnd)
    surface.setView(catcher)
    surface.show()
    let script = xdndPeerPath()
    let id     = Format.toString("%", surface.windowId)
    var peer   = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [script.toString(), "source", id.toString()],
                                                       standardOutput: .Pipe, standardError: .Pipe})
    defer stopXdndPeer(&peer)
    let deadline = Time.monotonicMilliseconds() + 10000
    while peer.isRunning() and Time.monotonicMilliseconds() < deadline
    {
        app.runFrame()
        discard expect peer.tryWaitForExit(Time.Duration.fromMilliseconds(5))
    }

    Swag.require(not peer.isRunning() and peer.exitCode() == 0, peer.standardError())
    Swag.require(peer.standardOutput() == "ok\n")
    Swag.require(catcher.drops == 1 and catcher.text == "external-é")
    Swag.require(catcher.files.count == 1 and catcher.files[0] == "/tmp/space and é.txt")
}

#[Swag.TestTag("integration.dragdrop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1", "XDND integration requires an isolated X11 server")
    var app: Application
    let surface = expect app.createSurface(40, 40, 220, 180, surfaceId: "xdnd-source")
    surface.show()
    let script    = xdndPeerPath()
    var thumbnail = Pixel.Image.create(2, 2, .BGRA8)
    thumbnail.clear()
    var preview = LinuxDrag.Preview.create(&thumbnail)
    Swag.require(preview.cursor != 0)
    preview.clear()
    for mode in ["target", "reject", "save"]
    {
        let destination = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("xdnd-%{X016}.txt", Guid64.random()).toString())
        defer discard catch File.delete(destination.toString())
        var peer = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [script.toString(), mode, destination.toString()],
                                                         standardOutput: .Pipe, standardError: .Pipe})
        defer stopXdndPeer(&peer)
        let deadline = Time.monotonicMilliseconds() + 3000
        for
        {
            peer.readAvailable()
            if peer.standardOutput() == "ready\n" do
                break
            Swag.require(peer.isRunning() and Time.monotonicMilliseconds() < deadline, peer.standardError())
            discard expect peer.tryWaitForExit(5'ms)
        }

        var data: DragData
        data.setText("source-é")
        var produced: u32
        let producer = func|&produced|()->Array'u8
        {
            produced += 1
            var result: Array'u8
            result.add(cast(const [..]u8, "deferred-content"))
            return result
        }

        data.addContent("virtual.txt", producer)
        Swag.require(produced == 0)
        let effect = surface.wnd.view.startDrag(&data, .Copy, &thumbnail)
        Swag.require(effect == (mode == "reject" ? DropEffect.None : DropEffect.Copy))
        Swag.require(produced == (mode == "reject" ? 0'u32 : 1'u32))
        let exited = expect peer.tryWaitForExit(3000'ms)
        Swag.require(exited)
        Swag.require(peer.exitCode() == 0, peer.standardError())
        Swag.require(peer.standardOutput() == "ready\nok\n")
        if mode == "save" do
            Swag.require(expect File.readAllText(destination.toString()) == "deferred-content")
    }
}

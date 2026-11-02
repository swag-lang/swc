#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core, Pixel

func selectionPeerPath()->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/clipboard.x11.peer.py")

func startSelectionPeer(mode: string)->Env.Process
{
    let path = selectionPeerPath()
    var peer = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [path.toString(), mode],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    let deadline = Time.monotonicMilliseconds() + 3000
    for
    {
        peer.readAvailable()
        if peer.standardOutput() == "ready\n" do
            return #move peer
        if not peer.isRunning() or Time.monotonicMilliseconds() >= deadline
        {
            discard catch peer.kill()
            discard catch peer.waitForExit()
            Swag.assert(false, "independent X11 peer did not become ready")
        }

        Threading.Thread.sleep(Time.Duration.fromMilliseconds(5))
    }
}

func stopSelectionPeer(peer: *Env.Process)
{
    discard catch peer.kill()
    discard catch peer.waitForExit()
}

func readSelectionPeer(mode: string)
{
    let path = selectionPeerPath()
    var peer = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [path.toString(), mode],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    defer stopSelectionPeer(&peer)
    Swag.assert(expect peer.tryWaitForExit(Time.Duration.fromMilliseconds(8000)))
    Swag.assert(peer.exitCode() == 0, peer.standardError())
    Swag.assert(peer.standardOutput() == "ok\n")
}

// This opt-in test writes to the desktop selection. The runner must create an isolated
// Xvfb and set this marker; the ordinary sandbox clipboard suite remains process-local.
#[Swag.TestTag("integration.clipboard")]
#test
{
    Swag.assert(Env.variable("SWAG_TEST_ISOLATED_X11") == "1", "clipboard integration requires an isolated X11 server")
    let wasFake = Clipboard.g_Fake.enabled
    Clipboard.g_Fake.enabled = false
    defer Clipboard.g_Fake.enabled = wasFake
    defer Clipboard.clear()
    Swag.assert(not Clipboard.isFake())

    Clipboard.setString("native-é")
    Swag.assert(Clipboard.getString() == "native-é")
    readSelectionPeer("read-text")

    var large: String
    for 262144 do
        large += 'x'
    Clipboard.setString(large.toString())
    readSelectionPeer("read-large")

    var image = Image.create(3, 2, .BGRA8)
    image.clear()
    Clipboard.addImage(image)
    Swag.assert(Clipboard.hasImage() and not Clipboard.hasString())
    readSelectionPeer("read-png")
    let copied = Clipboard.getImage()
    Swag.assert(copied.isValid() and copied.width == 3 and copied.height == 2)

    let format = expect Clipboard.registerFormat("Swag.Selection.Peer")
    scope
    {
        var peer = startSelectionPeer("offer")
        defer stopSelectionPeer(&peer)
        Swag.assert(Clipboard.getString() == "étranger")
        let externalImage = Clipboard.getImage()
        Swag.assert(externalImage.isValid() and externalImage.width == 2 and externalImage.height == 1)
        let color = externalImage.pixelColor(0, 0)
        Swag.assert(color.r == 0x10 and color.g == 0x20 and color.b == 0x30 and color.a == 0xFF)
        let bytes = Clipboard.getTypedData(format, null)
        Swag.assert(cast(string, bytes.toSlice()) == "payload")

        // Claiming one format retains another owner's unrelated format.
        Clipboard.addString("native-é")
        Swag.assert(expect peer.tryWaitForExit(Time.Duration.fromMilliseconds(3000)))
        Swag.assert(peer.exitCode() == 0)
        Swag.assert(Clipboard.getString() == "native-é")
        let retained = Clipboard.getTypedData(format, null)
        Swag.assert(cast(string, retained.toSlice()) == "payload")
        Swag.assert(Clipboard.hasImage())
    }

    scope
    {
        var peer = startSelectionPeer("offer-large")
        defer stopSelectionPeer(&peer)
        let copied = Clipboard.getString()
        Swag.assert(copied.count == 262144)
        for byte in copied.toString() do
            Swag.assert(byte == 'q')
        Clipboard.clear()
        Swag.assert(expect peer.tryWaitForExit(Time.Duration.fromMilliseconds(3000)))
        Swag.assert(peer.exitCode() == 0)
    }

    scope
    {
        var peer = startSelectionPeer("offer-silent")
        defer stopSelectionPeer(&peer)
        let started = Time.monotonicMilliseconds()
        Swag.assert(Clipboard.getString().isEmpty())
        let elapsed = Time.monotonicMilliseconds() - started
        Swag.assert(elapsed >= 3000 and elapsed < 7500)
        Clipboard.clear()
        Swag.assert(expect peer.tryWaitForExit(Time.Duration.fromMilliseconds(3000)))
    }

    for mode in ["offer-oversize", "offer-invalid-utf8"]
    {
        var peer = startSelectionPeer(mode)
        defer stopSelectionPeer(&peer)
        let started = Time.monotonicMilliseconds()
        Swag.assert(Clipboard.getString().isEmpty())
        Swag.assert(Time.monotonicMilliseconds() - started < 2000)
        Clipboard.clear()
        Swag.assert(expect peer.tryWaitForExit(Time.Duration.fromMilliseconds(3000)))
    }

    Clipboard.setString("native-é")
    readSelectionPeer("read-text")
    Clipboard.clear()
    Swag.assert(not Clipboard.hasString() and not Clipboard.hasImage() and not Clipboard.hasFormat(format))
}

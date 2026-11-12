#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel, Win32

// Open the resident hub, click a window owned by another process, and leave the hub behind.
#[Swag.TestTag("integration.capture.hub.focus")]
#test
{
    var journey: CaptureJourney
    journey.setup()

    // A dedicated child owns the small window; the test never takes over a user's application.
    const title = "Swag Capture Cross Process Focus Fixture"
    let script = "Add-Type -AssemblyName System.Windows.Forms; $f=New-Object Windows.Forms.Form; $f.Text='Swag Capture Cross Process Focus Fixture'; $f.StartPosition='Manual'; $f.SetBounds(20,20,110,85); $f.TopMost=$true; $f.ShowInTaskbar=$false; [Windows.Forms.Application]::Run($f)"
    var peer = expect Env.startProcess("powershell.exe",
                                       ["-NoProfile", "-Sta", "-WindowStyle", "Hidden", "-Command", script])
    defer { discard catch peer.kill(); discard catch peer.waitForExit(); }

    var watch: Time.Stopwatch
    watch.start()
    var peerWindow: Win32.HWND
    while peerWindow == null and watch.elapsedMilliseconds() < 5000
    {
        journey.app.runFrame()
        peerWindow = Win32.FindWindowA(null, title.buffer)
    }
    Swag.require(peerWindow != null, "the owned external window did not appear")
    var peerProcessId: Win32.DWORD
    discard Win32.GetWindowThreadProcessId(peerWindow, &peerProcessId)
    Swag.require(peerProcessId == peer.processId, "the external window belongs to another process")

    journey.surface.hide()
    let panel = unwrap ResidentPanel.open(journey.main, .Hub)
    var input = Gui.Testing.DesktopInput.create(journey.app, unwrap panel.surface)
    watch.restart()
    while watch.elapsedMilliseconds() < 120 do
        journey.app.runFrame()
    Swag.require(journey.main.residentPanel == panel, "the resident hub closed before the external click")
    Swag.require(panel.wasActive, "the resident hub did not arm its focus watch")

    var bounds: Win32.RECT
    Swag.require(Win32.GetWindowRect(peerWindow, &bounds))
    let point = Math.Point{(bounds.left + bounds.right) * 0.5, (bounds.top + bounds.bottom) * 0.5}
    let hit = Win32.WindowFromPoint(Win32.POINT{cast(s32, point.x), cast(s32, point.y)})
    Swag.require(Win32.GetAncestor(hit, Win32.GA_ROOT) == peerWindow,
                 "another desktop window covers the external click target")
    input.clickDesktopPoint(point)

    watch.restart()
    while journey.main.residentPanel != null and watch.elapsedMilliseconds() < 1000 do
        journey.app.runFrame()
    Swag.require(Win32.GetForegroundWindow() == peerWindow, "the external click did not take desktop focus")
    Swag.require(journey.main.residentPanel == null, "the resident hub stayed open after an external click")
}

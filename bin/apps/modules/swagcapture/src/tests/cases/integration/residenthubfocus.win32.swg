#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel, Win32

// Another application can take focus while the capture work window stays visible.
#[Swag.TestTag("integration.capture.hub.focus")]
#test
{
    var journey: CaptureJourney
    journey.setup()

    // A dedicated child owns the small window; the test never takes over a user's application.
    const title = "Swag Capture Cross Process Focus Fixture"
    let script = "Add-Type -AssemblyName System.Windows.Forms; $f=New-Object Windows.Forms.Form; $f.Text='Swag Capture Cross Process Focus Fixture'; $f.StartPosition='Manual'; $f.SetBounds(20,20,110,85); $f.TopMost=$true; $f.ShowInTaskbar=$false; [Windows.Forms.Application]::Run($f)"
    var peer   = expect Env.startProcess("powershell.exe",
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

    journey.main.showHub()
    let panel = unwrap journey.main.residentPanel
    let hubSurface = unwrap panel.surface
    watch.restart()
    while watch.elapsedMilliseconds() < 120 do
        journey.app.runFrame()
    Swag.require(journey.main.residentPanel == panel, "the capture window closed before the focus change")

    // Activate the owned fixture without clicking through whatever the user's desktop shows.
    discard Win32.SetForegroundWindow(peerWindow)
    watch.restart()
    while Win32.GetForegroundWindow() != peerWindow and watch.elapsedMilliseconds() < 1000 do
        journey.app.runFrame()
    Swag.require(Win32.GetForegroundWindow() == peerWindow, "the other application did not take desktop focus")

    watch.restart()
    while watch.elapsedMilliseconds() < 150 do
        journey.app.runFrame()
    Swag.require(journey.main.residentPanel == panel and not hubSurface.isHidden)
    Swag.require(journey.main.workspace == .Hub and not journey.surface.hasTrayIcon())
}

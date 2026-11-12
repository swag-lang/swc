#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel, Win32

// Open the resident hub, then click a different native window and leave the hub behind.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var otherApp: Application
    let otherSurface = expect otherApp.createSurface(40, 40, 280, 180)
    let otherButton = PushButton.create(otherSurface.wnd.view, "Other window", {32, 32, 160, 38})
    otherSurface.show()
    defer otherSurface.destroy()

    var journey: CaptureJourney
    journey.setup()
    journey.surface.hide()
    let panel = unwrap ResidentPanel.open(journey.main, .Hub)
    let panelHandle = panel.surface!.win32Handle()
    Swag.require(panelHandle != null)
    var hubInput = Gui.Testing.DesktopInput.create(journey.app, panel.surface)

    var watch: Time.Stopwatch
    watch.start()
    while Win32.GetForegroundWindow() != panelHandle and watch.elapsedMilliseconds() < 1000 do
        journey.app.runFrame()
    Swag.require(Win32.GetForegroundWindow() == panelHandle, "the resident hub did not take desktop focus")
    watch.start()
    while watch.elapsedMilliseconds() < 120 do
        journey.app.runFrame()
    Swag.require(journey.main.residentPanel == panel, "the resident hub closed before the outside click")

    scope
    {
        var input = Gui.Testing.DesktopInput.create(&otherApp, otherSurface)
        input.click(&otherButton.wnd)
        watch.start()
        while journey.main.residentPanel != null and watch.elapsedMilliseconds() < 1000 do
            journey.app.runFrame()
        Swag.require(journey.main.residentPanel == null, "the resident hub stayed open after another window took focus")
    }
}

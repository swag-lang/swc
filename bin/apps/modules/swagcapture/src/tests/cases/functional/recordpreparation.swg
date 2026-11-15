#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Video preparation releases the desktop and gives the live frame one explicit start action.
#test
{
    var f: HeadlessFixture
    f.setup(480, 120)
    defer f.shutdown()

    g_CaptureWindow   = {}
    g_CaptureAnchored = false
    let recorder = Memory.new'Recorder()
    defer Memory.delete(recorder)
    recorder.main      = f.main
    recorder.state     = .Preparing
    recorder.videoMode = true
    recorder.area      = {0, 0, 1280, 720}

    let width   = RecordHud.widthFor(0, recorder.readoutLabel(), preparing: true)
    let height  = cast(s32, RecordHudHeight + f.gui.theme.metrics.miniBar_ButtonSize + f.gui.theme.metrics.miniBar_Padding)
    let surface = expect f.gui.app.createSurface(0, 0, cast(s32, width), height, .ToolWindow | .TopMost | .Sheet)
    with let hud = RecordHud.create(surface.wnd, recorder)
    {
        .dockStyle = .Center
    }
    defer surface.destroy()
    surface.minSize = {}
    surface.setView(hud)
    surface.show()
    surface.wnd.applyLayout()

    var preview = f.gui.renderSurface(surface)
    Swag.require(preview.isValid())
    // The one action of a waiting pill is Record, in words, standing against the cross.
    let record = unwrap hud.recordButton
    Swag.require(record.isEnabled() and record.isLocallyVisible() and record.name == appStrings().ui_AimRecord)
    Swag.require(not hud.stopButton.isLocallyVisible() and not hud.pauseButton.isLocallyVisible())
    Swag.require(Math.abs(hud.cancelButton.position.x - record.position.right() - RecordHudButtonGap) < 0.01)

    // The pill says how large the video will be.
    Swag.require(Utf8.contains(hud.targetLabel.text(), recorder.pictureSizeText().toString()))
    Swag.require(hud.targetLabel.isLocallyVisible() and hud.targetLabel.position.right() <= record.position.x)
    #static if #os == Swag.TargetOs.Windows do
        Swag.require(hud.prepOptions.count == 4)
    else do
        Swag.require(hud.prepOptions.count == 3 and not hud.prepOptions[2].isEnabled())
    let options = &f.main.captureOptions
    Swag.require(options.recordVideoQuality == .Balanced)

    // The quality is chosen on the pill: a press moves to the next one and the button names it.
    let quality = unwrap hud.qualityButton
    Swag.require(quality.isLocallyVisible() and quality.position.right() <= hud.position.width)
    for expected in [VideoQuality.Compact, .Maximum, .Balanced]
    {
        quality.sigPressed.call(quality)
        Swag.require(options.recordVideoQuality == expected)
        Swag.require(Utf8.contains(quality.name.text.toString(), expected.label()))
    }
    Swag.require(VideoQuality.Maximum.quantizationQp() == 0 and VideoQuality.Balanced.quantizationQp() == 22)
    let before = [options.captureCursor, options.recordCountdown,
                  options.recordMicrophone, options.recordSystemSound]
    for button, index in hud.prepOptions where button.isEnabled()
    {
        let center = Math.Point{button[].position.width * 0.5, button[].position.height * 0.5}
        let local  = button[].localToSurface(center)
        let screen = Math.Point{surface.position.x + local.x * surface.dpiScale,
                                surface.position.y + local.y * surface.dpiScale}
        Swag.require(button[].focusPolicy == .Tab and button[].flags.has(.Toggle),
                     "recording options must use focusable toggle buttons")
        Swag.require(f.gui.mouseTargetAt(screen) == button,
                     "recording options must receive pointer events through the surface")
        f.gui.click(screen)
        Swag.require(button[].isChecked != before[index])
    }
    Swag.require(options.captureCursor != before[0] and options.recordCountdown != before[1])
    #static if #os == Swag.TargetOs.Windows do
        Swag.require(options.recordMicrophone != before[2] and options.recordSystemSound != before[3])
    record.sigPressed.call(record)
    Swag.require(recorder.recordRequested)

    recorder.state = .Recording
    hud.refresh()
    preview = f.gui.renderSurface(surface)
    Swag.require(preview.isValid())
    Swag.require(hud.stopButton.isLocallyVisible() and not hud.pauseButton.isEnabled())
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Viewers

func finishManualSubtitle(view: *Film.Panel)
{
    for 2_000
    {
        if view.subtitleLoad.isDone() do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(view.subtitleLoad.isDone())
    view.finishSubtitleLoad()
}

// Absolute timestamps and relative seconds reject malformed, overflowing and out-of-range input.
#test
{
    Swag.require(Viewer.parseTimeAddress("12:34", 100, 10_000) == 754)
    Swag.require(Viewer.parseTimeAddress("1:02:30", 100, 10_000) == 3_750)
    Swag.require(Viewer.parseTimeAddress(" +30 ", 100, 200) == 130)
    Swag.require(Viewer.parseTimeAddress("-10", 100, 200) == 90)
    Swag.require(Viewer.parseTimeAddress("0:00.25", 0, 1) == 0.25)
    for input in ["", "+", "1:60", "1:60:00", "1::2", "1:2:3:4", "nan", "inf", "1e3", "-101", "+101", "9999999999999999999999999999999999999999"] do
        Swag.require(Viewer.parseTimeAddress(input, 100, 200) < 0, input)
}

// The time control opens a validated dialog; jumping and undo keep a paused or playing transport.
#test
{
    let savedHints = Film.g_PlaybackHintUses
    defer Film.g_PlaybackHintUses = savedHints
    Film.g_PlaybackHintUses = 3
    let file = expect videoPreviewFile("scope-time-interactions.y4m", 16)
    defer catch File.delete(file)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, false)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    if view.playing do
        view.togglePlayback()
    view.seekSeconds(0.5)
    waitForVideoFrame(view)

    let dialog = view.createTimeDialog()
    dialog.setText("5:00")
    Swag.require(dialog.edit!.revalidate() == .InvalidVisible)
    Swag.require(not dialog.validateResult!(dialog, Dialog.BtnOk))
    Swag.require(view.elapsed == 0.5 and not view.playing)
    dialog.setText("+1")
    Swag.require(dialog.edit.revalidate() == .Valid)
    Swag.require(dialog.validateResult(dialog, Dialog.BtnOk))
    waitForVideoFrame(view)
    Swag.require(view.elapsed == 1.5 and not view.playing)
    Swag.require(view.previousSeek == 0.5)
    dialog.surface!.destroy()
    view.undoSeek()
    waitForVideoFrame(view)
    Swag.require(view.elapsed == 0.5 and view.previousSeek < 0 and not view.playing)

    view.togglePlayback()
    view.jumpTo(2)
    waitForVideoFrame(view)
    Swag.require(view.playing and view.elapsed == 2)
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    view.bottomVeil.timeButton.sigPressed.call(view.bottomVeil.timeButton)
    Swag.require(host.autoHandled and view.playing)
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    var goTo = KeyEvent{kind: .Pressed, key: .G, modifiers: .Control}
    Swag.require(window.routePlaybackKey(&goTo))
    Swag.require(host.autoHandled and view.playing)
}

// A subtitle dropped over the picture is attached to the movie; a bad replacement leaves it intact.
#test
{
    let file      = expect videoPreviewFile("scope-subtitle-drop.y4m", 16)
    let subtitles = Path.combine(Env.getSpecialDirectory(.Temp), "scope-unrelated-caption.srt")
    let broken    = Path.combine(Env.getSpecialDirectory(.Temp), "scope-broken-caption.srt")
    defer
    {
        catch File.delete(file)
        catch File.delete(subtitles)
        catch File.delete(broken)
    }

    expect File.writeAllBytes(subtitles, "1\n00:00:00,000 --> 00:00:03,000\nA manually loaded caption\n")
    expect File.writeAllBytes(broken, "No timed cues")
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, false)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    view.togglePlayback()
    view.seekSeconds(0)
    waitForVideoFrame(view)
    Swag.require(not view.subtitleReady and view.tracksButton.isEnabled())
    var point = view.imageView.surfaceRect().center()
    window.surface!.surfaceToScreen(&point)
    Swag.require(host.dropFiles(point, [subtitles.toString()]) == DropEffect.Copy)
    Swag.require(window.pendingFile.isEmpty() and view.pendingSubtitle == subtitles)
    host.fireTimer(view.timer)
    finishManualSubtitle(view)
    Swag.require(view.subtitleReady and view.subtitleSource == .Sidecar)
    Swag.require(view.subtitleOverlay.text == "A manually loaded caption")
    Swag.require(window.currentFile == file and not view.playing)
    let activeTrack = view.subtitleTrack()
    view.loadSubtitle(broken)
    finishManualSubtitle(view)
    Swag.require(view.subtitleTrack() == activeTrack and view.subtitleToast != null)
    Swag.require(view.subtitleOverlay.text == "A manually loaded caption")
    host.acceptModalFileDialog(subtitles)
    view.promptSubtitle()
    Swag.require(host.autoHandled)
    finishManualSubtitle(view)
    Swag.require(view.subtitleOverlay.sidecars.count == 1)
    Swag.require(window.currentFile == file and not view.playing)
    view.subtitleDelay = 0.3
    var reading: ViewerReadingState
    reading.capture(&window.instances[window.activeChoiceIndex], "video", "")
    Swag.require(reading.subtitleDelay == 0.3)
}

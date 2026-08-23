#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Audio

func videoPreviewFile(name: string, frameCount = 4'u32)->String fail
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), name)
    let rate     = try FrameRate.create(4, 1)
    var clip     = try Clip.create(160, 90, rate)

    for index in frameCount
    {
        var frame      = Image.create(160, 90, .RGB8)
        let colorIndex = index % 4
        frame.fill(colorIndex == 0 ? Color.fromRgb(18, 24, 32) : (colorIndex == 1 ? Color.fromRgb(56, 189, 248) : (colorIndex == 2 ? Color.fromRgb(247, 249, 0) : Color.fromRgb(130, 70, 180))))
        try clip.addFrame(frame)
    }

    try clip.save(fileName.toString())
    return fileName
}

func waitForVideoFrame(view: *VideoViewer)
{
    // Playback runs a producer ahead of the clock, so a picture reaches the screen only when
    // the viewer is next pumped. Drive that pump until the requested picture is published.
    while view.awaitingFrame
    {
        Threading.Thread.yield()
        view.updatePlayback()
    }
}

func videoAudioFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/glint-aac-mjpeg.mp4")
}

#test
{
    let fileName = expect videoPreviewFile(Format.toString("filescope-video-clock-%.mp4", Guid64.random()).toString(), 12)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)

    // A late decoder follows the presentation clock directly. The old catch-up cap decoded
    // frame 4 here and permanently slowed the clock instead of dropping six obsolete frames.
    view.playing = true
    view.elapsed = view.frameSeconds(10)
    view.clock.reset()
    view.updatePlayback()
    waitForVideoFrame(view)
    @assert(view.frameIndex == 10)
}

#test
{
    let fileName = expect videoPreviewFile(Format.toString("filescope-video-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    @assert(view.video.frameCount() == 4)
    @assert(view.frameIndex == 0 and !view.playing)
    @assert(view.details.indexOf("160") != Swag.U64.Max)
    @assert(view.details.indexOf("4 frames") != Swag.U64.Max)
    @assert(view.details.indexOf("Swag CPU") != Swag.U64.Max)
    @assert(view.timeLabel.text() == "0:00 / 0:01")

    view.seekFrame(2)
    waitForVideoFrame(view)
    @assert(view.frameIndex == 2)
    view.seekRelative(-10)
    waitForVideoFrame(view)
    @assert(view.frameIndex == 0)
    view.seekRelative(10)
    waitForVideoFrame(view)
    @assert(view.frameIndex == 3)
    view.timeline.setValue(3)
    waitForVideoFrame(view)
    @assert(view.frameIndex == 3)
    view.togglePlayback()
    @assert(view.playing)
    view.togglePlayback()
    @assert(!view.playing)
    view.stopPlayback()
    waitForVideoFrame(view)
    @assert(view.frameIndex == 0 and view.elapsed == 0)
}

#test
{
    let fileName = expect videoPreviewFile("viewer.video.preview.y4m")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(720, 420)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let request = ViewerRequest{&host.root, commandBar, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    view.dockStyle          = .Center
    view.commands.dockStyle = .Center
    view.seekFrame(2)
    waitForVideoFrame(view)

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.video.document")
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-video-", ".y4m")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a video")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}

#test
{
    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let fileName = videoAudioFixturePath()
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    @assert(view.audio != null and view.voice != null and view.video.audioTrackCount() == 1)
    view.setVolume(0.35)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.35, 0.001))
    view.setMuted(true)
    @assert(view.muted and view.muteButton.isChecked())
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0, 0.001))
    view.setMuted(false)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.35, 0.001))

    view.togglePlayback()
    @assert(view.playing and view.voice!.isPlaying())
    view.seekFrame(5)
    waitForVideoFrame(view)
    @assert(!view.resumeAudioAfterSeek and view.voice!.isPlaying())
    @assert(view.voice!.playbackSampleFrame() == cast(u64) Math.round(view.video.frameTimestamp(5) * 44_100.0))
    view.togglePlayback()
    @assert(!view.playing and !view.voice!.isPlaying())
    view.stopPlayback()
    @assert(view.voice!.playbackSampleFrame() == 0)
}

// An output device that never consumes what it was given reports the same position for ever.
// Presentation follows the sound, but it may not stop when the sound does: the no-sound backend
// consumes nothing here, and the picture still has to advance.
#test
{
    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let fileName = videoAudioFixturePath()
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    @assert(view.voice != null)

    let stalled = view.voice!.playbackSampleFrame()
    view.togglePlayback()
    @assert(view.playing)

    var attempts = 0
    while view.frameIndex == 0 and attempts < 4000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    @assert(view.voice!.playbackSampleFrame() == stalled)
    @assert(view.frameIndex != 0)
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Audio

func countVideoLoadingChange(wnd: *Wnd)
{
    let count = cast(*u32) wnd.userData!
    count[] += 1
}

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

func videoAvcFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/ffmpeg-h264-baseline.mp4")
}

func videoMatroskaFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/ffmpeg-h264-two-aac.mkv")
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

    // A Motion JPEG stream has no planes to hand over, so the queue holds packed pictures.
    @assert(!view.planar)
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
    @assert(view.backwardButton.icon.isValid() and view.forwardButton.icon.isValid())
    @assert(view.muteButton.icon.isValid() and view.muteButton.flags.has(.Toggle))
    @assert(view.audio != null and view.voice != null and view.video.audioTrackCount() == 1)
    view.setVolume(0.35)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.35, 0.001))
    view.setMuted(true)
    @assert(view.muted and view.muteButton.isChecked)
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

// A Matroska file carrying several sound tracks exposes a compact selector. Changing it creates
// and positions the replacement voice before releasing the previous one, so transport, volume,
// and mute state survive the handoff.
#test
{
    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(ViewerMinWidth, 450)
    defer host.shutdown()
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commands.dockStyle       = .Bottom
    commands.backgroundStyle = .Window
    commands.padding         = {16, 8, 16, 8}
    let path    = videoMatroskaFixturePath()
    let request = ViewerRequest{&host.root, commands, path}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    @assert(view.timeline.isEnabled())
    waitForVideoFrame(view)

    // Reaching the compact fixture's last cluster completes its sound packet tables through the
    // same foreground demux cursor; there is no background full-file scan to wait for.
    view.seekFrame(19)
    waitForVideoFrame(view)

    @assert(view.video.audioTrackCount() == 2 and view.audioCombo != null)
    @assert(view.audioCombo!.items.count == 2 and view.audioCombo!.selectedIndex == 0)
    @assert(view.audioCombo!.items[0]!.name.raw.indexOf("44.1 kHz") != Swag.U64.Max)
    view.setVolume(0.4)
    view.setMuted(true)
    view.seekFrame(5)
    waitForVideoFrame(view)
    let previousVoice = view.voice!

    view.audioCombo!.setSelectedIndex(1)
    @assert(view.audioTrackIndex == 1 and view.audio == view.video.audioTrack(1))
    @assert(view.voice != null and view.voice != previousVoice)
    @assert(view.muted and Math.isEqualEpsilon(expect view.voice!.volume(), 0, 0.001))
    @assert(view.voice!.playbackSampleFrame() == cast(u64) Math.round(view.video.frameTimestamp(5) * 44_100.0))

    view.setMuted(false)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.4, 0.001))

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    @assert(view.audioCombo!.toolTip == "Piste audio")
    @assert(view.audioCombo!.items[1]!.name.raw.indexOf("can.") != Swag.U64.Max)

    view.dockStyle          = .Center
    view.commands.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(view.commands)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.video.multiaudio")
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

// An H.264 stream is played from the planes its decoder reconstructed, without ever being
// converted to packed pixels.
//
// This is the path that matters for a real recording: converting a picture to RGB costs more
// processor time at high resolutions than decoding it did, and the renderer can sample the planes
// where it draws. Seeking must keep using it, since a seek rebuilds the queue.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let fileName = videoAvcFixturePath()
    let request  = ViewerRequest{
        contentParent: &host.root,
        commandParent: commands,
        fileName: fileName,
        reportLoadingChanged: &countVideoLoadingChange}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    var loadingChanges: u32
    view.userData = &loadingChanges
    waitForVideoFrame(view)

    @assert(view.planar)
    @assert(view.video.width() == 64 and view.video.height() == 48)
    @assert(view.frameIndex == 0 and !view.hasFailure)
    @assert(result.isLoading != null and !result.isLoading!(view))

    // A viewer reports every outstanding visible picture, not only its first one. The application
    // can therefore cover a stale frame while this exact seek reconstructs its target.
    view.repositionTo(12)
    @assert(result.isLoading!(view))
    @assert(loadingChanges == 1)
    view.decodeWake.signal()
    waitForVideoFrame(view)
    @assert(view.frameIndex == 12 and !view.hasFailure)
    @assert(!result.isLoading!(view))
    @assert(loadingChanges == 2)
    @assert(view.planar)
    view.userData = null
}

// The run-ahead queue stays a FIFO as pictures are taken from it.
//
// Taking the front with an unstable removal put the newest picture there instead, and the ones it
// stepped over were never taken at all: the queue reported itself full while the run-ahead it
// exists for had shrunk to two pictures, so any decode longer than one frame period reached the
// screen as a stall. Playback still looked sequential, which is why this needs an assertion on the
// order rather than on what was shown.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("filescope-video-queue-%.mp4", Guid64.random()).toString(), 40)
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
    @assert(view.frameIndex == 0)

    // A paused viewer decodes only the picture it is parked on, so let the producer run and wait
    // until it has filled every slot, which is also when it stops touching the queue.
    view.playing = true
    view.clock.reset()
    view.decodeWake.signal()
    var attempts = 0
    while view.ready.count < cast(u64) view.slotCount and attempts < 5000
    {
        Threading.Thread.sleep(1'ms)
        attempts += 1
    }

    @assert(view.ready.count == cast(u64) view.slotCount)

    for step in 1 to 5
    {
        view.elapsed = view.frameSeconds(step)
        view.clock.reset()
        @assert(view.publishHead(step, true))
        @assert(view.frameIndex == step)

        // Everything still queued follows what is on screen, in order and without a hole.
        Sync.scopedLock(&view.queueLock)
        var expected = view.frameIndex
        for slot in view.ready
        {
            expected += 1
            @assert(view.slots[cast(u64) slot].index == expected)
        }
    }
}

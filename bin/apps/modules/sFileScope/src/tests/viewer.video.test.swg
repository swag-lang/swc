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
    var attempts: u32
    while (!view.openFinished or view.awaitingFrame) and attempts < 5_000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    @assert(view.openFinished and !view.awaitingFrame)
}

func waitForVideoAudio(view: *VideoViewer, count: u32)
{
    var attempts: u32
    while view.video.audioTrackCount() != count and attempts < 5000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    @assert(view.video.audioTrackCount() == count)
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

// A same-stem sidecar is discovered, selected, and presented on the movie clock. Rendering
// preferences and manual synchronization are available from the same track menu.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("filescope-video-subtitle-%.mp4", Guid64.random()).toString())
    let folder   = Path.directoryName(fileName)!
    let stem     = Path.fileNameWithoutExtension(fileName)!
    let sidecar  = Path.combine(folder, Format.toString("%.fr.srt", stem).toString())
    defer
    {
        discard catch File.delete(sidecar)
        discard catch File.delete(fileName)
    }

    expect File.writeAllBytes(sidecar, "1\n00:00:00,000 --> 00:00:00,400\nOpening caption\n\n2\n00:00:00,500 --> 00:00:00,900\nSecond caption\n")

    let savedSettings = g_VideoSubtitleSettings
    defer g_VideoSubtitleSettings = savedSettings
    g_VideoSubtitleSettings = {}

    let standalone = expect Subtitle.Track.loadOwned(sidecar.toString())
    @assert(standalone != null)
    let standaloneText = videoSubtitleText(standalone!.cueTextData(0), standalone!.cueTextLength(0))
    @assert(standaloneText == "Opening caption")
    Subtitle.Track.destroy(standalone!)

    var host: Testing.HeadlessHost
    host.setup(720, 420)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 480, 36})
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    view.playing = false
    view.elapsed = 0

    view.finishSubtitles()
    view.refreshSubtitle()
    @assert(view.subtitleOverlay.sidecars.count == 1 and view.subtitleSource == .Sidecar)
    @assert(view.subtitleButton.isEnabled())
    let opening = videoSubtitleText(view.subtitleOverlay.sidecars[0].cueTextData(0), view.subtitleOverlay.sidecars[0].cueTextLength(0))
    @assert(opening == "Opening caption")
    @assert(view.subtitleOverlay.text == "Opening caption")
    view.seekSeconds(0.6)
    waitForVideoFrame(view)
    view.refreshSubtitle()
    @assert(view.subtitleOverlay.text == "Second caption")

    g_VideoSubtitleSettings.delay = -0.5
    view.subtitleSettingsChanged()
    @assert(view.subtitleOverlay.text == "Opening caption")

    host.openPopupSubMenuWhenShown(videoStrings().ui_SubtitleSize)
    host.thenClickPopupMenuItem("sFileScope.video.subtitle.size.large")
    view.showSubtitleMenu()
    @assert(g_VideoSubtitleSettings.size == .Large)
    host.clickPopupMenuItemWhenShown("sFileScope.video.subtitle.off")
    view.showSubtitleMenu()
    @assert(view.subtitleSource == .Off and view.subtitleOverlay.text.isEmpty())
}

// Switching files retires the old decoder immediately, before deferred GUI deletion keeps its
// frame buffers alive while the replacement allocates its H.264 contexts.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let index    = createViewerIndex()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    let fileName = videoAvcFixturePath()
    window.openFile(fileName, remember: false)
    @assert(window.currentView != null)
    let previous = cast(*VideoViewer) window.currentView!
    waitForVideoFrame(previous)
    @assert(previous.video.isOpen())

    window.openFile(fileName, remember: false)
    @assert(window.currentView == previous)
    var attempts: u32
    while (window.outgoingView != previous or window.instances.isEmpty()) and attempts < 5_000
    {
        Threading.Thread.sleep(1'ms)
        if window.startupTimer do
            host.fireTimer(window.startupTimer)
        attempts += 1
    }

    @assert(window.outgoingView == previous and window.currentView == previous)
    @assert(!previous.isPendingDestroy)
    let incoming = cast(*VideoViewer) window.instances[window.activeChoiceIndex].view!
    @assert(incoming != previous)
    waitForVideoFrame(incoming)
    window.commitViewerTransition(incoming)
    @assert(previous.isPendingDestroy)
    @assert(window.currentView == incoming and window.outgoingView == null)
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
    host.setReducedMotion(true)

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
    @assert(view.seekOverlay!.isLocallyVisible() and view.seekOverlay!.direction == -1 and view.seekOverlay!.text == "-10")
    @assert(view.seekOverlay!.presentationOffset == {} and view.seekOverlay!.presentationScale == {1, 1})
    @assert(view.seekOverlay!.position.vertCenter() > view.clientRect().vertCenter())
    waitForVideoFrame(view)
    @assert(view.frameIndex == 0)
    view.seekRelative(10)
    @assert(view.seekOverlay!.isLocallyVisible() and view.seekOverlay!.direction == 1 and view.seekOverlay!.text == "+10")
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
    @assert(view.audioButton.isVisible() and !view.audioButton.isEnabled())
    @assert(view.muteButton.isVisible() and !view.muteButton.isEnabled())
    @assert(view.volumeSlider.isVisible() and !view.volumeSlider.isEnabled())

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    host.setReducedMotion(false)
    view.showSeekFeedback(10)
    @assert(view.seekOverlay!.timer != null and view.seekOverlay!.presentationOffset.x < 0)
    host.advanceAnimations(0.15)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.video.document")

    let overlayTimer = view.seekOverlay!.timer!
    host.fireTimer(overlayTimer)
    @assert(!view.seekOverlay!.isLocallyVisible() and view.seekOverlay!.timer == null)

    host.theme.setSwagLight()
    host.notify(.ThemeChanged)
    view.showSeekFeedback(-10)
    @assert(view.seekOverlay!.backgroundStyle == .Transparent)
    @assert(Voltage.contrastRatio(Ink) >= 4.5)
    host.fireTimer(view.seekOverlay!.timer!)
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
    @assert(result.view != null and result.commands != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    @assert(!view.openFailure.isEmpty() and !view.video.isOpen())
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
    view.timeline.setValue(cast(f32) view.frameSeconds(5))
    @assert(view.awaitingFrame and view.resumeAudioAfterSeek)
    waitForVideoFrame(view)
    @assert(!view.resumeAudioAfterSeek and view.voice!.isPlaying())
    @assert(view.voice!.playbackSampleFrame() == cast(u64) Math.round(view.video.frameTimestamp(5) * 44_100.0))
    view.togglePlayback()
    @assert(!view.playing and !view.voice!.isPlaying())
    view.stopPlayback()
    @assert(view.voice!.playbackSampleFrame() == 0)
}

// Full-screen chrome is presentation-only: resizing and revealing either bar preserves the
// active voice and the transport state.
#test
{
    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(videoAudioFixturePath(), remember: false)
    let view = cast(*VideoViewer) window.currentView!
    waitForVideoFrame(view)

    // A click on the bottom timeline replaces the stale picture with the central wait overlay
    // until the decoder publishes the requested frame.
    view.timeline.setValue(cast(f32) view.frameSeconds(5))
    @assert(view.awaitingFrame and window.loadingOverlay.isLocallyVisible())
    waitForVideoFrame(view)
    window.updateLoadingIndicator()
    @assert(!window.loadingOverlay.isLocallyVisible())

    view.togglePlayback()
    let voice = view.voice!

    window.setFullScreen(true)
    window.updateFullScreenChrome({10, 1})
    window.updateFullScreenChrome({10, window.clientRect().height - 1})
    window.setFullScreen(false)

    @assert(view.playing and view.voice == voice and voice.isPlaying())
}

// Playback shortcuts belong to the active media viewer, not to whichever toolbar or panel
// happens to own focus. Held-key repeats are consumed without toggling transport again.
#test
{
    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(videoAudioFixturePath(), remember: false)
    let view = cast(*VideoViewer) window.currentView!
    @assert(window.loadingOverlay.isLocallyVisible())
    waitForVideoFrame(view)
    window.updateLoadingIndicator()
    @assert(!window.loadingOverlay.isLocallyVisible())

    window.viewerCombo.setFocus()
    var press = KeyEvent{kind: .Pressed, key: .Space}
    @assert(window.hookOnChildEvent!(window.viewerCombo, &press))
    @assert(view.playing and view.voice!.isPlaying() and window.viewerCombo.hasFocus())
    @assert(window.hookOnChildEvent!(window.viewerCombo, &press))
    @assert(view.playing and view.voice!.isPlaying())

    var release = KeyEvent{kind: .Released, key: .Space}
    @assert(window.hookOnChildEvent!(window.viewerCombo, &release))
    @assert(window.hookOnChildEvent!(window.viewerCombo, &press))
    @assert(!view.playing and !view.voice!.isPlaying() and window.viewerCombo.hasFocus())
    @assert(window.hookOnChildEvent!(window.viewerCombo, &release))
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
    waitForVideoFrame(view)
    @assert(view.timeline.isEnabled())
    waitForVideoAudio(view, 2)

    @assert(view.video.audioTrackCount() == 2)
    @assert(view.audioButton.isVisible() and view.audioButton.icon.isValid() and view.audioTrackIndex == 0)
    @assert(videoAudioTrackText(0, view.video.audioTrack(0)!).indexOf("Primary") != Swag.U64.Max)
    @assert(videoAudioTrackText(1, view.video.audioTrack(1)!).indexOf("Alternate") != Swag.U64.Max)
    @assert(videoAudioTrackText(0, view.video.audioTrack(0)!).indexOf("44.1 kHz") != Swag.U64.Max)
    @assert(view.muteButton.isVisible() and view.volumeSlider.isVisible())
    @assert(view.details.indexOf("AAC-LC") != Swag.U64.Max and view.details.indexOf("2 ch") != Swag.U64.Max)
    @assert(videoAudioEncodingText(.Ac3) == "AC-3" and videoAudioEncodingText(.Eac3) == "E-AC-3")
    @assert(videoAudioEncodingText(.Dts) == "DTS" and videoAudioEncodingText(.Flac) == "FLAC" and videoAudioEncodingText(.Mp3) == "MP3")
    view.setVolume(0.4)
    view.setMuted(true)
    view.seekFrame(5)
    waitForVideoFrame(view)
    view.togglePlayback()
    @assert(view.playing and view.voice!.isPlaying())
    let previousVoice = view.voice!

    host.clickPopupMenuItemWhenShown("sFileScope.video.audioTrack.1")
    view.showAudioTrackMenu()
    @assert(view.audioTrackIndex == 1 and view.audio == view.video.audioTrack(1))
    @assert(view.voice != null and view.voice != previousVoice)
    @assert(view.voice!.isPlaying())
    @assert(view.muted and Math.isEqualEpsilon(expect view.voice!.volume(), 0, 0.001))
    let switchedSample = view.voice!.playbackSampleFrame()
    let seekSample     = cast(u64) Math.round(view.video.frameTimestamp(5) * 44_100.0)
    @assert(switchedSample >= seekSample and switchedSample - seekSample < 4_410)

    view.setMuted(false)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.4, 0.001))
    expect view.selectAudioTrack(0)
    @assert(view.playing and view.audioTrackIndex == 0 and view.voice!.isPlaying())
    expect view.selectAudioTrack(1)
    @assert(view.playing and view.audioTrackIndex == 1 and view.voice!.isPlaying())
    view.togglePlayback()
    view.seekFrame(5)
    waitForVideoFrame(view)
    @assert(Math.isEqualEpsilon(view.timeline.value(), cast(f32) view.frameSeconds(5), 0.001))

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    @assert(view.audioButton.toolTip == "Piste audio")
    @assert(videoAudioTrackText(1, view.video.audioTrack(1)!).indexOf("can.") != Swag.U64.Max)
    @assert(view.details.indexOf("2 can.") != Swag.U64.Max)

    view.dockStyle          = .Center
    view.commands.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    @assert(view.audioButton.position.width == 36)
    @assert(view.timeline.position.right() <= view.timeLabel.position.x)
    @assert(view.timeLabel.position.right() <= view.muteButton.position.x)
    @assert(view.volumeSlider.position.right() <= view.subtitleButton.position.x)
    @assert(view.subtitleButton.position.right() <= view.audioButton.position.x)
    @assert(view.audioButton.position.right() == view.commands.clientRect().right())
    Testing.assertContentFits(view.commands)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.video.multiaudio")
}

// A progressive sound prefix must not become the master clock for a seek beyond that prefix.
// It stays paused until a longer index arrives, while the picture timeline remains at the point
// the user requested instead of snapping back to the last indexed sound sample.
#test
{
    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    let fileName = expect videoPreviewFile(Format.toString("filescope-video-audio-range-%.mp4", Guid64.random()).toString(), 12)
    defer discard catch File.delete(fileName)
    let soundPath = Gui.Testing.tempFilePath("filescope-video-audio-range-", ".pcm")
    defer discard catch File.delete(soundPath)
    var pcm: Array'u8
    pcm.resize(200)
    expect File.writeAllBytes(soundPath, pcm.toSlice())
    let packets: [1] SoundPacket = [{0, 200, 100}]
    let sound = Memory.new'SoundFile()
    sound[] = #nodrop #move expect SoundFile.openPcmPacketStream(soundPath, .Pcm16, 100, 1, packets)

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

    view.audio   = sound
    view.voice   = expect Voice.create(sound)
    view.playing = true
    view.clock.restart()
    view.seekFrame(8)
    waitForVideoFrame(view)
    @assert(view.audioRangePending and view.resumeAudioAfterSeek and !view.voice!.isPlaying())
    @assert(view.currentSeconds() >= 1.9 and view.voice!.playbackSampleFrame() == 0)
    view.followAudioClock()
    @assert(view.currentSeconds() >= 1.9)

    // Once the progressive index reaches the target, the deferred seek is still remembered and
    // positions the replacement voice before sound resumes.
    let longerPath = Gui.Testing.tempFilePath("filescope-video-audio-range-long-", ".pcm")
    defer discard catch File.delete(longerPath)
    pcm.resize(800)
    expect File.writeAllBytes(longerPath, pcm.toSlice())
    const LongerPackets: [1] SoundPacket = [{0, 800, 400}]
    let longerSound = Memory.new'SoundFile()
    longerSound[] = #nodrop #move expect SoundFile.openPcmPacketStream(longerPath, .Pcm16, 100, 1, LongerPackets)
    view.voice!.destroy()
    view.voice = null
    view.audio = null
    Memory.delete(sound)
    view.audio = longerSound
    view.voice = expect Voice.create(longerSound)
    view.resumeAudio()
    @assert(!view.audioRangePending and !view.resumeAudioAfterSeek and view.voice!.isPlaying())
    @assert(view.voice!.playbackSampleFrame() >= 200)
    view.voice!.destroy()
    view.voice = null
    view.audio = null
    Memory.delete(longerSound)
}

// A Matroska seek window carries a media-timeline origin. The viewer maps that absolute movie
// position to the window's local sample frames instead of treating the window as time zero.
#test
{
    let soundPath = Gui.Testing.tempFilePath("filescope-video-audio-window-", ".ac3")
    defer discard catch File.delete(soundPath)
    expect File.writeAllBytes(soundPath, [0x0B'u8, 0x77, 0, 0, 0, 0, 0])
    const Packets: [1] SoundPacket = [{0, 7, 1536}]
    var config: Array'u8
    var sound = expect SoundFile.openPacketStream(soundPath, .Ac3, 48_000, 2, 1536, Packets, config.toSlice(), {timelineStartSeconds: 100})

    @assert(!videoSoundCovers(&sound, 99.99))
    @assert(videoSoundCovers(&sound, 100.01))
    @assert(videoSoundSample(&sound, 100.01) == 480)
    @assert(!videoSoundCovers(&sound, 101))
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
    let view           = cast(*VideoViewer) result.view!
    let loadingChanges = Memory.new'u32()
    view.userData = loadingChanges
    waitForVideoFrame(view)
    loadingChanges[] = 0

    @assert(view.planar)
    @assert(view.video.width() == 64 and view.video.height() == 48)
    @assert(view.frameIndex == 0 and !view.hasFailure)
    @assert(result.isLoading != null and !result.isLoading!(view))

    // A viewer reports every outstanding visible picture, not only its first one. The application
    // can therefore cover a stale frame while this exact seek reconstructs its target.
    view.repositionTo(12)
    @assert(result.isLoading!(view))
    @assert(loadingChanges[] == 1)
    view.decodeWake.signal()
    waitForVideoFrame(view)
    @assert(view.frameIndex == 12 and !view.hasFailure)
    @assert(!result.isLoading!(view))
    @assert(loadingChanges[] == 2)
    @assert(view.planar)
    view.userData = null
    Memory.delete(loadingChanges)
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

// Falling behind jumps to a clean sync picture. The wait overlay remains visible until that
// picture is available, so a decoder below playback speed reports its actual state.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("filescope-video-resync-%.mp4", Guid64.random()).toString(), 40)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null and result.isLoading != null and result.needsLoadingOverlay != null)
    let view = cast(*VideoViewer) result.view!
    waitForVideoFrame(view)
    @assert(view.frameIndex == 0)

    view.playing = true
    view.elapsed = view.frameSeconds(12)
    view.clock.reset()
    view.updatePlayback()

    @assert(view.awaitingFrame and result.isLoading!(view))
    @assert(result.needsLoadingOverlay!(view))
    waitForVideoFrame(view)
    @assert(view.frameIndex == 12)
}

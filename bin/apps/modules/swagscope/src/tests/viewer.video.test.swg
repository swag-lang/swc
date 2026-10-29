#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Audio, Viewers

// Opening fades are excluded; histogram selection returns a representative later scene.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp), "thumbnail-fade.y4m")
    defer catch File.delete(path)
    var clip = expect Clip.create(64, 48, expect FrameRate.create(4, 1))
    for index in 20
    {
        var image = Image.create(64, 48, .RGB8)
        image.fill(index < 5 ? Color.fromRgb(0, 0, 0) : Color.fromRgb(56, 189, 248))
        expect clip.addFrame(image)
    }

    expect clip.save(path)
    let thumbnail = expect Film.loadThumbnail(path)
    let color     = thumbnail.pixelColor(32, 24)
    Swag.assert(color.g > 160 and color.b > 200)

    var candidates: Array'Film.ThumbnailCandidate
    for color in [Color.fromRgb(0, 0, 0), Color.fromRgb(255, 255, 255), Color.fromRgb(56, 189, 248)]
    {
        var candidate: Film.ThumbnailCandidate
        candidate.image = Image.create(32, 24, .RGB8)
        candidate.image.fill(color)
        candidate.analyze()
        candidates.add(#move candidate)
    }

    Swag.assert(not candidates[0].usable and not candidates[1].usable and candidates[2].usable)
    Swag.assert(Film.representativeThumbnail(candidates.toSlice()) == 2)
}

// The first lively picture is kept without decoding the other positions: contrast decides, a flat
// colour or a mostly dark frame does not qualify.
#test
{
    var flat: Film.ThumbnailCandidate
    flat.image = Image.create(32, 24, .RGB8)
    flat.image.fill(Color.fromRgb(56, 189, 248))
    flat.analyze()
    Swag.assert(flat.usable and not flat.lively)

    var bands: Film.ThumbnailCandidate
    bands.image = Image.create(32, 24, .RGB8)
    for index in bands.image.pixels.count do
        bands.image.pixels[index] = cast(u8, ((index / 3) % 32) * 8)
    bands.analyze()
    Swag.assert(bands.usable and bands.lively)
}

// The black bands a film was encoded with are trimmed from every edge; a frame dark from edge to
// edge is a dark scene and stays whole.
#test
{
    var boxed = Image.create(64, 48, .RGB8)
    Memory.set(boxed.pixels.storage(), 0, boxed.pixels.count)
    for y in 6 until 42
    {
        for x in 4 until 60
        {
            let pixel = boxed.pixels.storage() + cast(u64, y) * cast(u64, boxed.rowStride) + cast(u64, x) * 3
            Memory.set(pixel, 160, 3)
        }
    }

    Film.trimLetterbox(&boxed)
    Swag.assert(boxed.width == 56 and boxed.height == 36)

    var night = Image.create(64, 48, .RGB8)
    Memory.set(night.pixels.storage(), 8, night.pixels.count)
    Film.trimLetterbox(&night)
    Swag.assert(night.width == 64 and night.height == 48)
}

// The duration a thumbnail carries comes back from its metadata and reads the way players write it.
#test
{
    var image = Image.create(4, 4, .RGB8)
    Swag.assert(thumbnailDuration(&image) == 0)
    var record: ImageMetadata
    record.tag   = Viewer.ThumbnailDurationTag
    record.value = "7083"
    image.metadata.add(#move record)
    Swag.assert(thumbnailDuration(&image) == 7083)
    Swag.assert(formatDuration(7083) == "1:58:03" and
                formatDuration(65) == "1:05" and
                formatDuration(9) == "0:09")
}

// Both decoder paths propagate failure into the producer's catch before the queue reports it.
#test
{
    for planar in [false, true]
    {
        var view: Film.Panel
        view.planar = planar
        view.slots.resize(1)
        view.freeSlots.add(0)
        let produced = view.produceOne()
        Swag.assert(not produced and view.hasFailure)
        Swag.assert(view.failureText == failureShape(appStrings().ui_FailureUnreadable, "video reader has no open stream"))
        Swag.assert(view.inFlight == 0 and view.ready.isEmpty() and view.freeSlots.count == 1)
    }
}

func countVideoLoadingChange(wnd: *Wnd)
{
    let count = cast(*u32, unwrap wnd.userData)
    count[] += 1
}

func videoPreviewFile(name: string, frameCount = 4'u32)->String fail => try videoPreviewFileAt(Path.combine(Env.getSpecialDirectory(.Temp), name), frameCount)

// Writes a short silent movie of `frameCount` solid pictures at `fileName`.
func videoPreviewFileAt(fileName: string, frameCount = 4'u32)->String fail
{
    let rate    = try FrameRate.create(4, 1)
    var clip    = try Clip.create(160, 90, rate)
    let palette = [Color.fromRgb(18, 24, 32), Color.fromRgb(56, 189, 248), Color.fromRgb(247, 249, 0), Color.fromRgb(130, 70, 180)]

    for index in frameCount
    {
        var frame = Image.create(160, 90, .RGB8)
        frame.fill(palette[index % palette.count])
        try clip.addFrame(frame)
    }

    try clip.save(fileName)
    return fileName
}

// Answers a movie that has been played through with the continuation stored on the view.
func answerVideoEnd(wnd: *Wnd)->Viewer.Continuation
{
    let answer = cast(*Viewer.Continuation, unwrap wnd.userData)
    return answer[]
}

// Runs the movie on screen to its end and lets the transport act on the host's answer.
func playVideoThrough(view: *Film.Panel)
{
    let count = view.video.frameCount()
    view.seekFrame(count - 1)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == count - 1 and view.playing)

    // No sound owns this clock, so pushing it past the end is exactly what real time would do.
    view.elapsed = view.video.durationInSeconds() + 1
    view.updatePlayback()
}

// Completes the hand-over to the file a play mode queued.
//
// The movie on its way out retires on its own thread, so the classification is pumped with
// real time between turns rather than spun.
func completeVideoHandover(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while not window.pendingFile.isEmpty() and steps < 5_000
    {
        Threading.Thread.sleep(1'ms)
        Swag.drainWork()
        host.pump()
        if window.startupTimer do
            host.fireTimer(window.startupTimer)
        steps += 1
    }

    Swag.assert(window.pendingFile.isEmpty())
}

func waitForVideoFrame(view: *Film.Panel)
{
    // Playback runs a producer ahead of the clock, so a picture reaches the screen only when
    // the viewer is next pumped. Drive that pump until the requested picture is published.
    var attempts: u32
    while (not view.openFinished or view.awaitingFrame) and attempts < 5_000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    Swag.assert(view.openFinished and not view.awaitingFrame)
}

// Withholds every free slot and drains any in-flight decode, so a test can observe a loading state.
//
// A fast background producer must not decide whether a test sees the requested wait overlay.
func holdVideoProducer(view: *Film.Panel)
{
    for 5_000
    {
        scope
        {
            Sync.scopedLock(&view.queueLock)
            view.ready.clear()
            view.freeSlots.clear()
            if not view.inFlight do
                return
        }

        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(false)
}

// Hands back every slot [[holdVideoProducer]] withheld, and wakes the producer.
func releaseVideoProducer(view: *Film.Panel)
{
    scope
    {
        Sync.scopedLock(&view.queueLock)
        Swag.assert(not view.inFlight and view.ready.isEmpty() and view.freeSlots.isEmpty())
        for index in view.slotCount do
            view.freeSlots.add(cast(u32, index))
    }

    view.decodeWake.signal()
}

func waitForVideoAudio(view: *Film.Panel, count: u32)
{
    var attempts: u32
    while view.video.audioTrackCount() != count and attempts < 5000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    Swag.assert(view.video.audioTrackCount() == count)
}

func waitForVideoVoicePlaying(view: *Film.Panel)
{
    var attempts: u32
    while view.voice and not view.voice.isPlaying() and attempts < 5_000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    Swag.assert(view.voice != null and view.voice.isPlaying())
}

func videoAudioFixturePath()->String    => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/glint-aac-mjpeg.mp4")
func videoAvcFixturePath()->String      => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/ffmpeg-h264-baseline.mp4")
func videoMatroskaFixturePath()->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/ffmpeg-h264-two-aac.mkv")

// A same-stem sidecar is discovered, selected, and presented on the movie clock. Rendering
// preferences and manual synchronization are available from the same track menu.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("scope-video-subtitle-%.mp4", Guid64.random()))
    let folder   = unwrap Path.directoryName(fileName)
    let stem     = unwrap Path.fileNameWithoutExtension(fileName)
    let sidecar  = Path.combine(folder, Format.toString("%.fr.srt", stem))
    defer
    {
        discard catch File.delete(sidecar)
        discard catch File.delete(fileName)
    }

    expect File.writeAllBytes(sidecar, "1\n00:00:00,000 --> 00:00:00,400\nOpening caption\n\n2\n00:00:00,500 --> 00:00:00,900\nSecond caption\n")

    let savedSettings = Film.g_SubtitleSettings
    defer Film.g_SubtitleSettings = savedSettings
    Film.g_SubtitleSettings = {}

    let standalone = expect Subtitle.Track.loadOwned(sidecar)
    #assert(#typeof(standalone) == *Subtitle.Track)
    let standaloneText = standalone.cueContent(0)
    Swag.assert(standaloneText == "Opening caption")
    Subtitle.Track.destroy(standalone)

    var host: Testing.HeadlessHost
    host.setup(720, 420)
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 480, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    view.playing = false
    view.elapsed = 0

    view.finishSubtitles()
    view.refreshSubtitle()
    Swag.assert(view.subtitleOverlay.sidecars.count == 1 and view.subtitleSource == .Sidecar)
    Swag.assert(view.subtitleReady and view.subtitleChip.isLocallyVisible())
    let trackName    = Film.subtitleTrackName(0, view.subtitleOverlay.sidecars[0])
    let languageText = Format.toString(Film.texts().ui_SubtitleTrackLang, "fr")
    Swag.assert(Utf8.contains(languageText, "<p2> (fr)</p>"))
    Swag.assert(not Utf8.contains(RichString.plainText(trackName), "<p"))
    Swag.assert(view.subtitleText() == RichString.plainText(trackName))
    let opening = view.subtitleOverlay.sidecars[0].cueContent(0)
    Swag.assert(opening == "Opening caption")
    Swag.assert(view.subtitleOverlay.text == "Opening caption")
    view.seekSeconds(0.6)
    waitForVideoFrame(view)
    view.refreshSubtitle()
    Swag.assert(view.subtitleOverlay.text == "Second caption")

    Film.g_SubtitleSettings.delay = -0.5
    view.subtitleSettingsChanged()
    Swag.assert(view.subtitleOverlay.text == "Opening caption")

    // The options reach every subtitle setting: a style two pages deep, the delay stepped in
    // place, and the track.
    let strings = Film.texts()
    host.activateOptionRowWhenShown(strings.ui_OptionSubtitles)
    host.thenActivateOptionRow(strings.ui_SubtitleSize)
    host.thenActivateOptionRow(strings.ui_SubtitleSizeLarge)
    view.showOptions()
    Swag.assert(host.autoHandled)
    Swag.assert(Film.g_SubtitleSettings.size == .Large)

    host.activateOptionRowWhenShown(strings.ui_OptionSubtitles)
    host.thenActivateOptionRow(strings.ui_SubtitleDelay, step: 10)
    view.showOptions()
    Swag.assert(Math.isEqualEpsilon(Film.g_SubtitleSettings.delay, 0.5, 0.0001))
    host.activateOptionRowWhenShown(strings.ui_OptionSubtitles)
    host.thenActivateOptionRow(strings.ui_SubtitleDelayReset)
    host.thenActivateOptionRow(strings.ui_SubtitleOff)
    view.showOptions()
    Swag.assert(Film.g_SubtitleSettings.delay == 0)
    Swag.assert(view.subtitleSource == .Off and view.subtitleOverlay.text.isEmpty())
    Film.g_SubtitleSettings = {}
}

// Switching files retires the old decoder immediately, before deferred GUI deletion keeps its
// frame buffers alive while the replacement allocates its H.264 contexts.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)

    var index    = createViewerPluginRegistry()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    let fileName = videoAvcFixturePath()
    window.openFile(fileName, remember: false)
    completeViewerWindowClassification(&host, window)
    Swag.assert(window.currentView != null)
    var previous = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(previous)
    Swag.assert(previous.video.isOpen() and previous.playing)

    // Leave each decoder running before replacing it. A queue that grew on the decoder thread
    // through storage owned by the GUI allocator would surface, after several ordinary zaps, as
    // Memory.realloc(16, 8).
    for 8
    {
        for 12
        {
            Threading.Thread.sleep(1'ms)
            previous.updatePlayback()
        }

        window.openFile(fileName, remember: false)
        Swag.assert(window.currentView == previous)
        var attempts: u32
        while (window.outgoingView != previous or window.instances.isEmpty()) and attempts < 5_000
        {
            Threading.Thread.sleep(1'ms)
            host.pump()
            if window.startupTimer do
                host.fireTimer(window.startupTimer)
            attempts += 1
        }

        Swag.assert(window.outgoingView == previous and window.currentView == previous)
        Swag.assert(not previous.isPendingDestroy)
        let incoming = assume cast(*Film.Panel, window.instances[window.activeChoiceIndex].view)
        Swag.assert(incoming != previous)
        waitForVideoFrame(incoming)
        Swag.assert(incoming.playing)
        window.commitViewerTransition(incoming)
        Swag.assert(previous.isPendingDestroy)
        Swag.assert(window.currentView == incoming and window.outgoingView == null)
        previous = incoming
    }
}

#test
{
    let fileName = expect videoPreviewFile(Format.toString("scope-video-clock-%.mp4", Guid64.random()), 12)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)

    // Put every remaining picture in the queue before advancing the presentation clock. A
    // partially filled queue tests producer scheduling instead of the catch-up decision.
    view.playing = true
    view.clock.reset()
    view.decodeWake.signal()
    var attempts = 0
    var queued   = 0'u64
    while queued != 11 and attempts < 5000
    {
        scope
        {
            Sync.scopedLock(&view.queueLock)
            queued = view.ready.count
        }

        if queued != 11 do
            Threading.Thread.sleep(1'ms)
        attempts += 1
    }

    Swag.assert(queued == 11)

    // A late presentation drops every obsolete picture. Capping catch-up at four frames
    // would publish frame 4 instead of the frame the stopped clock requests.
    view.playing = true
    view.elapsed = view.frameSeconds(10)
    view.clock.reset()
    view.updatePlayback()
    view.playing = false
    Swag.assert(not view.clock.isRunning())
    Swag.assert(view.frameIndex == 10)
}

#test
{
    let fileName = expect videoPreviewFile(Format.toString("scope-video-%.mp4", Guid64.random()))
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    host.setReducedMotion(true)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.video.frameCount() == 4)
    Swag.assert(result.sidePanelButton != null and result.sidePanelHost != null)
    Swag.assert(not result.sidePanelHost.isLocallyVisible())
    result.sidePanelButton.setChecked(true)
    result.sidePanelButton.sigCheckedChanged.call(result.sidePanelButton)
    Swag.assert(result.sidePanelHost.isLocallyVisible())
    Swag.assert(Utf8.contains(view.information.text(), "Dimensions: 160 × 90 px"))
    Swag.assert(Utf8.contains(view.information.text(), "Frames: 4"))
    view.information.closeButton.sigPressed.call(view.information.closeButton)
    Swag.assert(not result.sidePanelHost.isLocallyVisible())
    Swag.assert(view.frameIndex == 0 and view.playing)
    Swag.assert(view.playButton.icon.index == cast(s32, ThemeIcons.Pause))
    view.togglePlayback()
    Swag.assert(not view.playing)

    var nextFrame = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Control}
    view.sendEvent(&nextFrame)
    waitForVideoFrame(view)
    Swag.assert(nextFrame.accepted and view.frameIndex == 1 and not view.playing)
    var previousFrame = KeyEvent{kind: .Pressed, key: .Left, modifiers: .Control}
    view.sendEvent(&previousFrame)
    waitForVideoFrame(view)
    Swag.assert(previousFrame.accepted and view.frameIndex == 0 and not view.playing)
    var previousAtStart = KeyEvent{kind: .Pressed, key: .Left, modifiers: .Control}
    view.sendEvent(&previousAtStart)
    Swag.assert(previousAtStart.accepted and view.frameIndex == 0)
    view.togglePlayback()
    let frameBeforePausedStep = view.frameIndex
    var nextWhilePlaying      = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Control}
    view.sendEvent(&nextWhilePlaying)
    waitForVideoFrame(view)
    Swag.assert(nextWhilePlaying.accepted and not view.playing and view.frameIndex == frameBeforePausedStep + 1)

    // A Motion JPEG stream has no planes to hand over, so the queue holds packed pictures.
    Swag.assert(not view.planar)
    Swag.assert(view.details.indexOf("160") != Swag.U64.Max)
    Swag.assert(view.details.indexOf("4 frames") != Swag.U64.Max)
    Swag.assert(view.details.indexOf("Swag CPU") != Swag.U64.Max)
    Swag.assert(view.timeText() == "0:00 / 0:01")

    view.seekFrame(2)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 2)
    var reading: ViewerReadingState
    reading.capture(&result, "video", "")
    view.seekFrame(0)
    waitForVideoFrame(view)
    reading.applySettings(&result)
    discard reading.restore(&result)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 2 and not view.playing)
    view.seekRelative(-10)
    Swag.assert(view.seekOverlay!.isLocallyVisible() and
                view.seekOverlay.direction == -1 and
                view.seekOverlay.text == "-10")
    Swag.assert(view.seekOverlay.presentationOffset == {} and view.seekOverlay.presentationScale == Math.Point{1, 1})
    Swag.assert(view.seekOverlay.position.vertCenter() > view.clientRect().vertCenter())
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 0)
    view.seekRelative(10)
    Swag.assert(view.seekOverlay.isLocallyVisible() and
                view.seekOverlay.direction == 1 and
                view.seekOverlay.text == "+10")
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 3)
    view.timeline.setValue(3)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 3)
    view.togglePlayback()
    Swag.assert(view.playing)
    view.togglePlayback()
    Swag.assert(not view.playing)
    view.stopPlayback()
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 0 and view.elapsed == 0)
}

// At rest nothing stands over the picture. A movement of the pointer brings the veils, a moment
// of stillness takes them away, and a pointer resting on them keeps them. A press on the
// timeline seeks there, and the chips open the page of the options they name.
#test
{
    let fileName = expect videoPreviewFile("viewer.video.veils.y4m")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1280, 720)
    var result = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands == null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    view.dockStyle = .Center
    host.root.applyLayout()
    if view.playing do
        view.togglePlayback()

    Swag.assert(not view.veilsShown and
                not view.topVeil.isLocallyVisible() and
                not view.bottomVeil.isLocallyVisible())
    host.moveMouse(view.localToSurface(Math.Point{640, 300}))
    Swag.assert(view.veilsShown and view.bottomVeil.isLocallyVisible() and view.topVeil.isLocallyVisible())
    Swag.assert(view.timeline.position.width == view.clientRect().width - 2 * Film.VeilInset + 16)

    // Still over the picture, the veils leave; resting on the controls, they stay.
    view.settleVeils(10_000)
    Swag.assert(not view.veilsShown and not view.bottomVeil.isLocallyVisible())

    // The first movement brings the veils back, the next one lands on their controls.
    host.moveMouse(view.playButton.surfaceRect().center())
    host.moveMouse(view.playButton.surfaceRect().center() + Math.Point{1, 0})
    Swag.assert(view.veilsShown and view.veilsHeld)
    view.settleVeils(10_000)
    Swag.assert(view.veilsShown)

    // A press on the timeline seeks to where it points.
    let timeline = view.timeline.surfaceRect()
    let trackX  = timeline.x + 8
    let trackWidth = timeline.width - 16
    host.click(Math.Point{trackX + trackWidth * 0.75, timeline.vertCenter()})
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 3 and view.timeText() == "0:00 / 0:01")

    // The keys move the film too: Space plays and pauses, the arrows seek and set the volume.
    view.setFocus()
    host.keyPress(.Space)
    Swag.assert(view.playing)
    host.keyPress(.Space)
    Swag.assert(not view.playing)
    host.keyPress(.Left)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 0)
    let volume = view.volume
    host.keyPress(.Down)
    Swag.assert(view.volume < volume)

    // At rest the lens offers what the film is watched with, and nothing it cannot do: this film
    // has neither subtitles nor a second sound track.
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Video")
    view.describeLens(&entries)
    Swag.assert(results.sections.count == 1 and results.sections[0]!.entries.count == 3)
    Swag.assert(results.sections[0]!.entries[0].title == appStrings().cmd_Play)
    Swag.assert(results.sections[0]!.entries[1].title == Film.texts().cmd_Speed)
    Swag.assert(results.sections[0]!.entries[2].title == appStrings().cmd_FullScreen)

    // The speed chip opens the speeds, the one in force checked.
    Swag.assert(view.speedChip.text() == "1×" and not view.audioChip.isLocallyVisible())
    var speeds: OptionSheet.Page
    view.describeSpeeds(&speeds)
    host.activateOptionRowWhenShown("1.5×")
    view.speedChip.sigPressed.call(view.speedChip)
    Swag.assert(view.playbackRate == 1.5 and view.speedChip.text() == "1.5×")
}

// The seek feedback is a Voltage mark with an ink keyline over the picture, which reads over a
// bright picture as over a dark one, and leaves on its own.
#test
{
    let fileName = expect videoPreviewFile("viewer.video.seek.y4m")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(720, 420)
    var result = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    view.dockStyle = .Center
    host.root.applyLayout()

    // A film without sound offers no sound track among its options, and its sound is off.
    var options: OptionSheet.Page
    view.describeOptions(&options)
    for row in options.rows do
        Swag.assert(row.label != Film.texts().ui_OptionAudio)
    Swag.assert(not view.muteButton.isEnabled())

    host.setReducedMotion(false)
    view.showSeekFeedback(10)
    Swag.assert(view.seekOverlay!.timer != null and view.seekOverlay.presentationOffset.x < 0)
    let overlayTimer = view.seekOverlay.timer
    host.fireTimer(overlayTimer)
    Swag.assert(not view.seekOverlay.isLocallyVisible() and view.seekOverlay.timer == null)

    host.theme.setLight()
    host.notify(.ThemeChanged)
    view.showSeekFeedback(-10)
    Swag.assert(view.seekOverlay.backgroundStyle == .Transparent)
    Swag.assert(Voltage.contrastRatio(Ink) >= 4.5)
    host.fireTimer(view.seekOverlay.timer)
}

// The film in the window, against `scope.video`: the picture alone at rest, and under the
// pointer the top veil with the title and its facts, the bottom veil with the timeline, the
// time under the pointer, the play button, the time in mono and the chips.
#[Swag.TestTag("golden")]
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window = framedViewerWindow(&host, videoMatroskaFixturePath(), light)
        let view   = assume cast(*Film.Panel, window.instances[window.activeChoiceIndex].view)

        // The film writes its title in the top veil, so the strip leaves it out.
        Swag.assert(host.surfaceWnd.titleHidden)
        waitForVideoFrame(view)
        waitForVideoAudio(view, 2)
        if view.playing do
            view.togglePlayback()
        view.seekFrame(5)
        waitForVideoFrame(view)
        view.refreshTime()
        view.timeline.setValueWithoutGesture(cast(f32, view.frameSeconds(view.frameIndex)))
        host.settleAnimations(window, 4)

        var rest = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&rest, light ? "viewer.video.paper" : "viewer.video.ink")

        // The first movement brings the veils, the next one reads a time on the timeline.
        let timeline = view.timeline.surfaceRect()
        let trackX = timeline.x + 8
        let trackWidth = timeline.width - 16
        host.moveMouse(Math.Point{trackX + trackWidth * 0.6, timeline.vertCenter()})
        host.moveMouse(Math.Point{trackX + trackWidth * 0.62, timeline.vertCenter()})
        host.settleAnimations(window, 4)
        var hover = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&hover, light ? "viewer.video.hover.paper" : "viewer.video.hover.ink")
    }
}

// RV40 reaches the normal planar viewer and seeks across B pictures and open groups.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let fileName = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/rv40-legacy-clock.mkv")
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.planar and not view.hasFailure)
    Swag.assert(view.video.width() == 96 and view.video.height() == 64)
    for index in [7'u64, 3, 8, 0]
    {
        view.repositionTo(index)
        view.decodeWake.signal()
        waitForVideoFrame(view)
        Swag.assert(view.frameIndex == index and not view.hasFailure and view.planar)
    }
}

func captureVideoFailure(wnd: *Wnd, reason: string)
{
    let captured = cast(*String, unwrap wnd.userData)
    captured[] = reason
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-video-", ".y4m")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a video")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: &host.root, services: {reportFailure: &captureVideoFailure})
    Swag.assert(result.view != null and result.commands == null)
    let view = assume cast(*Film.Panel, result.view)
    var failure: String
    view.userData = &failure
    waitForVideoFrame(view)
    Swag.assert(not view.openFailure.isEmpty() and not view.video.isOpen())
    Swag.assert(failure == view.openFailure)
}

#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let fileName = videoAudioFixturePath()
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.muteButton.icon.isValid() and
                view.muteButton.flags.has(.Toggle) and
                view.muteButton.isEnabled())
    Swag.assert(view.audio != null and view.voice != null and view.video.audioTrackCount() == 1)
    Swag.assert(view.playing and view.voice.isPlaying())
    view.setVolume(0.35)
    Swag.assert(Math.isEqualEpsilon(expect view.voice.volume(), 0.35, 0.001))
    Swag.assert(view.volume == 0.35)
    view.setMuted(true)
    Swag.assert(view.muted and view.muteButton.isChecked)
    Swag.assert(Math.isEqualEpsilon(expect view.voice.volume(), 0, 0.001))
    view.setMuted(false)
    Swag.assert(Math.isEqualEpsilon(expect view.voice.volume(), 0.35, 0.001))

    holdVideoProducer(view)
    view.timeline.setValue(cast(f32, view.frameSeconds(5)))
    Swag.assert(view.awaitingFrame and view.resumeAudioAfterSeek)
    releaseVideoProducer(view)
    waitForVideoFrame(view)
    Swag.assert(not view.resumeAudioAfterSeek and view.voice.isPlaying())
    Swag.assert(view.voice.playbackSampleFrame() == cast(u64, Math.round(view.video.frameTimestamp(5) * 44_100.0)))
    view.togglePlayback()
    Swag.assert(not view.playing and not view.voice.isPlaying())
    view.stopPlayback()
    Swag.assert(view.voice.playbackSampleFrame() == 0)
}

// The playback speed menu changes how fast the movie plays: an adjusted rate scales the silent
// clock and the sound together, and stays declared by the host summary until reset.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 480, 36})
    let fileName = videoAudioFixturePath()
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.speedChip.text() == "1×")
    Swag.assert(view.audio != null and view.voice != null)

    // The speed chip says the rate in force, but not while its own page is open over it.
    view.optionsOpen = true
    view.setPlaybackRate(1.5)
    Swag.assert(view.speedChip.text() == "1×")
    view.optionsOpen = false
    view.setPlaybackRate(1.25)
    Swag.assert(view.speedChip.text() == "1.25×")
    view.setPlaybackRate(1)
    Swag.assert(view.speedChip.text() == "1×")

    // The speed entry rescales the voice with the clock, and the summary declares the rate.
    host.activateOptionRowWhenShown(Film.texts().ui_OptionSpeed)
    host.thenActivateOptionRow("2×")
    view.showOptions()
    Swag.assert(view.playbackRate == 2)
    Swag.assert(view.speedChip.text() == "2×")
    Swag.assert(Math.isEqualEpsilon(expect view.voice.frequencyRatio(), 2, 0.001))
    Swag.assert(view.details.indexOf("2×") != Swag.U64.Max)
    view.setPlaybackRate(1)
    Swag.assert(view.playbackRate == 1 and view.details.indexOf("2×") == Swag.U64.Max)
    Swag.assert(Math.isEqualEpsilon(expect view.voice.frequencyRatio(), 1, 0.001))
    var faster = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Shift}
    view.sendEvent(&faster)
    Swag.assert(faster.accepted and view.playbackRate == 1.25)
    Swag.assert(Math.isEqualEpsilon(expect view.voice.frequencyRatio(), 1.25, 0.001))
    var slower = KeyEvent{kind: .Pressed, key: .Left, modifiers: .Shift}
    view.sendEvent(&slower)
    Swag.assert(slower.accepted and view.playbackRate == 1)
    view.setPlaybackRate(2)
    var fastest = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Shift}
    view.sendEvent(&fastest)
    Swag.assert(fastest.accepted and view.playbackRate == 2)
}

// The host's answer to a movie that has been played through is what the transport does with
// it: a replay restarts from the first picture without leaving the playing state, and any other
// answer parks it on the last picture.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("scope-video-loop-%.mp4", Guid64.random()))
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 480, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands, services: {reportFinished: &answerVideoEnd})
    Swag.assert(result.view != null)
    let view   = assume cast(*Film.Panel, result.view)
    var answer = Viewer.Continuation.Replay
    view.userData = &answer
    waitForVideoFrame(view)
    Swag.assert(view.playing and view.voice == null)

    playVideoThrough(view)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 0 and view.playing)

    // Told that the next file is on its way, the transport parks on the last picture.
    answer = .Next
    playVideoThrough(view)
    Swag.assert(not view.playing and view.frameIndex == view.video.frameCount() - 1)
}

// Played through with the folder mode on, a movie hands over to the next movie of its folder,
// past the notes stored beside it, and the last one hands over to the first. The movie that
// arrives starts playing on its own, which is what makes the folder a playlist.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope_chain_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    discard expect videoPreviewFileAt(Path.combine(folder, "clip1.mp4"))
    discard expect videoPreviewFileAt(Path.combine(folder, "clip2.mp4"))
    expect File.writeAllBytes(Path.combine(folder, "notes.txt"), "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(Path.combine(folder, "clip1.mp4"), remember: false)
    completeViewerWindowClassification(&host, window)
    window.setPlayMode(.Folder)

    for expected in ["clip2.mp4", "clip1.mp4"]
    {
        let view = assume cast(*Film.Panel, window.instances[window.activeChoiceIndex].view)
        waitForVideoFrame(view)
        Swag.assert(window.currentView == view and view.playing)
        Swag.assert(view.speedChip.parent == view.bottomVeil)

        // The clip is shorter than the walk through the sheet, so it waits while the reader chooses.
        view.togglePlayback()
        host.activateOptionRowWhenShown(appStrings().ui_PlayMode)
        host.thenActivateOptionRow(appStrings().ui_PlayShuffle)
        host.thenActivateOptionRow(Film.texts().ui_OptionSpeed)
        host.thenActivateOptionRow("2×")
        view.showOptions()
        view.togglePlayback()
        Swag.assert(view.playbackRate == 2 and window.playMode == .Shuffle)
        view.setPlaybackRate(1)
        window.setPlayMode(.Folder)

        var page: OptionSheet.Page
        view.describeOptions(&page)
        Swag.assert(page.rows[0].label == appStrings().ui_PlayMode and page.rows[0].value == appStrings().ui_PlayFolder)

        playVideoThrough(view)
        Swag.assert(not view.playing and Path.fileName(window.pendingFile) == expected)
        completeVideoHandover(&host, window)
        Swag.assert(Path.fileName(window.currentFile) == expected)
    }
}

// Full-screen chrome is presentation-only: resizing and revealing either bar preserves the
// active voice and the transport state.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(videoAudioFixturePath(), remember: false)
    completeViewerWindowClassification(&host, window)
    let view = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)

    // A click on the bottom timeline keeps the stale picture until the decoder publishes the
    // requested frame, and brings the central wait overlay over it only once the decode has
    // taken long enough to be a wait.
    holdVideoProducer(view)
    view.timeline.setValue(cast(f32, view.frameSeconds(5)))
    Swag.assert(view.awaitingFrame and
                not window.loadingOverlay.isLocallyVisible() and
                window.loadingWantedSince != 0)
    expireViewerLoadingDelay(window)
    Swag.assert(window.loadingOverlay.isLocallyVisible())
    releaseVideoProducer(view)
    waitForVideoFrame(view)
    window.updateLoadingIndicator()
    Swag.assert(window.loadingOverlay.isLocallyVisible())
    expireViewerLoadingLinger(window)
    Swag.assert(not window.loadingOverlay.isLocallyVisible())

    let voice = unwrap view.voice

    window.setFullScreen(true)
    window.notePointer({10, 1})
    window.notePointer(Math.Point{10, window.clientRect().height - 1})
    window.setFullScreen(false)

    Swag.assert(view.playing and view.voice == voice and voice.isPlaying())
}

// Choosing another viewer for a playing film pauses it, sound included, and coming back finds it
// paused where it was rather than playing on behind the other viewer.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(videoAudioFixturePath(), remember: false)
    completeViewerWindowClassification(&host, window)
    let view = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    Swag.assert(view.playing and (unwrap view.voice).isPlaying())

    var binary = Swag.U32.Max
    for choice, choiceIndex in window.choices where window.index.plugins[choice.pluginIndex].key == "binary" do
        binary = cast(u32, choiceIndex)
    let film = window.activeChoiceIndex
    Swag.assert(binary != Swag.U32.Max and window.activateChoice(binary))
    Swag.assert(window.currentView != view and not view.playing)
    Swag.assert(view.voice != null and not view.voice.isPlaying())

    // The binary report finishes before the film is chosen again: a viewer still loading is
    // retired rather than kept, and the host waits for that.
    let report = &window.instances[binary]
    for 4_096 where report.isLoading and report.isLoading()
    {
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
    }

    Swag.assert(window.activateChoice(film) and window.currentView == view)
    Swag.assert(not view.playing and not view.voice.isPlaying())
}

// Playback shortcuts belong to the active media viewer, not to whichever toolbar or panel
// happens to own focus. Held-key repeats are consumed without toggling transport again.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(videoAudioFixturePath(), remember: false)
    completeViewerWindowClassification(&host, window)
    let view = assume cast(*Film.Panel, window.currentView)
    Swag.assert(not window.loadingOverlay.isLocallyVisible() and window.loadingWantedSince != 0)
    expireViewerLoadingDelay(window)
    Swag.assert(window.loadingOverlay.isLocallyVisible())
    waitForVideoFrame(view)
    window.updateLoadingIndicator()
    expireViewerLoadingLinger(window)
    Swag.assert(not window.loadingOverlay.isLocallyVisible())

    // Start the shortcut scenario from a deliberate pause; opening itself already started play.
    view.togglePlayback()
    Swag.assert(not view.playing and not view.voice!.isPlaying())

    // A control of the window outside the viewer keeps the keyboard while the keys play.
    let outside = EditBox.create(window, "", {0, 0, 120, 32})
    outside.setFocus()
    var press = KeyEvent{kind: .Pressed, key: .Space}
    Swag.assert(window.hookOnChildEvent!(outside, &press))
    Swag.assert(view.playing and view.voice!.isPlaying() and outside.hasFocus())
    Swag.assert(window.hookOnChildEvent(outside, &press))
    Swag.assert(view.playing and view.voice!.isPlaying())

    var release = KeyEvent{kind: .Released, key: .Space}
    Swag.assert(window.hookOnChildEvent(outside, &release))
    Swag.assert(window.hookOnChildEvent(outside, &press))
    Swag.assert(not view.playing and not view.voice!.isPlaying() and outside.hasFocus())
    Swag.assert(window.hookOnChildEvent(outside, &release))

    view.setPlaybackRate(1)
    var faster = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Shift}
    Swag.assert(window.hookOnChildEvent(outside, &faster))
    Swag.assert(view.playbackRate == 1.25 and outside.hasFocus())
    Swag.assert(Math.isEqualEpsilon(expect view.voice!.frequencyRatio(), 1.25, 0.001))
    let frameBeforeStep = view.frameIndex
    var nextFrame       = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Control}
    Swag.assert(window.hookOnChildEvent(outside, &nextFrame))
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == frameBeforeStep + 1 and not view.playing and outside.hasFocus())
}

// A Matroska file carrying several sound tracks exposes them on a chip. Changing it creates and
// positions the replacement voice before releasing the previous one, so transport, volume, and
// mute state survive the handoff.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(ViewerWindow.MinWidth, 450)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    with let commands = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    let path   = videoMatroskaFixturePath()
    var result = openTestViewer(Film.viewerPlugin(), &host.root, path, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.timeline.isEnabled())
    waitForVideoAudio(view, 2)

    Swag.assert(view.video.audioTrackCount() == 2)
    Swag.assert(Utf8.contains(view.information.text(), "Name: Primary"))
    Swag.assert(Utf8.contains(view.information.text(), "Name: Alternate"))
    Swag.assert(Utf8.contains(view.information.text(), "44100 Hz"))
    Swag.assert(view.audioTrackIndex == 0)
    Swag.assert(Film.audioTrackName(0, unwrap view.video.audioTrack(0)) == "Primary")
    Swag.assert(Film.audioTrackName(1, unwrap view.video.audioTrack(1)) == "Alternate")
    Swag.assert(Film.audioDetailsText(unwrap view.video.audioTrack(1)) == "AAC-LC · 2 ch · 44.1 kHz")
    Swag.assert(Format.toString(Film.texts().ui_AudioTrackLang, "fre") == "<p2> (fre)</p>")
    Swag.assert(view.muteButton.isEnabled() and
                view.audioChip.isLocallyVisible() and
                view.audioChip.text() == "Primary 2.0")
    Swag.assert(view.details.indexOf("AAC-LC") != Swag.U64.Max and view.details.indexOf("2 ch") != Swag.U64.Max)
    Swag.assert(Film.audioEncodingText(.Ac3) == "AC-3" and Film.audioEncodingText(.Eac3) == "E-AC-3")
    Swag.assert(Film.audioEncodingText(.Dts) == "DTS" and
                Film.audioEncodingText(.Flac) == "FLAC" and
                Film.audioEncodingText(.Mp3) == "MP3")
    Swag.assert(Film.audioEncodingText(.Vorbis) == "Vorbis" and
                Film.audioEncodingText(.Opus) == "Opus" and
                Film.audioEncodingText(.AdpcmIma) == "IMA ADPCM")
    view.setVolume(0.4)
    view.setMuted(true)

    // This fixture lasts only 800 ms. Inspect the popup while paused, then exercise the same
    // handoff while playing at an explicitly held position, independent of menu/render latency.
    view.togglePlayback()
    view.seekFrame(5)
    waitForVideoFrame(view)
    Swag.assert(not view.playing and not view.voice!.isPlaying())
    let previousVoice = unwrap view.voice

    host.activateOptionRowWhenShown(Film.texts().ui_OptionAudio)
    host.thenActivateOptionRow("Alternate")
    view.showOptions()
    Swag.assert(view.audioTrackIndex == 1 and view.audio == view.video.audioTrack(1))
    Swag.assert(view.voice != null and view.voice != previousVoice)
    Swag.assert(not view.playing and not view.voice.isPlaying())
    Swag.assert(view.muted and Math.isEqualEpsilon(expect view.voice.volume(), 0, 0.001))
    let switchedSample = view.voice.playbackSampleFrame()
    let seekSample     = cast(u64, Math.round(view.video.frameTimestamp(5) * 44_100.0))
    let currentSample  = Film.soundSample(unwrap view.audio, view.currentSeconds())
    let sampleDrift    = switchedSample > currentSample ? switchedSample - currentSample : currentSample - switchedSample
    Swag.assert(switchedSample >= seekSample and sampleDrift < 4_410)

    view.setMuted(false)
    Swag.assert(Math.isEqualEpsilon(expect view.voice.volume(), 0.4, 0.001))
    view.togglePlayback()
    Swag.assert(view.playing and view.voice.isPlaying())
    view.clock.reset()
    expect view.selectAudioTrack(0)
    waitForVideoVoicePlaying(view)
    Swag.assert(view.playing and view.audioTrackIndex == 0)
    view.clock.reset()
    expect view.selectAudioTrack(1)
    waitForVideoVoicePlaying(view)
    Swag.assert(view.playing and view.audioTrackIndex == 1)
    view.togglePlayback()
    view.seekFrame(5)
    waitForVideoFrame(view)
    Swag.assert(Math.isEqualEpsilon(view.timeline.value(), cast(f32, view.frameSeconds(5)), 0.001))

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.audioChip.toolTip == "Piste audio")
    Swag.assert(Film.texts().ui_OptionAudio == "Piste audio")
    Swag.assert(Film.audioDetailsText(unwrap view.video.audioTrack(1)).indexOf("can.") != Swag.U64.Max)
    Swag.assert(view.details.indexOf("2 can.") != Swag.U64.Max)
}

// A progressive sound prefix must not become the master clock for a seek beyond that prefix.
// It stays paused until a longer index arrives, while the picture timeline remains at the point
// the user requested instead of snapping back to the last indexed sound sample.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    let fileName = expect videoPreviewFile(Format.toString("scope-video-audio-range-%.mp4", Guid64.random()), 12)
    defer discard catch File.delete(fileName)
    let soundPath = Gui.Testing.tempFilePath("scope-video-audio-range-", ".pcm")
    defer discard catch File.delete(soundPath)
    var pcm: Array'u8
    pcm.resize(200)
    expect File.writeAllBytes(soundPath, pcm.toSlice())
    let packets: [1] SoundPacket = [SoundPacket{0, 200, 100}]
    var sounds:  ArrayPtr'SoundFile
    let sound = sounds.allocate()
    sound[] = expect SoundFile.openPcmPacketStream(soundPath, .Pcm16, 100, 1, packets)
    sounds.add(sound)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)

    view.audio   = sound
    view.voice   = expect Voice.create(sound)
    view.playing = true
    view.clock.restart()
    view.seekFrame(8)
    waitForVideoFrame(view)
    Swag.assert(view.audioRangePending and view.resumeAudioAfterSeek and not view.voice.isPlaying())
    Swag.assert(view.currentSeconds() >= 1.9 and view.voice.playbackSampleFrame() == 0)
    view.followAudioClock()
    Swag.assert(view.currentSeconds() >= 1.9)

    // Once the progressive index reaches the target, the deferred seek is still remembered and
    // positions the replacement voice before sound resumes.
    let longerPath = Gui.Testing.tempFilePath("scope-video-audio-range-long-", ".pcm")
    defer discard catch File.delete(longerPath)
    pcm.resize(800)
    expect File.writeAllBytes(longerPath, pcm.toSlice())
    const LongerPackets: [1] SoundPacket = [SoundPacket{0, 800, 400}]
    let longerSound = sounds.allocate()
    longerSound[] = expect SoundFile.openPcmPacketStream(longerPath, .Pcm16, 100, 1, LongerPackets)
    sounds.add(longerSound)
    view.voice.destroy()
    view.audio = longerSound
    view.voice = expect Voice.create(longerSound)
    view.resumeAudio()
    Swag.assert(not view.audioRangePending and not view.resumeAudioAfterSeek and view.voice.isPlaying())
    Swag.assert(view.voice.playbackSampleFrame() >= 200)
    view.voice.destroy()
    view.voice = null
    view.audio = null
}

// A Matroska seek window carries a media-timeline origin. The viewer maps that absolute movie
// position to the window's local sample frames instead of treating the window as time zero.
#test
{
    let soundPath = Gui.Testing.tempFilePath("scope-video-audio-window-", ".ac3")
    defer discard catch File.delete(soundPath)
    expect File.writeAllBytes(soundPath, [0x0B'u8, 0x77, 0, 0, 0, 0, 0])
    const Packets: [1] SoundPacket = [SoundPacket{0, 7, 1536}]
    var config: Array'u8
    var sound = expect SoundFile.openPacketStream(soundPath, .Ac3, 48_000, 2, 1536, Packets, config.toSlice(), {timelineStartSeconds: 100})

    Swag.assert(not Film.soundCovers(&sound, 99.99))
    Swag.assert(Film.soundCovers(&sound, 100.01))
    Swag.assert(Film.soundSample(&sound, 100.01) == 480)
    Swag.assert(not Film.soundCovers(&sound, 101))
}

// An output device that never consumes what it was given reports the same position for ever.
// Presentation follows the sound, but it may not stop when the sound does: the no-sound backend
// consumes nothing here, and the picture still has to advance.
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let fileName = videoAudioFixturePath()
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.voice != null)

    let stalled = view.voice.playbackSampleFrame()
    Swag.assert(view.playing)

    var attempts = 0
    while view.frameIndex == 0 and attempts < 4000
    {
        Threading.Thread.sleep(1'ms)
        view.updatePlayback()
        attempts += 1
    }

    Swag.assert(view.voice.playbackSampleFrame() == stalled)
    Swag.assert(view.frameIndex != 0)
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

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let fileName = videoAvcFixturePath()
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands, services: {reportLoadingChanged: &countVideoLoadingChange})
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    var counters: ArrayPtr'u32
    let loadingChanges = counters.allocate()
    counters.add(loadingChanges)
    view.userData = loadingChanges
    waitForVideoFrame(view)
    loadingChanges[] = 0

    Swag.assert(view.planar)
    Swag.assert(view.video.width() == 64 and view.video.height() == 48)
    Swag.assert(view.frameIndex == 0 and not view.hasFailure)
    Swag.assert(result.isLoading != null and not result.isLoading())

    // A viewer reports every outstanding visible picture, not only its first one. The application
    // can therefore cover a stale frame while this exact seek reconstructs its target.
    view.repositionTo(12)
    Swag.assert(result.isLoading())
    Swag.assert(loadingChanges[] == 1)
    view.decodeWake.signal()
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 12 and not view.hasFailure)
    Swag.assert(not result.isLoading())
    Swag.assert(loadingChanges[] == 2)
    Swag.assert(view.planar)
    view.userData = null
}

// The run-ahead queue stays a FIFO as pictures are taken from it.
//
// Taking the front with an unstable removal would put the newest picture there instead, and the
// ones it steps over would never be taken at all: the queue would report itself full while the
// run-ahead it exists for shrinks to two pictures, so any decode longer than one frame period
// reaches the screen as a stall. Playback would still look sequential, which is why this asserts
// the order rather than what is shown.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("scope-video-queue-%.mp4", Guid64.random()), 40)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 0)

    view.togglePlayback()
    Swag.assert(not view.playing)

    // A paused viewer decodes only the picture it is parked on, so let the producer run and wait
    // until it has filled every slot, which is also when it stops touching the queue.
    view.playing = true
    view.clock.reset()
    view.decodeWake.signal()
    var attempts = 0
    while view.ready.count < cast(u64, view.slotCount) and attempts < 5000
    {
        Threading.Thread.sleep(1'ms)
        attempts += 1
    }

    Swag.assert(view.ready.count == cast(u64, view.slotCount))

    for step in 1 to 5
    {
        view.elapsed = view.frameSeconds(step)
        view.clock.reset()
        Swag.assert(view.publishHead(step, true))
        Swag.assert(view.frameIndex == step)

        // Everything still queued follows what is on screen, in order and without a hole.
        Sync.scopedLock(&view.queueLock)
        var expected = view.frameIndex
        for slot in view.ready
        {
            expected += 1
            Swag.assert(view.slots[cast(u64, slot)].index == expected)
        }
    }
}

// Decoded run-ahead is sized by bytes: ordinary video keeps useful depth, while 4K pictures do
// not multiply into a triple-digit-megabyte queue. Seeking never waits for more slots than exist.
#test
{
    Swag.assert(Film.prefetchSlotCount(1920, 1080, true) == 12)
    Swag.assert(Film.prefetchSlotCount(3840, 2160, true) == 5)
    Swag.assert(Film.prefetchSlotCount(3840, 2160, false) == 2)
    Swag.assert(Film.rebufferPictureCount(2) == 2)
    Swag.assert(Film.rebufferPictureCount(8) == 4)
}

// Falling behind jumps to a clean sync picture. The wait overlay remains visible until that
// picture is available, so a decoder below playback speed reports its actual state.
#test
{
    let fileName = expect videoPreviewFile(Format.toString("scope-video-resync-%.mp4", Guid64.random()), 40)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    var result   = openTestViewer(Film.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.assert(result.view != null and result.isLoading != null and result.needsLoadingOverlay != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 0)

    holdVideoProducer(view)
    view.playing = true
    view.elapsed = view.frameSeconds(12)
    view.clock.reset()
    view.updatePlayback()

    Swag.assert(view.awaitingFrame and result.isLoading())
    Swag.assert(result.needsLoadingOverlay())
    releaseVideoProducer(view)
    waitForVideoFrame(view)
    Swag.assert(view.frameIndex == 12)
}

// Bright, middle, and dark bands: the pictures subtitle text has to stay readable over.
struct SubtitleBackdropProbe
{
    using wnd: Wnd
}

impl IWnd for SubtitleBackdropProbe
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rect    = .clientRect()
        let band    = Math.floor(rect.width / 3)
        painter.fillRect(0, 0, band, rect.height, Color.fromArgb(0xFFF2EFE6))
        painter.fillRect(band, 0, band, rect.height, Color.fromArgb(0xFF8A8F96))
        painter.fillRect(2 * band, 0, rect.width - 2 * band, rect.height, Color.fromArgb(0xFF101418))
    }
}

func assertVideoTimelineEndpoints(light: bool, golden: string)
{
    var host: Testing.HeadlessHost
    host.setup(420, 90)
    host.root.backgroundStyle = .Application
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)

    let start = Wnd.create'Film.VideoTimeline(&host.root, {24, 12, 372, 24})
    let end   = Wnd.create'Film.VideoTimeline(&host.root, {24, 54, 372, 24})
    start.setBounds(0, 100, 0)
    end.setBounds(0, 100, 0)
    start.setValueWithoutGesture(0)
    end.setValueWithoutGesture(100)
    let room = start.clientRect()
    Swag.assert(start.positionOf(0) - room.x >= 7.99)
    Swag.assert(room.right() - end.positionOf(100) >= 7.99)
    host.root.applyLayout()

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, golden)
}

// The playhead and its outline stay whole when the track is at its first or last frame.
#[Swag.TestTag("golden")]
#test
{
    assertVideoTimelineEndpoints(false, "viewer.video.timeline.endpoints.encre")
    assertVideoTimelineEndpoints(true, "viewer.video.timeline.endpoints.paper")
}

func assertSubtitleEffect(effect: Film.SubtitleEffect, size: Film.SubtitleSize, dpiScale: f32, golden: string)
{
    let savedSettings = Film.g_SubtitleSettings
    defer Film.g_SubtitleSettings = savedSettings
    Film.g_SubtitleSettings        = {}
    Film.g_SubtitleSettings.effect = effect
    Film.g_SubtitleSettings.size   = size

    var host: Testing.HeadlessHost
    host.setup(900, 240, dpiScale)
    let backdrop = Wnd.create'SubtitleBackdropProbe(&host.root)
    backdrop.dockStyle = .Center
    let overlay = Film.SubtitleOverlay.create(backdrop)
    overlay.setSubtitle("Vous ne passerez pas, dit Gandalf.\nTout le monde descend, Jérôme !")
    host.root.applyLayout()

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, golden)
}

// Every readability effect over every kind of picture. The outline and the shadow keep their
// proportions from the normal size to the largest one on a high-density screen, and the
// backdrop of two lines is one shape, with no darker band where the lines meet.
#[Swag.TestTag("golden")]
#test
{
    assertSubtitleEffect(.Outline, .Normal, 1, "viewer.video.subtitle.outline")
    assertSubtitleEffect(.Shadow, .Normal, 1, "viewer.video.subtitle.shadow")
    assertSubtitleEffect(.Background, .Normal, 1, "viewer.video.subtitle.background")
    assertSubtitleEffect(.None, .Normal, 1, "viewer.video.subtitle.none")
    assertSubtitleEffect(.Outline, .VeryLarge, 1.5, "viewer.video.subtitle.outline.large.hidpi")
    assertSubtitleEffect(.Shadow, .VeryLarge, 1.5, "viewer.video.subtitle.shadow.large.hidpi")
    assertSubtitleEffect(.Background, .VeryLarge, 1.5, "viewer.video.subtitle.background.large.hidpi")
}

// The options of a film gather the play mode, the speed, the sound track and the subtitles, each
// with the value in force, and the page of a setting lists its choices with the one in force
// checked. The sheet stands on the speed chip of the bottom veil.
#[Swag.TestTag("golden")]
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(ViewerWindow.MinWidth, 450)
    host.setReducedMotion(true)
    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    with let commands = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    var result = openTestViewer(Film.viewerPlugin(), &host.root, videoMatroskaFixturePath(), commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    waitForVideoAudio(view, 2)
    if view.playing do
        view.togglePlayback()
    view.seekFrame(5)
    waitForVideoFrame(view)
    view.setPlaybackRate(1.5)

    view.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var rendered: u32
    host.app.sigFrame += func|host = &host, rendered = &rendered|(_)
    {
        let sheet = host.capturedOptionSheet()
        if not sheet or rendered[] == 2 do
            return
        host.finishAnimations()

        if rendered[] == 0
        {
            Swag.assert(sheet.page.rows.count == 4)
            Swag.assert(sheet.page.rows[1].value == "1.5×" and sheet.page.rows[2].value == "Primary")
            var first = host.render()
            Pixel.Testing.assertImageGolden(&first, "viewer.video.options")
            Swag.assert(sheet.activateRow(Film.texts().ui_OptionAudio))
            host.finishAnimations()
        }
        else
        {
            Swag.assert(sheet.page.rows[0].checked and sheet.page.rows[1].detail == "AAC-LC · 2 ch · 44.1 kHz")
            var tracks = host.render()
            Pixel.Testing.assertImageGolden(&tracks, "viewer.video.options.audio")
            sheet.close()
        }

        rendered[] += 1
    }

    view.showOptions()
    host.app.sigFrame.clear()
    Swag.assert(rendered == 2)
}

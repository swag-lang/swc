#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel, Video, Audio

// The output probe must service WASAPI independently of the editor's picture decoding.
#[Swag.NoCopy]
struct WebCaptureOutputProbe
{
    worker: Threading.Thread
    ready:  Sync.Event
    mutex:  Swag.Mutex
    error:  Swag.Error
}

impl WebCaptureOutputProbe
{
    mtd start(queue: *CaptureQueue) fail
    {
        .ready.init(false)
        let collect = func|probe = me, queue|(thread: const *Threading.Thread)
        {
            var signaled = false
            defer if not signaled do
                probe.ready.signal()
            catch
            {
                var index: Win32.DWORD
                let name = Utf16.toZeroTerminated("Audio")
                let task = try Win32.AvSetMmThreadCharacteristicsW(name.buffer, &index)
                defer discard catch Win32.AvRevertMmThreadCharacteristics(task)
                var source = try CaptureOutputLoopback.openDefault(queue)
                defer source.close()
                probe.ready.signal()
                signaled = true
                while not thread.requestEnd.isRaised() do
                    discard try source.pump(5)
                discard try source.pump()
            }
            {
                probe.mutex.lock()
                defer probe.mutex.unlock()
                probe.error.capture(Swag.err)
            }
        }

        try .worker.init(collect)
        expect .worker.start()
        .ready.wait()
        try .check()
    }

    mtd check() fail
    {
        .mutex.lock()
        defer .mutex.unlock()
        try .error.raise()
    }

    mtd close()
    {
        if .worker.isValid()
        {
            .worker.safeForceEnd()
            .worker.wait()
        }
    }

    mtd opDrop() => .close()
}

// Measure the browser's distinctive tone, rather than accepting an arbitrary nonempty track.
struct WebCaptureTone
{
    frames:       u64
    power, real, imaginary, tonePower: f64
    windowFrames: u32
}

impl WebCaptureTone
{
    mtd add(samples: const [..] s16, channels, rate: u32, offset: u64)
    {
        for frame in samples.count / channels
        {
            let sample = cast(f64, samples[frame * channels])
            let phase  = Math.ConstF64.TwoPi * 440 * (offset + frame) / rate
            .power        += sample * sample
            .real         += sample * Math.cos(phase)
            .imaginary    += sample * Math.sin(phase)
            .frames       += 1
            .windowFrames += 1

            // A looping browser clip can reset its tone phase. Measure energy in 100 ms
            // windows so a phase discontinuity cannot cancel several seconds of valid sound.
            if .windowFrames == rate / 10
            {
                .tonePower        += 2 * (.real * .real + .imaginary * .imaginary) / .windowFrames
                .real, .imaginary = 0
                .windowFrames     = 0
            }
        }
    }

    mtd const rms()->f64 => .frames ? Math.sqrt(.power / .frames) : 0

    mtd const toneFraction()->f64
    {
        let tail = .windowFrames ? 2 * (.real * .real + .imaginary * .imaginary) / .windowFrames : 0
        return .power ? (.tonePower + tail) / .power : 0
    }
}

private func webCaptureQuality()->VideoQuality
{
    let quality = Env.variable("SWAG_CAPTURE_WEB_QUALITY")
    if quality == "balanced" do
        return .Balanced
    if quality == "compact" do
        return .Compact
    if quality == "maximum" do
        return .Maximum
    return .Balanced
}

// tools/capture-web.py supplies a real looping HTML video and its system audio in an isolated
// browser. Select its area, record with the production HUD, reopen, and play through XAudio2.
// A second WASAPI recording verifies editor output after the browser has been silenced.
#[Swag.TestTag("integration.capture.web")]
#test
{
    Swag.require(Env.hasArgument("swag.audio.native-output=true"),
                 "launch this device integration with tools/capture-web.py")
    Swag.require(Env.hasArgument("swag.capture.native-screen=true"),
                 "this integration requires actual desktop pixels")
    let evidence = Env.sandboxRoot()
    let browser  = Win32.FindWindowA(null, "Swag Capture Web AV Probe".buffer)
    Swag.require(browser != null, "the owned browser fixture window is missing")
    var bounds: Win32.RECT
    Swag.require(Win32.GetWindowRect(browser, &bounds))

    // Use the native window origin rather than the browser's reported screen position;
    // the fixture supplies its content insets, in physical pixels.
    let x         = bounds.left + expect StrConv.toF32(Env.variable("SWAG_CAPTURE_WEB_INSET_X"))
    let y         = bounds.top + expect StrConv.toF32(Env.variable("SWAG_CAPTURE_WEB_INSET_Y"))
    let width     = expect StrConv.toF32(Env.variable("SWAG_CAPTURE_WEB_WIDTH"))
    let height    = expect StrConv.toF32(Env.variable("SWAG_CAPTURE_WEB_HEIGHT"))
    let stallMs   = expect StrConv.toU32(Env.variable("SWAG_CAPTURE_WEB_STALL_MS"))
    let maxMissed = expect StrConv.toS32(Env.variable("SWAG_CAPTURE_WEB_MAX_MISSED"))
    Console.println("Browser capture rectangle: ", x, ", ", y, " ", width, " x ", height)

    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    let app  = journey.app
    main.captureOptions.recordCountdown   = false
    main.captureOptions.captureCursor     = Env.variable("SWAG_CAPTURE_WEB_CURSOR") == "true"
    main.captureOptions.recordSystemSound = true
    main.captureOptions.recordVideoQuality = webCaptureQuality()
    main.captureOptions.recordMicrophone  = false
    main.captureOptions.inPlaceEdit       = true
    main.captureOptions.hideEditorBefore  = true
    main.captureOptions.sendToEditor      = true
    var stage: u32
    var stalled = false
    app.sigFrame += func|&journey, x, y, width, height, browser, stallMs, maxMissed, stage = &stage, stalled = &stalled|(_)
    {
        Swag.require(journey.watch.elapsedMilliseconds() < 38_000, "web recording timed out")
        if stage[] == 0
        {
            for surface in journey.app.surfaces
            {
                if surface.view() is CaptureRectWnd as overlay
                {
                    var attach = KeyEvent{kind: .Pressed, key: .A, modifiers: .None}
                    overlay.sendEvent(&attach)
                    let scale   = overlay.deviceScale()
                    let first   = Math.Point{(x - g_DesktopX) / scale, (y - g_DesktopY) / scale}
                    var pointer = MouseEvent{kind: .Pressed, button: .Left, surfacePos: first}
                    overlay.sendEvent(&pointer)
                    pointer.kind = .Move

                    // Keep the last physical pixel through a fractional DPI round trip.
                    pointer.surfacePos = first + Math.Point{(width + 0.25) / scale, (height + 0.25) / scale}
                    overlay.sendEvent(&pointer)
                    pointer.kind = .Released
                    overlay.sendEvent(&pointer)
                    if not g_CaptureAnchored or g_CaptureWindow.nativeWindow != cast(u64, browser) do
                        Console.println("Area link: selected=", g_StartGrabX, ", ", g_StartGrabY,
                                        " -> ", g_EndGrabX, ", ", g_EndGrabY,
                                        " anchored=", g_CaptureAnchored,
                                        " selected_window=", g_CaptureWindow.nativeWindow,
                                        " browser=", cast(u64, browser),
                                        " title=", g_CaptureWindow.title)
                    Swag.require(g_CaptureAnchored and g_CaptureWindow.nativeWindow == cast(u64, browser),
                                 "selected area must be linked to the actual browser window")
                    stage[] = 1
                    return
                }
            }
        }
        elif stage[] == 1
        {
            if g_Recorder
            {
                let recorder = unwrap g_Recorder
                Swag.require(recorder.state == .Preparing and recorder.target.window == cast(u64, browser),
                             "the live preparation must follow the chosen browser window")
                let hud = unwrap recorder.hud
                stage[] = 2
                hud.pauseButton.sigPressed.call(hud.pauseButton)
                Swag.require(recorder.recordRequested)
                return
            }
        }
        elif stage[] == 2 and g_Recorder
        {
            let recorder = unwrap g_Recorder
            if not stalled[] and recorder.elapsed() >= 2_000_000
            {
                // A slow picture may stall the UI producer; the sound must remain continuous.
                stalled[] = true
                Threading.Thread.sleep(Time.Duration.fromMilliseconds(stallMs))
            }

            if recorder.elapsed() >= 6_000_000
            {
                // Stop the screen reader before inspecting its counters from this thread.
                recorder.videoProducer.close()
                Swag.require(recorder.videoAudio and recorder.videoAudio.systemIsActive(),
                             "system loopback must be active, not replaced with silent packets")
                let audio: *VideoRecordingAudio = recorder.videoAudio
                Console.println("Web recording: frames=", recorder.video.frameCount(), " duration_us=", recorder.elapsed(), " source_failures=", recorder.video.sourceFailureCount())
                Console.println("Video missed slots=", recorder.video.missedFrameSlotCount(), " forced_ui_stall_ms=", stallMs)
                Console.println("Video work: fresh=", recorder.video.freshFrames, " grab_us=", recorder.video.grabMicroseconds, " encode_us=", Atomic.get(&recorder.video.encoder.encodeMicroseconds), " repeat_us=", Atomic.get(&recorder.video.encoder.repeatMicroseconds), " producer_wait_us=", recorder.video.producerWaitMicroseconds, " runtime_workers=", Swag.workerCount())
                Console.println("Video peaks: grab_us=", recorder.video.maxGrabMicroseconds,
                                " scale_us=", recorder.video.maxScaleMicroseconds,
                                " submit_us=", recorder.video.maxProducerWaitMicroseconds,
                                " first_missed=", recorder.video.firstMissedSlot,
                                " last_missed=", recorder.video.lastMissedSlot)
                Console.println("Screen read: dc_us=", recorder.video.source.dcMicroseconds,
                                " blit_us=", recorder.video.source.blitMicroseconds,
                                " flush_us=", recorder.video.source.flushMicroseconds,
                                " copy_us=", recorder.video.source.copyMicroseconds,
                                " cursor_us=", recorder.video.source.cursorMicroseconds)
                Console.println("Screen backend: dxgi=", recorder.video.source.accelerated != null)
                if let accelerated = recorder.video.source.accelerated
                {
                    let metrics = accelerated.metrics()
                    Console.println("DXGI work: acquired=", metrics.acquiredFrames,
                                    " unchanged=", metrics.unchangedFrames,
                                    " acquire_us=", metrics.acquireMicroseconds,
                                    " max_acquire_us=", metrics.maxAcquireMicroseconds,
                                    " readback_us=", metrics.readbackMicroseconds,
                                    " max_readback_us=", metrics.maxReadbackMicroseconds,
                                    " coalesced_updates=", metrics.coalescedUpdates,
                                    " multi_rect=", metrics.multiRectFrames,
                                    " copy_us=", metrics.copyMicroseconds,
                                    " mirrored_pixels=", metrics.mirroredPixels,
                                    " output_us=", metrics.outputMicroseconds,
                                    " compose_us=", metrics.composeMicroseconds)
                }
                if maxMissed >= 0 do
                    Swag.require(recorder.video.missedFrameSlotCount() <= cast(u64, maxMissed),
                                 "recording exceeded the requested missed-frame budget")
                scope
                {
                    audio.encoderMutex.lock()
                    defer audio.encoderMutex.unlock()
                    Console.println("System sound queue: dropped_blocks=",
                                    audio.systemQueue.droppedBlockCount(),
                                    " dropped_frames=",
                                    audio.systemQueue.droppedFrameCount(),
                                    " synthetic_frames=",
                                    audio.systemPump.syntheticFrameCount(),
                                    " interruptions=",
                                    audio.systemPump.sourceInterruptionCount())
                    Swag.require(audio.systemQueue.droppedFrameCount() == 0, "video work must not overflow the sound queue")
                    Swag.require(audio.systemPump.syntheticFrameCount() < 9_600,
                                 "sound gaps must remain bounded to source startup, including during a slow picture")
                    Swag.require(audio.systemPump.sourceInterruptionCount() <= 1,
                                 "video work must not repeatedly interrupt the native sound source")
                }

                Swag.require(recorder.video.sourceFailureCount() == 0 and
                             (recorder.video.source.accelerated != null or recorder.video.source.memoryDC != null))
                stage[] = 3
                let hud = unwrap recorder.hud
                hud.stopButton.sigPressed.call(hud.stopButton)
            }
        }
    }

    // Keep the fixture browser exposed before selection; the native journey window otherwise
    // overlaps a large browser area and can become the window selected by the rectangle.
    journey.surface.hide()
    main.sendCommandEvent(ActionCapture.RecordVideo)
    app.runFrame()
    app.sigFrame.clear()
    Swag.require(stage == 3 and g_Recorder == null and app.surfaces.count == 1)

    let capture = unwrap main.editWnd.getCapture()
    Console.println("Captured dimensions: ", capture.width, " x ", capture.height)
    Swag.require(capture.media == .Video and capture.width == width and capture.height == height)
    var document = String.from(capture.file)
    let media    = Capture.mediaPathOf(document, .Video)
    let bytes    = expect File.readAllBytes(media)
    discard expect File.writeAllBytes(Path.combine(evidence, "web.mp4"), bytes.toSlice())
    var reader = expect Video.Reader.open(media)
    Swag.require(reader.frameCount() >= 150 and reader.durationInSeconds() >= 5.9)
    Swag.require(reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleRateHz() == 48_000 and sound.numChannels() == 2)
    Console.println("MP4 durations: video=", reader.durationInSeconds(), " audio=", sound.durationInSeconds(), " audio_start=", sound.timelineStartSeconds())
    Swag.require(Math.abs(sound.durationInSeconds() - reader.durationInSeconds()) < 0.15,
                 "audio and video durations must agree")

    var recordedTone: WebCaptureTone
    expect sound.decodePcm16(func|&recordedTone, sound|(pcm: const [..] s16)->bool
    {
        recordedTone.add(pcm, sound.numChannels(), sound.sampleRateHz(), recordedTone.frames)
        return true
    })
    Console.println("Recorded audio: frames=", recordedTone.frames, " rms=", recordedTone.rms(), " tone_fraction=", recordedTone.toneFraction())
    Swag.require(recordedTone.rms() > 300 and recordedTone.toneFraction() > 0.90,
                 "MP4 must contain the browser's 440 Hz audio")

    var picture:  Image
    var changes:  u64
    var previous: u32
    for index in reader.frameCount()
    {
        expect reader.decodeFrameInto(&picture, index)
        let hash = Hash.hashBytes32(picture.pixels.toSlice())
        if index and hash != previous do
            changes += 1
        previous = hash
        if index == 0 or index + 1 == reader.frameCount() do
            expect picture.save(Path.combine(evidence, Format.toString("frame-%.png", index).toString()))
    }

    Console.println("Decoded every frame: count=", reader.frameCount(), " changed=", changes)
    Swag.require(changes > reader.frameCount() / 2, "browser video must move throughout the recording")

    // Reopen the saved capture from the real library, rather than playing an in-memory fixture.
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("web video reopened", func|main, &document|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == document and main.timeline != null
    })
    let opened   = unwrap main.editWnd.getCapture()
    let timeline = unwrap main.timeline
    discard expect File.writeAllText(Path.combine(evidence, "mute-source"), "mute")
    journey.waitFor("browser paused and muted", func|evidence|()->bool
                    => File.exists(Path.combine(evidence, "source-silent")))

    // Editor frames at large capture sizes can delay the test consumer; retain the
    // independent output samples until the next GUI frame drains the probe.
    var queue = expect CaptureQueue.create(48_000, 2, Time.monotonicMicroseconds() * 10, 10_000_000, slots: 256)
    var loopback: WebCaptureOutputProbe
    expect loopback.start(&queue)
    defer loopback.close()
    var pcm:   Array's16
    var block: CaptureBlock
    var baseline, quietWindow: WebCaptureTone
    let quietStart = Time.monotonicMicroseconds()
    var lastLoudAt, lastPacketAt = quietStart
    while Time.monotonicMicroseconds() - lastLoudAt < 400_000
    {
        app.runFrame()
        Swag.require(Time.monotonicMicroseconds() - quietStart < 4_000_000,
                     "browser audio did not drain after pause and mute")
        expect loopback.check()
        while queue.pop(&pcm, &block)
        {
            lastPacketAt = Time.monotonicMicroseconds()
            quietWindow.add(pcm.toSlice(), 2, 48_000, block.startSample)
            if quietWindow.frames >= 4_800
            {
                baseline = quietWindow
                if baseline.rms() * Math.sqrt(baseline.toneFraction()) >= 300 do
                    lastLoudAt = lastPacketAt
                quietWindow = WebCaptureTone{}
            }
        }

        if Time.monotonicMicroseconds() - lastPacketAt > 250_000 do
            baseline = WebCaptureTone{}
    }

    let baselineToneRms = baseline.rms() * Math.sqrt(baseline.toneFraction())
    Console.println("Browser muted, output baseline rms=", baseline.rms(), " tone_fraction=", baseline.toneFraction(), " tone_rms=", baselineToneRms)
    Swag.require(baselineToneRms < 300,
                 "the browser's reference tone must be absent before editor playback")
    timeline.playButton.sigPressed.call(timeline.playButton)
    defer timeline.stop()
    Swag.require(Audio.activeDriverKind() == .XAudio2 and timeline.audioVoices[0] != null,
                 "editor must use the real native audio device")
    let voice           = unwrap timeline.audioVoices[0]
    let frames          = unwrap opened.frames
    var replayTone: WebCaptureTone
    var maxAudioFrame, maxPicture: u64
    var checkpoint: bool
    var wrapped:    bool
    var previousPicture = opened.playhead
    let playStart       = Time.monotonicMicroseconds()

    // The editor intentionally loops. Observe a full pass and its wrap, then pause through
    // the actual transport button; waiting for an automatic stop would never finish.
    while not wrapped
    {
        app.runFrame()
        Swag.require(journey.watch.elapsedMilliseconds() < 38_000, "web playback timed out")
        Swag.require(timeline.isPlaying(), "editor playback stopped before completing the clip")
        expect loopback.check()
        while queue.pop(&pcm, &block) do
            replayTone.add(pcm.toSlice(), 2, 48_000, block.startSample)
        maxAudioFrame = Math.max(maxAudioFrame, voice.playbackSampleFrame())
        maxPicture    = Math.max(maxPicture, opened.playhead)
        wrapped       = opened.playhead < previousPicture and
                        frames.timeOf(maxPicture) + 200_000 >= frames.endTime
        previousPicture = opened.playhead
        if not checkpoint and frames.timeOf(opened.playhead) >= 2_000_000
        {
            checkpoint = expect Gui.Testing.verifyNativePresentation(journey.surface)
            if checkpoint
            {
                app.renderer.setCurrentContext(journey.surface.renderingContext())
                let screenshot = app.renderer.readRenderTarget(&journey.surface.rt, 0, 0, journey.surface.rt.colorBuffer.width, journey.surface.rt.colorBuffer.height)
                expect screenshot.save(Path.combine(evidence, "editor-playing.png"))
            }
        }
    }

    let playedUs = Time.monotonicMicroseconds() - playStart
    timeline.playButton.sigPressed.call(timeline.playButton)
    Swag.require(not timeline.isPlaying())
    Console.println("Editor replay: picture=", maxPicture, " audio_frame=", maxAudioFrame, " elapsed_us=", playedUs, " rms=", replayTone.rms(), " tone_fraction=", replayTone.toneFraction(), " presentation=", checkpoint)
    Console.println("Replay probe dropped frames=", queue.droppedFrameCount())
    Swag.require(queue.droppedFrameCount() == 0, "the independent output probe must retain the replayed sound")
    Swag.require(checkpoint and wrapped)
    Swag.require(maxAudioFrame >= 5 * 48_000 and playedUs >= 5_500_000)
    Swag.require(replayTone.rms() > 300 and replayTone.toneFraction() > 0.85,
                 "system output must contain the editor's replayed tone while the browser is muted")
    Swag.require(replayTone.rms() * Math.sqrt(replayTone.toneFraction()) > Math.max(300, baselineToneRms * 4),
                 "editor output must introduce the reference tone above the measured background")
    discard expect File.writeAllText(Path.combine(evidence, "passed"), "web video and audio recorded and replayed")
}

// Exercise the shipped full-screen and monitor commands with native DXGI frames.
#[Swag.TestTag("integration.capture.fullscreen")]
#test
{
    Swag.require(Env.hasArgument("swag.capture.native-screen=true"),
                 "launch this device integration with tools/capture-web.py")
    let desktop = Env.variable("SWAG_CAPTURE_WEB_MODE") == "desktop"
    let browser = Win32.FindWindowA(null, "Swag Capture Web AV Probe".buffer)
    Swag.require(browser != null, "the owned browser fixture window is missing")
    var browserBounds: Win32.RECT
    Swag.require(Win32.GetWindowRect(browser, &browserBounds))
    let browserX = browserBounds.left + expect StrConv.toS32(Env.variable("SWAG_CAPTURE_WEB_INSET_X"))
    let browserY = browserBounds.top + expect StrConv.toS32(Env.variable("SWAG_CAPTURE_WEB_INSET_Y"))
    let monitors = Env.getMonitors()
    var monitorIndex = Swag.U64.Max
    for index in monitors.count
    {
        let bounds = monitors[index].physicalBounds
        if browserX >= bounds.x and browserX < bounds.right() and
           browserY >= bounds.y and browserY < bounds.bottom()
        {
            monitorIndex = index
            break
        }
    }
    Swag.require(monitorIndex != Swag.U64.Max, "the browser fixture is outside the connected monitors")
    let expected = desktop ? Math.Rectangle{Env.getSystemMetric(.DesktopX),
                                             Env.getSystemMetric(.DesktopY),
                                             Env.getSystemMetric(.DesktopWidth),
                                             Env.getSystemMetric(.DesktopHeight)} :
                             monitors[monitorIndex].physicalBounds
    let videoWidth = cast(s32, Math.floor(expected.width / 2) * 2)
    let videoHeight = cast(s32, Math.floor(expected.height / 2) * 2)
    let maxSide = Math.max(videoWidth, videoHeight)
    let outputWidth = maxSide > 4096 ?
                      Math.max(2, cast(s32, Math.floor(cast(f64, videoWidth) * 4096 / maxSide / 2)) * 2) : videoWidth
    let outputHeight = maxSide > 4096 ?
                       Math.max(2, cast(s32, Math.floor(cast(f64, videoHeight) * 4096 / maxSide / 2)) * 2) : videoHeight
    let maxMissed = expect StrConv.toS32(Env.variable("SWAG_CAPTURE_WEB_MAX_MISSED"))
    let durationSeconds = expect StrConv.toU32(Env.variable("SWAG_CAPTURE_WEB_DURATION"))
    let evidence = Env.sandboxRoot()
    Console.println("Full-screen capture: mode=", desktop ? "desktop" : "monitor",
                    " bounds=", expected.x, ", ", expected.y, " ", expected.width, " x ", expected.height)

    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    let app = journey.app
    main.captureOptions.recordCountdown = false
    main.captureOptions.captureCursor = Env.variable("SWAG_CAPTURE_WEB_CURSOR") == "true"
    main.captureOptions.recordSystemSound = false
    main.captureOptions.recordVideoQuality = webCaptureQuality()
    main.captureOptions.recordMicrophone = false
    main.captureOptions.inPlaceEdit = true
    main.captureOptions.hideEditorBefore = true
    main.captureOptions.sendToEditor = true
    var stage: u32
    app.sigFrame += func|&journey, desktop, expected, videoWidth, videoHeight, maxMissed, durationSeconds, stage = &stage|(_)
    {
        Swag.require(journey.watch.elapsedMilliseconds() < cast(u64, durationSeconds + 25) * 1_000,
                     "full-screen recording timed out")
        if not g_Recorder do
            return
        let recorder = unwrap g_Recorder
        if stage[] == 1 and recorder.video.sourceFailureCount() >= 3 do
            Swag.require(false, "native desktop capture is unavailable; check desktop access")
        if stage[] == 0
        {
            Swag.require(recorder.state == .Preparing and recorder.target.window == 0)
            let hud = unwrap recorder.hud
            let hudSurface = unwrap hud.surface
            var affinity: Win32.DWORD
            Swag.require(GetWindowDisplayAffinity(hudSurface.win32Handle(), &affinity) and
                         affinity == 0x11'u32,
                         "the recording controls must be excluded from desktop capture")
            if desktop
            {
                let screenButton = unwrap hud.screenButton
                screenButton.sigPressed.call(screenButton)
                let choices = unwrap hud.screenChoices
                Swag.require(choices.menu.surface != hud.surface,
                             "the screen menu must have its own native surface")
                choices.menu.sigCommandSelected.call(choices.menu, AllScreensChoiceId)
                choices.close()
                Swag.require(hudSurface.position.intersects(recorder.area),
                             "the full-desktop test must exercise overlapping recording controls")
            }
            Swag.require(recorder.area.x == expected.x and recorder.area.y == expected.y and
                         recorder.area.width == videoWidth and recorder.area.height == videoHeight)
            stage[] = 1
            hud.pauseButton.sigPressed.call(hud.pauseButton)
        }
        elif stage[] == 1 and recorder.elapsed() >= cast(u64, durationSeconds) * 1_000_000
        {
            Swag.require(recorder.edges.isEmpty(), "the screen selection frame must be gone before encoding")
            recorder.videoProducer.close()
            Console.println("Full-screen recording: frames=", recorder.video.frameCount(),
                            " fresh=", recorder.video.freshFrames,
                            " missed=", recorder.video.missedFrameSlotCount(),
                            " source_failures=", recorder.video.sourceFailureCount(),
                            " grab_us=", recorder.video.grabMicroseconds,
                            " max_grab_us=", recorder.video.maxGrabMicroseconds,
                            " scale_us=", recorder.video.scaleMicroseconds,
                            " max_scale_us=", recorder.video.maxScaleMicroseconds,
                            " encode_us=", Atomic.get(&recorder.video.encoder.encodeMicroseconds),
                            " repeat_us=", Atomic.get(&recorder.video.encoder.repeatMicroseconds),
                            " max_submit_us=", recorder.video.maxProducerWaitMicroseconds,
                            " first_missed=", recorder.video.firstMissedSlot,
                            " last_missed=", recorder.video.lastMissedSlot,
                            " dxgi=", recorder.video.source.accelerated != null)
            if let accelerated = recorder.video.source.accelerated
            {
                let metrics = accelerated.metrics()
                Console.println("DXGI work: acquired=", metrics.acquiredFrames,
                                " unchanged=", metrics.unchangedFrames,
                                " partial=", metrics.partialFrames,
                                " copied_pixels=", metrics.copiedPixels,
                                " acquire_us=", metrics.acquireMicroseconds,
                                " max_acquire_us=", metrics.maxAcquireMicroseconds,
                                " readback_us=", metrics.readbackMicroseconds,
                                " max_readback_us=", metrics.maxReadbackMicroseconds,
                                " deferred_readbacks=", metrics.deferredReadbacks,
                                " coalesced_updates=", metrics.coalescedUpdates,
                                " multi_rect=", metrics.multiRectFrames,
                                " copy_us=", metrics.copyMicroseconds,
                                " mirrored_pixels=", metrics.mirroredPixels,
                                " output_us=", metrics.outputMicroseconds,
                                " compose_us=", metrics.composeMicroseconds)
            }
            Swag.require(recorder.video.sourceFailureCount() == 0 and
                         recorder.video.source.accelerated != null)
            if Env.variable("SWAG_CAPTURE_WEB_MOTION_STRESS") == "true" do
                Swag.require(recorder.video.freshFrames * 4 >= recorder.video.frameCount() * 3,
                             "full-screen recording lost too many moving desktop frames")
            if maxMissed >= 0 do
                Swag.require(recorder.video.missedFrameSlotCount() <= cast(u64, maxMissed),
                             "full-screen recording exceeded the missed-frame budget")
            stage[] = 2
            let hud = unwrap recorder.hud
            hud.stopButton.sigPressed.call(hud.stopButton)
        }
    }

    journey.surface.hide()
    if desktop do
        main.sendCommandEvent(ActionCapture.RecordScreen)
    else do
        main.recordVideoScreen(.Monitor, monitorIndex)
    app.runFrame()
    app.sigFrame.clear()
    Swag.require(stage == 2 and g_Recorder == null)
    let capture = unwrap main.editWnd.getCapture()
    Swag.require(capture.media == .Video and capture.width == outputWidth and
                 capture.height == outputHeight)
    let media = Capture.mediaPathOf(String.from(capture.file), .Video)
    var reader = expect Video.Reader.open(media)
    Console.println("Full-screen file: frames=", reader.frameCount(),
                    " duration=", reader.durationInSeconds())
    // A gap longer than four slots is represented by one held sample, so its duration
    // matters here rather than the number of encoded pictures.
    Swag.require(reader.frameCount() > 0 and
                 Math.isEqualEpsilon(reader.frameTimestamp(0), 0, 0.000001),
                 "full-screen recording begins after time zero")
    Swag.require(reader.durationInSeconds() >= cast(f64, durationSeconds) - 0.1,
                 "full-screen recording ends over 100 ms before the requested duration")
    var image: Image
    expect reader.decodeFrameInto(&image, 0)
    Swag.require(image.width == outputWidth and image.height == outputHeight)
    let firstHash = Hash.hashBytes32(image.pixels.toSlice())
    expect reader.decodeFrameInto(&image, reader.frameCount() - 1)
    Swag.require(Hash.hashBytes32(image.pixels.toSlice()) != firstHash,
                 "the full-screen recording must preserve moving pixels")
    expect image.save(Path.combine(evidence, "fullscreen-last.png"))
    Console.println("Full-screen file: frames=", reader.frameCount(),
                    " duration=", reader.durationInSeconds(), " decoded=", image.width, " x ", image.height)
    if durationSeconds <= 10 do
        discard expect File.writeAllBytes(Path.combine(evidence, "fullscreen.mp4"),
                                          (expect File.readAllBytes(media)).toSlice())
    discard expect File.writeAllText(Path.combine(evidence, "passed"), "full-screen recording decoded")
}

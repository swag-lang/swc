#global internal
#global namespace Viewers.Sound

using Core, Pixel, Gui, Audio, Threading

// Describes the waveform player to the host.
//
// It offers itself for every extension the audio module can decode, so a codec added there reaches
// the player without a list to update here.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "sound"
        .staticName   = "Sound"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Sound)
        .create       = &createViewer
        .smokeFixture = "pacman_beginning.wav"
    }

    let extensions = SoundFile.decodableExtensions()
    result.addSelectors(extensions.toSlice())
    return result
}

private
{
    const SeekSeconds  = 10.0
    const CommandWidth = 820.0

    // Slices the payload is reduced to. It is read back one column of pixels at a time, so it only
    // has to stay ahead of the widest plot a window can give it; past that the columns repeat.
    const WaveformPointCount = 4096'u64

    // The page of a recording, after `scope.sound`: the cover, the name and who made it, then the
    // wave as a row of bars with the times under it.
    const CoverSize   = 180.0      // Side of the cover.
    const CoverTop    = 88.0       // Distance from the strip to the cover.
    const MinCoverTop = 24.0       // Distance a short window keeps between the strip and the cover.
    const CoverCorner = 12.0       // Corner of the cover, the one of a floating surface.
    const TitleSize   = 28'u32     // Size of the name of the recording.
    const TitleGap    = 24.0       // Air between the cover and the name.
    const CreditGap   = 6.0        // Air between the name and who made it.
    const CreditSize  = 15'u32     // Size of who made it.
    const WaveWidth   = 1000.0     // Widest the wave stands.
    const WaveBottom  = 84.0       // Distance from the bottom of the page to the bottom of the wave's band.
    const WaveHeight  = 110.0      // Height of the bars at their loudest.
    const BarWidth    = 4.0        // Width of one bar of the wave.
    const BarGap      = 3.5        // Air between two bars.
    const TimesGap    = 14.0       // Air between the bars and the times under them.
    const TimesHeight = 26.0       // Height of the line of times.
    const WaveGap     = 32.0       // Least air between who made it and the wave.
}

// Loudness of a slice, in the two readings a level meter carries: the transient that clips and the
// body the ear hears. Drawing both is what separates a waveform from a silhouette.
struct WaveformPoint
{
    peak: f32     // Loudest absolute level of the slice.
    body: f32     // Mean absolute level of the slice.
}

private var g_EngineUsers:      u32
private var g_ViewerOwnsEngine: bool

// Creation of the audio engine started ahead of the first voice, on a runtime worker.
private var g_EngineWarmUp:  Swag.Task
private var g_EngineWarming: bool

// Starts creating the audio engine without waiting for it.
//
// Opening the output device is the better part of a second, and a player that only asks for
// the engine once its first picture is ready to be shown adds that second to the wait for
// the picture. Starting it here lets the device come online while the file is being opened
// and its first picture decoded; [[acquireEngine]] then joins the work instead of doing
// it. Call it from the GUI thread, which is the only one that acquires the engine.
func warmEngine()
{
    if g_EngineWarming or g_EngineUsers or isEngineCreated() do
        return

    g_EngineWarming = true
    g_EngineWarmUp.submit(func()
    {
        discard catch createEngine()
    })
}

// Takes a reference on the shared audio engine, creating it on first use, and reports whether the engine is available.
//
// Call [[releaseEngine]] once for every successful acquisition.
func acquireEngine(kind = DriverKind.Default)->bool
{
    if g_EngineUsers
    {
        g_EngineUsers += 1
        return true
    }

    if g_EngineWarming
    {
        g_EngineWarmUp.wait()
        g_EngineWarming = false
        if isEngineCreated() do
            g_ViewerOwnsEngine = true
    }

    if not isEngineCreated()
    {
        catch createEngine(kind) { return false }
        g_ViewerOwnsEngine = true
    }

    g_EngineUsers = 1
    return true
}

// Drops a reference taken by [[acquireEngine]], destroying the engine with the last one when a viewer created it.
func releaseEngine()
{
    if not g_EngineUsers do
        return
    g_EngineUsers -= 1
    if g_EngineUsers or not g_ViewerOwnsEngine do
        return
    destroyEngine()
    g_ViewerOwnsEngine = false
}

// Reads the PCM sample at `offset` as a level between -1 and 1, or 0 for an encoding that is not PCM.
func sampleAt(bytes: const [..] u8, offset: u64, encoding: SoundFileEncoding)->f32
{
    switch encoding
    {
    case .Pcm8:
        return (cast(f32, bytes[offset]) - 128) / 128

    case .Pcm16:
        let raw = Math.make16(bytes[offset + 1], bytes[offset])
        return cast(f32, cast #bit (s16, raw)) / 32768

    case .Pcm24:
        var raw = Math.make32(0, bytes[offset + 2], bytes[offset + 1], bytes[offset])
        if raw & 0x00800000 do
            raw |= 0xFF000000
        return cast(f32, cast #bit (s32, raw)) / 8388608

    case .Pcm32:
        let raw = Math.make32(bytes[offset + 3], bytes[offset + 2], bytes[offset + 1], bytes[offset])
        return cast(f32, cast #bit (s32, raw)) / 2147483648

    case .Float32:
        let raw = Math.make32(bytes[offset + 3], bytes[offset + 2], bytes[offset + 1], bytes[offset])
        return Math.clamp(cast #bit (f32, raw), -1, 1)
    }

    return 0
}

// Reduces an interleaved PCM payload to at most [[WaveformPointCount]] points, mixing its channels.
func buildWaveform(bytes: const [..] u8, encoding: SoundFileEncoding, channels: u32)->Array'WaveformPoint
{
    var result: #returntype
    if not bytes.count or not channels do
        return result

    var bytesPerSample = 4'u64
    switch encoding
    {
    case .Pcm8:  bytesPerSample = 1
    case .Pcm16: bytesPerSample = 2
    case .Pcm24: bytesPerSample = 3
    }

    let bytesPerFrame = bytesPerSample * channels
    let frameCount    = bytes.count / bytesPerFrame
    let pointCount    = Math.min(frameCount, WaveformPointCount)
    if not pointCount do
        return result
    result.resize(pointCount)

    for point in pointCount
    {
        let first = point * frameCount / pointCount
        let last  = Math.max((point + 1) * frameCount / pointCount, first + 1)
        var peak  = 0'f32
        var sum   = 0'f32
        for frame in first until last
        {
            var mixed = 0'f32
            for channel in channels
            {
                let offset = frame * bytesPerFrame + channel * bytesPerSample
                mixed += sampleAt(bytes, offset, encoding)
            }

            mixed /= channels
            let level = Math.abs(mixed)
            peak = Math.max(peak, level)
            sum  += level
        }

        result[point] = WaveformPoint{peak, sum / cast(f32, last - first)}
    }

    return result
}

// Formats the length of a sound for the host summary: milliseconds below one second, seconds with two decimals from there on.
func durationText(seconds: f32)->String
{
    if seconds < 1 do
        return Format.toString("% ms", cast(u32, Math.max(Math.round(seconds * 1000), 1)))
    return Format.toString("%{f2} s", seconds)
}

// Plots the waveform of a sound as a row of bars, the played part apart from the rest.
struct WaveformView
{
    using wnd:  Wnd
    panel:      *Panel?     // Player the wave seeks, when a click chooses a place.
    samples:    Array'WaveformPoint
    readyCount: u64     // Points the builder has published so far.
    duration:   f32
    progress:   f32     // Played fraction, from 0 to 1.
}

// Reduces successive interleaved PCM16 chunks without retaining their borrowed storage.
struct WaveformReducer
{
    points:       *Array'WaveformPoint
    frameCount:   u64
    pointCount:   u64
    channels:     u32
    frameOffset:  u64
    currentPoint: u64
    peak:         f32
    sum:          f64
    sampleCount:  u64
    readyCount:   u64
}

impl WaveformReducer
{
    // Folds interleaved `samples` into the waveform points, keeping for each point the peak and
    // mean level of its frames mixed to mono. A point is ready once the frames move past it.
    mtd consume(samples: const [..] s16)
    {
        let frames = samples.count / .channels
        for frame in frames
        {
            let target = Math.min(.frameOffset * .pointCount / .frameCount, .pointCount - 1)
            if target != .currentPoint
            {
                let body = .sampleCount ? cast(f32, (.sum / cast(f64, .sampleCount))) : 0
                .points[][.currentPoint] = WaveformPoint{.peak, body}
                .readyCount   = .currentPoint + 1
                .currentPoint = target
                .peak         = 0
                .sum          = 0
                .sampleCount  = 0
            }

            var mixed = 0'f32
            for channel in .channels do
                mixed += cast(f32, samples[frame * .channels + channel]) / 32768
            let level = Math.abs(mixed / .channels)
            .peak        = Math.max(.peak, level)
            .sum         += level
            .sampleCount += 1
            .frameOffset += 1
        }
    }

    mtd finish()
    {
        if not .sampleCount or .currentPoint >= .pointCount do
            return
        .points[][.currentPoint] = WaveformPoint{.peak, cast(f32, (.sum / cast(f64, .sampleCount)))}
        .readyCount = .currentPoint + 1
    }
}

private impl IWnd for WaveformView
{
    // Draws the wave as a row of bars, the played ones in Arc, with the elapsed time under its
    // start and the length under its end.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let bars    = Math.Rectangle{room.x, room.y, room.width, WaveHeight}
        let center  = bars.vertCenter()
        let count   = cast(u64, Math.max(Math.floor((bars.width + BarGap) / (BarWidth + BarGap)), 1))
        let played  = Math.clamp(.progress, 0, 1) * cast(f32, count)

        painter.setParams(.Antialiased)
        if not .samples.isEmpty()
        {
            for bar in count
            {
                let first = bar * .samples.count / count
                let last  = Math.max((bar + 1) * .samples.count / count, first + 1)
                if first >= .readyCount do
                    break
                var level = 0'f32
                for index in first until Math.min(last, .readyCount) do
                    level = Math.max(level, .samples[index].peak)

                // A quiet slice still stands as a dot, so the row reads as one wave.
                let height = Math.max(level * WaveHeight, BarWidth)
                let x      = bars.x + cast(f32, bar) * (BarWidth + BarGap)
                let color  = cast(f32, bar) < played ? colors.arc : colors.strongLine
                painter.fillRoundRect(Math.Rectangle{x, center - height * 0.5, BarWidth, height}, BarWidth * 0.5, BarWidth * 0.5, color)
            }
        }

        let mono    = .theme().createDefaultFontFs(.themeMetrics().defaultFixedFontSize)
        let strong  = .theme().createDefaultFontFs(.themeMetrics().defaultFixedFontSize, .Bold)
        let timesY  = bars.bottom() + TimesGap + TimesHeight * 0.5
        let elapsed = Viewer.timeText(.progress * .duration)
        let total   = Viewer.durationText(.duration)
        painter.drawString(room.x, strong.opticalLineTop(timesY), elapsed, strong, colors.text)
        painter.drawString(room.right() - Painter.measureString(total, mono).width, mono.opticalLineTop(timesY), total, mono, colors.faintText)
    }

    // A click on the wave plays from the place it chose.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left or .panel == null or .duration <= 0
        {
            evt.accepted = false
            return
        }

        let x = .surfaceToLocal(evt.surfacePos).x
        .panel.seekSeconds(Math.clamp(x / Math.max(.clientRect().width, 1), 0, 1) * .duration)
    }
}

// Plays a sound file over its waveform, with the transport in the host's command bar.
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:       *Wnd
        playButton:     *IconButton
        stopButton:     *IconButton
        backwardButton: *IconButton
        forwardButton:  *IconButton
        timeline:       *Slider
        timeLabel:      *Label
        muteButton:     *IconButton
        volumeSlider:   *Slider
        waveform:       *WaveformView
    }

    // Opening runs in the background; its end arrives as a task event.
    sound:        SoundFile
    openFileName: String
    openTask:     Swag.Task'SoundFile
    openFinished: bool
    opened:       bool

    waveformTask:  Swag.Task
    waveformLock:  Swag.Mutex
    waveformBuilt: u64

    voice:       *Voice?
    timer:       *Timer?
    duration:    f32
    elapsed:     f32
    engineReady: bool
    thumbnail:   bool
    playing:     bool
    muted:       bool
    volume:      f32 = 1

    retireRequested: bool
    retired:         bool

    tags:     SoundTags     // Written by the open worker; read only once it has finished.
    details:  String
    services: Viewer.HostServices
}

impl Panel
{
    // Reports whether work remains whose result has not reached the waveform yet.
    mtd isLoading()->bool
    {
        if not .openFinished do
            return true

        let built = .publishedWaveformCount()
        return .waveformTask.isPending() or .waveform.readyCount < built
    }

    // Reports whether the host should cover the view, which is until the sound has opened.
    mtd needsLoadingOverlay()->bool => not .openFinished or (.thumbnail and .isLoading())

    // Publishes the file opened in the background and initializes playback on the GUI thread.
    mtd completeOpen() fail
    {
        if .openFinished do
            return

        .openFinished      = true
        .sound             = try .openTask.take()
        .opened            = true
        .duration          = .sound.durationInSeconds()
        .waveform.duration = .duration
        .arrangeWave()     // The tags read beside the sound may add a line of credits.
        if .duration > 0 do
            .timeline.setBounds(0, .duration, Math.min(0.01'f32, .duration / 100))
        .startWaveform()

        .engineReady = not .thumbnail and acquireEngine()
        if .engineReady do
            .playButton.enable(true)
        .backwardButton.enable(.engineReady and .duration > 0)
        .forwardButton.enable(.engineReady and .duration > 0)
        .timeline.enable(.engineReady and .duration > 0)
        .muteButton.enable(.engineReady)
        .volumeSlider.enable(.engineReady)
        .refreshTransport()
        if not .engineReady do
            .playButton.toolTip = texts().ui_NoEngine
        .refreshDetails()
        .services.loadingChanged(me)
    }

    // Rebuilds the host summary in the active language and reports it: how the recording is
    // stored. What it is stands on the page.
    mtd refreshDetails()
    {
        .details = Format.toString(texts().ui_Details,
                                   .sound.sampleRateHz(),
                                   channelCountText(.sound.numChannels()),
                                   .sound.sampleStorageBits(),
                                   durationText(.duration))
        .services.showDetails(me, .details)
        .invalidate()
    }

    // Returns the name the page writes: the title the tags give, or the name of the file.
    mtd title()->String
    {
        if not .tags.title.isEmpty() do
            return String.from(.tags.title)
        return String.from(Path.fileNameWithoutExtension(.openFileName) orelse .openFileName)
    }

    // Returns who made the recording and where it belongs, the way the page writes it under the
    // name: the artist, the album and the year the tags give.
    mtd credits()->String
    {
        var result: #returntype
        let artist = .tags.artist.isEmpty() ? .tags.albumArtist.toString() : .tags.artist.toString()
        for name in [artist, .tags.album.toString(), .tags.year.toString()] where name.count
        {
            if not result.isEmpty() do
                result += " · "
            result += name
        }

        return result
    }

    // Returns where the page stands: the cover centered under the strip, the top of the name
    // under it, and the top of the wave's band.
    //
    // The wave keeps to the foot of the page and the name never runs into it: a short window
    // gives up the air above the cover first.
    mtd pageLayout()->{cover: Math.Rectangle, titleTop: f32, waveTop: f32}
    {
        let room  = .clientRect()
        let theme = .theme()
        var words = TitleGap + theme.createDefaultFont(TitleSize, .Bold).height
        if not .credits().isEmpty() do
            words += CreditGap + theme.createDefaultFont(CreditSize).height

        let wave  = WaveHeight + TimesGap + TimesHeight
        let strip = .stripInset()
        let spare = room.height - strip - CoverSize - words - WaveGap - wave - WaveBottom

        var result: #returntype
        result.cover    = {Math.round((room.width - CoverSize) * 0.5), strip + Math.clamp(spare, MinCoverTop, CoverTop), CoverSize, CoverSize}
        result.titleTop = result.cover.bottom() + TitleGap
        result.waveTop  = Math.max(room.height - WaveBottom - wave, result.cover.bottom() + words + WaveGap)
        return result
    }

    // Places the wave across the lower part of the page.
    mtd arrangeWave()
    {
        let room  = .clientRect()
        let width = Math.min(WaveWidth, Math.max(room.width - 2 * 48, 1))
        .waveform.setPosition(Math.Rectangle{Math.round((room.width - width) * 0.5), .pageLayout().waveTop, width, WaveHeight + TimesGap + TimesHeight})
    }

    mtd retranslate()
    {
        .playButton.toolTip     = .playing ? texts().ui_TipPause : texts().ui_TipPlay
        .stopButton.toolTip     = texts().ui_TipStop
        .backwardButton.toolTip = texts().ui_TipBackward
        .forwardButton.toolTip  = texts().ui_TipForward
        .volumeSlider.toolTip   = texts().ui_TipVolume
        .muteButton.toolTip     = texts().ui_TipMute
        .timeline.toolTip       = texts().ui_TipSeek
        if not .opened do
            return

        if not .engineReady do
            .playButton.toolTip = texts().ui_NoEngine
        .refreshDetails()
    }

    // Finishes teardown once neither task can touch the sound or waveform storage.
    mtd finishRetire()
    {
        if .retired do
            return
        .openTask.wait()
        .waveformTask.wait()
        .retired = true
    }

    // Requests teardown without waiting on the GUI thread, and reports whether deferred GUI destruction may release this view.
    mtd retire()->bool
    {
        if .retired do
            return true
        if not .retireRequested
        {
            .retireRequested = true
            .stopTimer(&.timer)

            if .voice
            {
                catch .voice.stop()
                .voice.destroy()
                .voice = null
            }

            if .engineReady
            {
                releaseEngine()
                .engineReady = false
            }

            .openTask.cancel()
            .waveformTask.cancel()
        }

        if .openTask.isPending() or .waveformTask.isPending() do
            return false
        .finishRetire()
        return true
    }

    // Tears the view down for window destruction, which, unlike file selection, may wait for both workers.
    mtd retireBlocking()
    {
        discard .retire()
        .finishRetire()
    }

    // Publishes the first `count` waveform points to the GUI thread.
    //
    // The worker never changes a published point, so the painter can read that prefix after taking
    // this one synchronized count without copying the whole wave.
    mtd publishWaveform(count: u64)
    {
        Sync.scopedLock(&.waveformLock)
        .waveformBuilt = count
    }

    // Returns how many waveform points the worker has published.
    mtd publishedWaveformCount()->u64
    {
        Sync.scopedLock(&.waveformLock)
        return .waveformBuilt
    }

    // Decodes the sound independently from voice streaming and reduces it to the waveform budget.
    //
    // Successive PCM16 chunks are reduced as they arrive; the callback never retains the decoder's
    // borrowed storage.
    mtd buildWaveformInBackground()
    {
        let frameCount = .sound.sampleFrameCount()
        let pointCount = .waveform.samples.count
        let channels   = .sound.numChannels()
        if not frameCount or not pointCount or not channels do
            return

        var reducer = WaveformReducer{&.waveform.samples, frameCount, pointCount, channels}
        catch .sound.decodePcm16(func|reducer = &reducer, view = me|(samples: const [..] s16)->bool
        {
            reducer.consume(samples)
            if reducer.readyCount do
                view.publishWaveform(reducer.readyCount)
            return not Swag.isCancelled()
        })
        reducer.finish()
        .publishWaveform(reducer.readyCount)
    }

    // Starts the background task that reduces the sound to its waveform. The playback timer shows
    // the points as they are published.
    mtd startWaveform()
    {
        let pointCount = Math.min(.sound.sampleFrameCount(), WaveformPointCount)
        if not pointCount do
            return
        .waveform.samples.resize(pointCount)
        .waveformTask.submit(func|view = me|() { view.buildWaveformInBackground() }, .taskNotifier(&.waveformTask), .Background)
    }

    mtd syncWaveform()
    {
        let ready = .publishedWaveformCount()
        if ready == .waveform.readyCount do
            return
        .waveform.readyCount = ready
        .waveform.invalidate()
    }

    mtd refreshTransport()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, themeActionIconSize(.themeMetrics())))
        .playButton.toolTip = .playing ? texts().ui_TipPause : texts().ui_TipPlay
        .stopButton.enable(.voice != null)
        .timeline.setValueWithoutGesture(.elapsed)
        .timeLabel.setText(Viewer.timeRangeText(.elapsed, .duration))
        .waveform.progress = .duration > 0 ? .elapsed / .duration : 0
        .waveform.invalidate()
    }

    mtd ensureVoice()->bool
    {
        if .voice do
            return true
        catch
        {
            .voice = try Voice.create(&.sound)
            catch .voice.setVolume(.muted ? 0 : .volume)
            return true
        }

        return false
    }

    mtd seekSeconds(seconds: f32)
    {
        if not .engineReady or not .ensureVoice() do
            return
        let target = Math.clamp(seconds, 0, .duration)
        let frame  = cast(u64, Math.round(target * cast(f32, .sound.sampleRateHz())))
        catch .voice!.seekSampleFrame(frame)
        {
            return
        }

        .elapsed = target
        .refreshTransport()
    }

    // Gives the lens the transport and the sound of the recording.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let texts = appStrings()
        let ready = .playButton.isEnabled()
        entries.add(.playing ? texts.cmd_Pause : texts.cmd_Play, func|view = me|() { view.togglePlayback() }, disabled: not ready, shortcut: Input.formatKeyShortcut(.None, .Space))
        entries.add(texts.cmd_Stop, func|view = me|() { view.stopPlayback() }, disabled: not .stopButton.isEnabled())
        entries.add(texts.cmd_SeekBackward, func|view = me|() { view.seekRelative(-SeekSeconds) }, shortcut: Input.formatKeyShortcut(.None, .Left))
        entries.add(texts.cmd_SeekForward, func|view = me|() { view.seekRelative(SeekSeconds) }, shortcut: Input.formatKeyShortcut(.None, .Right))
        entries.add(texts.cmd_Mute, func|view = me|() { view.setMuted(not view.muted) }, checked: .muted, disabled: not .muteButton.isEnabled(), shortcut: Input.formatKeyShortcut(.None, .M))
    }

    mtd seekRelative(seconds: f32)
    {
        let current = .voice ? cast(f32, .voice.playbackPositionSeconds()) : .elapsed
        .seekSeconds(current + seconds)
    }

    mtd setMuted(muted: bool)
    {
        .muted = muted
        .muteButton.setChecked(muted)
        .muteButton.setIcon(.theme().icon(muted ? .VolumeMute : .Volume, themeActionIconSize(.themeMetrics())))
        if .voice do
            catch .voice.setVolume(muted ? 0 : .volume)
    }

    // Sets the playback volume, from 0 to 1, and shows it on the volume slider.
    mtd setVolume(volume: f32)
    {
        // The slider snaps to its step and reports the change back here, so it moves first and
        // the requested volume, not its snapped position, is the one kept.
        let requested = Math.clamp(volume, 0, 1)
        .volumeSlider.setValueWithoutGesture(requested)
        .volume = requested
        if .voice and not .muted do
            catch .voice.setVolume(.volume)
    }

    // Pauses or plays the sound, creating its voice on first use. Does nothing until the sound
    // engine is ready, or when the device refuses.
    mtd togglePlayback()
    {
        if not .engineReady or not .ensureVoice() do
            return

        if .playing
        {
            catch .voice!.pause()
            {
                return
            }

            .playing = false
        }
        else
        {
            catch .voice!.play()
            {
                return
            }

            .playing = true
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if .voice
        {
            catch .voice.stop()
            {
                return
            }
        }

        .playing = false
        .elapsed = 0
        .refreshTransport()
    }

    // Applies what the window's play mode calls for once the sound has been played through.
    //
    // Stopping rewinds the transport either way: a sound has no last picture to park on, and
    // one that is to be replayed starts again from its first sample.
    mtd finishPlayback()
    {
        let continuation = .services.finished(me)
        .stopPlayback()
        if continuation == .Replay do
            .togglePlayback()
    }
}

impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    // The host keeps a viewer the reader switched away from, to bring it back as it was, so a
    // hidden player pauses: neither its sound nor its end may go on behind another viewer.
    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind == .Hide and .playing do
            .togglePlayback()
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if evt.task != &.openTask or not .openTask.isDone()
        {
            evt.accepted = false
            return
        }

        if .retireRequested
        {
            discard catch .openTask.take()
            return
        }

        catch .completeOpen() { .services.failed(me, Viewer.failureText(Swag.err)) }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        if not .openFinished do
            return

        .syncWaveform()
        if not .playing or not .voice do
            return
        .elapsed = cast(f32, .voice.playbackPositionSeconds())
        if .elapsed >= .duration
        {
            .finishPlayback()
            return
        }

        .refreshTransport()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .retireBlocking()
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .waveform != null do
            .arrangeWave()
    }

    // Draws the cover, and under it the name of the recording and who made it, centered.
    //
    // The tags carry no picture yet, so the cover is a tile of the raised ground with the glyph
    // of a sound in it, lifted by the shadow of a floating surface.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let layout  = .pageLayout()
        let cover   = layout.cover

        painter.setParams(.Antialiased)
        .theme().drawFloatingShadow(painter, cover, CoverCorner)
        painter.fillRoundRect(cover, CoverCorner, CoverCorner, colors.raised)
        let glyph = .theme().icon(.Volume, 48)
        glyph.paint(painter, cover.horzCenter() - glyph.sizeX * 0.5, cover.vertCenter() - glyph.sizeY * 0.5, colors.faintText)

        let titleFont = .theme().createDefaultFont(TitleSize, .Bold)
        let title     = .title()
        var y         = layout.titleTop
        painter.drawString(Math.round((room.width - Painter.measureString(title, titleFont).width) * 0.5), y, title, titleFont, colors.text)
        y += titleFont.height + CreditGap

        let credits = .credits()
        if not credits.isEmpty()
        {
            let font = .theme().createDefaultFont(CreditSize)
            painter.drawString(Math.round((room.width - Painter.measureString(credits, font).width) * 0.5), y, credits, font, colors.softText)
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers != .None
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Space, .MediaPlayPause: .togglePlayback()
        case .Left:                   .seekRelative(-SeekSeconds)
        case .Right:                  .seekRelative(SeekSeconds)
        case .M, .VolumeMute:         .setMuted(not .muted)
        case .Up:                     .setVolume(Math.min(.volume + Viewer.VolumeStep, 1))
        case .Down:                   .setVolume(Math.max(.volume - Viewer.VolumeStep, 0))
        case .Home:                   .seekSeconds(0)
        case .MediaStop:              .stopPlayback()
        default:                      evt.accepted = false
        }
    }
}

impl Panel
{
    // Creates the transport in the command group: transport and seek buttons on the left, the
    // sound controls and the clock on the right, and the timeline between them.
    //
    // Every control starts disabled; opening the sound enables what the engine can serve.
    mtd createTransportBar()
    {
        with .playButton = Viewer.createActionButton(.commands, .Play)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_TipPlay
            .enable(false)
            .sigPressed += func|view = me|(_) { view.togglePlayback() }
        }

        with .stopButton = Viewer.createActionButton(.commands, .Stop)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipStop
            .enable(false)
            .sigPressed += func|view = me|(_) { view.stopPlayback() }
        }

        with .backwardButton = Viewer.createActionButton(.commands, .SeekBackward)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipBackward
            .enable(false)
            .sigPressed += func|view = me|(_) { view.seekRelative(-SeekSeconds) }
        }

        with .forwardButton = Viewer.createActionButton(.commands, .SeekForward)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipForward
            .enable(false)
            .sigPressed += func|view = me|(_) { view.seekRelative(SeekSeconds) }
        }

        with .volumeSlider = Slider.create(.commands, {0, 0, 96, 36})
        {
            .dockStyle = .Right
            .margin    = {8, 1, 0, 1}
            .toolTip   = texts().ui_TipVolume
            .setBounds(0, 1, 0.05)
            .setValueWithoutGesture(1)
            .enable(false)
            .sigChanged += func|view = me|(slider) { view.setVolume(slider.value()) }
        }

        with .muteButton = Viewer.createActionButton(.commands, .Volume, .Toggle)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .toolTip   = texts().ui_TipMute
            .setCheckIndicator(.Frame)
            .enable(false)
            .sigCheckedChanged += func|view = me|(button) { view.setMuted(button.isChecked) }
        }

        with .timeLabel = Label.create(.commands, "", {0, 0, 112, 36}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .setTextAlignment(.Right, .Center)
        }

        with .timeline = Slider.create(.commands, {0, 0, 0, 36})
        {
            .dockStyle = .Center
            .margin    = {12, 1, 12, 1}
            .toolTip   = texts().ui_TipSeek
            .enable(false)
            .sigEndChange += func|view = me|(slider) { view.seekSeconds(slider.value()) }
        }
    }

    // Builds the sound panel: commands, transport bar and waveform view, then opens the file in
    // the background.
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.sound")
        {
            .backgroundStyle = .View
            .services        = services
            .thumbnail       = host.isThumbnail()
        }

        result.commands = host.createCommandGroup(CommandWidth)
        result.createTransportBar()

        with result.waveform = Wnd.create'WaveformView(result, "scope.sound.waveform")
        {
            .panel = result
            .backgroundStyle = .Transparent
        }

        result.timer = result.addTimer(33'ms)
        result.refreshTransport()
        result.applyLayout()
        result.arrangeWave()
        result.setInitialFocus(result.playButton)
        result.openFileName = host.fileName()

        // A worker allocates with the default allocator, so the owned packet table it builds can
        // be handed to the GUI thread.
        let view = result
        result.openTask.submit(func|view|()->SoundFile fail
        {
            // The tags are read beside the sound, and the GUI thread reads neither until the
            // task has finished.
            view.tags = SoundTags.read(view.openFileName)
            return try SoundFile.load(view.openFileName, preloadData: false)
        },
                               result.taskNotifier(&result.openTask))
        return result
    }
}

// Creates the integrated sound playback and waveform view and connects it to the host.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setDetails(view.details)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    with var lifecycle: Viewer.LifecycleApi
    {
        .retire    = func|view|()->bool => view.retire()
        .isLoading = func|view|()->bool => view.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.needsLoadingOverlay()
    }

    host.setLifecycle(lifecycle)
}

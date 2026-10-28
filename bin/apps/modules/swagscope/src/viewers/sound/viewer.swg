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

    // Air around the plot, and the band the time scale is read in.
    const WaveformInsetX      = 24.0
    const WaveformInsetY      = 32.0
    const WaveformScaleHeight = 26.0
    const WaveformTickHeight  = 5.0
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

// Plots the waveform of a sound above its time scale, the played part apart from the rest.
struct WaveformView
{
    using wnd:  Wnd
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

// Returns the interval a time scale is graduated at, so the marks land on numbers a reader
// already thinks in rather than on an even division of whatever the duration happens to be.
func waveformTickStep(duration: f32, plotWidth: f32)->f32
{
    const Steps: [14] f32 = [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]

    // One mark every 120 pixels or so keeps the scale readable at any width, and each label needs
    // the room its own digits take.
    let wanted = duration * 120 / Math.max(plotWidth, 1)
    for step in Steps where step >= wanted do
        return step
    return Steps[Steps.count - 1]
}

// Formats one graduation of the time scale, in the shortest spelling its step allows.
func waveformTickText(seconds, step: f32)->String
{
    if seconds >= 60
    {
        let minutes = cast(u32, seconds / 60)
        let rest    = cast(u32, Math.round(seconds - cast(f32, minutes) * 60))
        return Format.toString("%:%{02}", minutes, rest)
    }

    if step < 1 do
        return Format.toString("%{f2}", seconds)
    return Format.toString("%", cast(u32, Math.round(seconds)))
}

private impl WaveformView
{
    // Returns the band the wave is drawn in, above the band the time scale is read in.
    mtd const plotRect()->Math.Rectangle
    {
        let rect = .clientRect()
        return Math.Rectangle{rect.x + WaveformInsetX,
                              rect.y + WaveformInsetY,
                              Math.max(rect.width - 2 * WaveformInsetX, 1),
                              Math.max(rect.height - 2 * WaveformInsetY - WaveformScaleHeight, 1)}
    }

    // Draws the graduated scale under the wave, skipping any mark whose label would touch the one
    // before it.
    mtd paintTimeScale(painter: *Painter, plot: Math.Rectangle)
    {
        if .duration <= 0 do
            return

        let font = .font().regular
        if not font do
            return

        let colors  = .themeColors()
        let step    = waveformTickStep(.duration, plot.width)
        let baseY   = plot.bottom()
        var written = plot.x - 1

        painter.drawLine(plot.x, baseY, plot.right(), baseY, colors.line, 1)

        var seconds = 0'f32
        while seconds <= .duration
        {
            let x = plot.x + plot.width * (seconds / .duration)
            painter.drawLine(x, baseY, x, baseY + WaveformTickHeight, colors.line, 1)

            // The last graduation is pulled back inside the plot rather than dropped: a scale that
            // stops naming its end reads as a scale that was cut off.
            let text  = waveformTickText(seconds, step)
            let width = Painter.measureString(text, font).width
            let left  = Math.min(x, plot.right() - width)
            if left > written
            {
                painter.drawString(left, baseY + WaveformTickHeight + 4, text, font, colors.label_TextFaint)
                written = left + width + 12
            }

            seconds += step
        }
    }
}

private impl IWnd for WaveformView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let plot    = .plotRect()
        let center  = plot.vertCenter()

        painter.setParams(.Antialiased)
        .paintTimeScale(painter, plot)

        // The silence line is under the wave, and only shows where the wave has nothing to say.
        painter.drawLine(plot.x, center, plot.right(), center, colors.line, 1)
        if .samples.isEmpty() do
            return

        // The alternate theme tone gives the sound its own voice while the signature accent stays
        // reserved for the exact play position. Two opacities preserve transient and body detail.
        let alternate = .theme().palette.alternate.mark
        let playBody  = Color.lerp(colors.view_Bk, alternate, 0.92)
        let playPeak  = Color.lerp(colors.view_Bk, alternate, 0.58)
        let restBody  = Color.lerp(colors.view_Bk, alternate, 0.48)
        let restPeak  = Color.lerp(colors.view_Bk, alternate, 0.25)

        let columns = cast(u64, Math.max(plot.width, 1))

        // Pixel alignment keeps the progress boundary crisp instead of blending two adjacent
        // waveform columns into a soft vertical seam.
        let playHead = Math.round(Math.clamp(.progress, 0, 1) * plot.width)
        let scale    = plot.height * 0.5 - 1

        for column in columns
        {
            let first = column * .samples.count / columns
            let last  = Math.max((column + 1) * .samples.count / columns, first + 1)
            if first >= .readyCount do
                continue
            var peak = 0'f32
            var body = 0'f32
            for index in first until Math.min(last, .readyCount)
            {
                peak = Math.max(peak, .samples[index].peak)
                body = Math.max(body, .samples[index].body)
            }

            // A slice of near silence still gets its pixel: a wave broken into a comb reads as a
            // rendering fault rather than as a quiet passage.
            let peakHeight = Math.max(peak * scale, 0.5)
            let bodyHeight = Math.max(body * scale, 0.5)
            let played     = cast(f32, column) < playHead
            let x          = plot.x + cast(f32, column)

            painter.fillRect(x, center - peakHeight, 1, peakHeight * 2, played ? playPeak : restPeak)
            painter.fillRect(x, center - bodyHeight, 1, bodyHeight * 2, played ? playBody : restBody)
        }

        // The play head is a rule, and it runs into the scale so the time it is at can be read.
        if .progress > 0
        {
            let x = plot.x + playHead
            painter.drawLine(x, plot.y, x, plot.bottom() + WaveformTickHeight, colors.signature, 1)
        }
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

    // Rebuilds the host summary in the active language and reports it.
    mtd refreshDetails()
    {
        let format = Format.toString(texts().ui_Details,
                                     .sound.sampleRateHz(),
                                     channelCountText(.sound.numChannels()),
                                     .sound.sampleStorageBits(),
                                     durationText(.duration))

        // What the recording is comes before how it is stored.
        var names: Array'string
        let artist = .tags.artist.isEmpty() ? .tags.albumArtist.toString() : .tags.artist.toString()
        for name in [.tags.title.toString(), artist, .tags.album.toString(), .tags.year.toString()] where name.count do
            names.add(name)
        .details.clear()
        for name in names
        {
            .details += name
            .details += " · "
        }

        .details += format
        .services.showDetails(me, .details)
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
            .dockStyle       = .Center
            .backgroundStyle = .View
        }

        result.timer = result.addTimer(33'ms)
        result.refreshTransport()
        result.applyLayout()
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

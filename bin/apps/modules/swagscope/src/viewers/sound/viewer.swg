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
        .thumbnail    = &loadThumbnail
        .smokeFixture = "pacman_beginning.wav"
    }

    let extensions = SoundFile.decodableExtensions()
    result.addSelectors(extensions.toSlice())
    return result
}

// Returns the sleeve the recording embeds, fitted within `maxSide`, or else draws a bounded
// waveform from the same PCM decoder and reducer as the sound viewer.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    var tags   = SoundTags.read(fileName, withPicture: true)
    var sleeve = embeddedSleeve(&tags, cast(s32, maxSide))
    if sleeve.isValid() do
        return sleeve

    let sound  = try SoundFile.load(fileName, preloadData: false)
    let width  = cast(s32, Math.max(Math.min(maxSide, 256'u32), 64'u32))
    let height = width / 2
    let frames = Math.min(sound.sampleFrameCount(), cast(u64, sound.sampleRateHz()) * 10)
    var canvas = try ImageCanvas.create(width, height)
    canvas.clear(Color.fromRgb(248, 249, 250))
    if not frames do
        return try canvas.toImage()

    var points: Array'WaveformPoint
    points.resize(Math.min(frames, cast(u64, width - 16)))
    var reducer = WaveformReducer{&points, frames, points.count, sound.numChannels()}
    try sound.decodePcm16(0, frames, func|reducer = &reducer|(samples: const [..] s16)->bool
    {
        reducer.consume(samples)
        return true
    })
    reducer.finish()

    let painter = &canvas.painter
    let middle  = cast(f32, height) * 0.5
    for point, index in points
    {
        let x    = 8 + cast(f32, index)
        let peak = Math.max(1'f32, point.peak * (middle - 8))
        let body = Math.max(1'f32, point.body * (middle - 8))
        painter.fillRect({x, middle - peak, 1, peak * 2}, Color.fromRgb(150, 165, 177))
        painter.fillRect({x, middle - body, 1, body * 2}, Color.fromRgb(48, 80, 104))
    }

    return try canvas.toImage()
}

private
{
    const SeekSeconds  = 10.0
    const CommandWidth = 720.0

    // Slices the payload is reduced to. It is read back one column of pixels at a time, so it only
    // has to stay ahead of the widest plot a window can give it; past that the columns repeat.
    const WaveformPointCount = 4096'u64

    // The page of a recording, after `scope.sound`: the cover, the name and who made it, then the
    // wave as a row of bars, with a band under it that keeps the bars clear of the transport.
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
    const TimesGap    = 14.0       // Air between the bars and the band under them.
    const TimesHeight = 26.0       // Height of the band under the bars.
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

// Formats the length of a sound for the host summary: milliseconds below one second, seconds with two decimals from there on.
func durationText(seconds: f32)->String
{
    if seconds < 1 do
        return Format.toString("% ms", cast(u32, Math.max(Math.round(seconds * 1000), 1)))
    return Format.toString("%{f2} s", seconds)
}

// Returns the established technical name of an audio payload encoding, the way the information
// sheets of a recording and of the sound tracks of a film write it.
func encodingText(encoding: SoundFileEncoding)->string
{
    switch encoding
    {
    case .Pcm8:     return "PCM 8-bit"
    case .Pcm16:    return "PCM 16-bit"
    case .Pcm24:    return "PCM 24-bit"
    case .Pcm32:    return "PCM 32-bit"
    case .Float32:  return "PCM float32"
    case .AacLc:    return "AAC-LC"
    case .Ac3:      return "AC-3"
    case .Eac3:     return "E-AC-3"
    case .Dts:      return "DTS"
    case .Flac:     return "FLAC"
    case .Mp3:      return "MP3"
    case .Vorbis:   return "Vorbis"
    case .Opus:     return "Opus"
    case .AdpcmMs:  return "ADPCM"
    case .AdpcmIma: return "IMA ADPCM"
    default:        return "Audio"
    }
}

// Plots the waveform of a sound as a row of bars, the played part apart from the rest.
struct WaveformView
{
    using wnd:  Wnd
    panel:      *Panel?     // Player the wave seeks, when a click chooses a place.
    samples:    Array'WaveformPoint
    readyCount: u64     // Points the builder has published so far.
    duration:   f32
    progress:   f32          // Played fraction, from 0 to 1.
    loopStart:  f32 = -1     // Fraction where the looped passage starts, negative without one.
    loopEnd:    f32 = -1     // Fraction where it ends, negative while only its start is set.
}

impl WaveformView
{
    // Returns how many bars the wave stands as across its width.
    mtd barCount()->u64 => cast(u64, Math.max(Math.floor((.clientRect().width + BarGap) / (BarWidth + BarGap)), 1))

    // Returns how many bars stand in Arc when `progress` of the recording has been played.
    mtd playedBars(progress: f32)->f32 => Math.ceil(Math.clamp(progress, 0, 1) * cast(f32, .barCount()))

    // Sets the played fraction, and repaints only when a bar changes color.
    mtd setProgress(progress: f32)
    {
        let repaint = .playedBars(progress) != .playedBars(.progress)
        .progress = progress
        if repaint do
            .invalidate()
    }
}

// Levels of a whole recording, measured on the 16-bit samples its waveform is built from.
struct SoundLevels
{
    peak:      u32             // Largest sample magnitude, 32,768 at full scale.
    squares:   f64             // Sum of the squared samples.
    samples:   u64             // Samples measured, every channel counted.
    fullScale: u64             // Samples at the top or bottom of the scale, where a louder signal clips.
    ceiling:   s16 = 32767     // Highest value the source can store, once widened to 16 bits.
}

impl SoundLevels
{
    // Folds one sample into the levels.
    #[Swag.Inline]
    mtd add(sample: s16)
    {
        let value     = cast(s32, sample)
        let magnitude = cast(u32, value < 0 ? -value : value)
        .peak    = Math.max(.peak, magnitude)
        .squares += cast(f64, value) * cast(f64, value)
        .samples += 1
        if sample == -32768 or sample >= .ceiling do
            .fullScale += 1
    }

    // Returns the sample peak in decibels below full scale.
    mtd const peakDecibels()->f64 => decibels(cast(f64, .peak) / 32768)

    // Returns the root mean square level in decibels below full scale.
    mtd const rmsDecibels()->f64 => .samples ? decibels(Math.sqrt(.squares / cast(f64, .samples)) / 32768) : decibels(0)
}

// Converts an amplitude relative to full scale into the `dBFS` reading the sheet writes, with
// one decimal; silence has no finite level.
func decibelsText(value: f64)->String
{
    if value == Swag.F64.NegInf do
        return String.from("−∞ dBFS")
    return Format.toString("%{f1} dBFS", value > -0.05 ? 0'f64 : value)
}

// Converts an amplitude relative to full scale into decibels; zero is minus infinity.
func decibels(amplitude: f64)->f64 => amplitude > 0 ? 20 * Math.log10(amplitude) : Swag.F64.NegInf

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
    levels:       SoundLevels
    nextBoundary: u64     // First frame past the current point; the target is only worked out again there.
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
            // Frame `f` belongs to point `f * pointCount / frameCount`, which only changes at the
            // boundary where that quotient grows, so it is worked out once per point, not per frame.
            if .frameOffset >= .nextBoundary
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

                // The last point takes every frame left, however many the decoder hands over.
                .nextBoundary = target + 1 < .pointCount ? ((target + 1) * .frameCount + .pointCount - 1) / .pointCount : Swag.U64.Max
            }

            var mixed = 0'f32
            for channel in .channels
            {
                let sample = samples[frame * .channels + channel]
                .levels.add(sample)
                mixed += cast(f32, sample) / 32768
            }

            let level = Math.abs(mixed / .channels)
            .peak        = Math.max(.peak, level)
            .sum         += level
            .sampleCount += 1
            .frameOffset += 1
        }
    }

    // Stores the point the last frames were folded into, which no later frame moved past.
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
    // Draws the wave as a row of bars, the played ones in Arc, over the band of a looped passage.
    // The times are the transport's to read.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let bars    = Math.Rectangle{room.x, room.y, room.width, WaveHeight}
        let center  = bars.vertCenter()
        let count   = .barCount()
        let played  = Math.clamp(.progress, 0, 1) * cast(f32, count)

        painter.setParams(.Antialiased)

        // A looped passage stands as a faint band behind its bars, its start alone as a line.
        if .loopStart >= 0
        {
            var band = colors.arc
            band.a = 48
            let left = bars.x + Math.clamp(.loopStart, 0, 1) * bars.width
            if .loopEnd > .loopStart do
                painter.fillRect(Math.Rectangle{left, bars.y, bars.x + Math.clamp(.loopEnd, 0, 1) * bars.width - left, bars.height}, band)
            else do
                painter.fillRect(Math.Rectangle{left, bars.y, 1, bars.height}, colors.arc)
        }

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
// Every output from background opening is returned together and installed on the GUI thread.
struct SoundOpenResult
{
    sound:           SoundFile
    tags:            SoundTags
    coverImage:      Image
    landmarks:       Array'Landmark
    landmarkWarning: bool
}

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
    openTask:     Swag.Task'SoundOpenResult
    openFinished: bool
    opened:       bool

    waveformTask:  Swag.Task
    waveformLock:  Swag.Mutex
    waveformBuilt: u64
    levels:        SoundLevels     // Written by the waveform worker; read once it has finished.
    levelsRead:    bool            // Whether the whole recording was measured, set with `levels`.
    levelsShown:   bool            // Whether the sheet has been told the levels are known.

    voice:        *Voice?
    timer:        *Timer?
    duration:     f32
    elapsed:      f32
    engineReady:  bool
    thumbnail:    bool
    playing:      bool
    muted:        bool
    volume:       f32 = 1
    playbackRate: f64 = 1      // Source seconds played per second; the pitch follows it.
    loopStart:    f32 = -1     // Second the looped passage starts at, negative without one.
    loopEnd:      f32 = -1     // Second it ends at, negative while only its start is set.

    landmarks:      Array'Landmark  // Read-only sidecar cues and markers made in this panel.
    landmarkWarning: bool           // A sidecar cue was malformed or outside this recording.
    sessionMarkerCount: u32          // Number used to name temporary markers in this session.
    backHistory:    Array'f32        // Bounded session-only seek destinations before the current one.
    forwardHistory: Array'f32       // Bounded session-only seek destinations after the current one.

    // What the transport last showed, so a tick that would not change it pushes nothing.
    clockSecond:   s64 = -1     // Whole second the clock was written at.
    timelinePixel: s32 = -1     // Pixel column the timeline thumb was pushed to.

    retireRequested: bool
    retired:         bool

    tags:       SoundTags     // Written by the open worker; read only once it has finished.
    coverImage: Image         // The sleeve found beside the file, decoded by the open worker.
    cover:      Texture       // That sleeve, uploaded once the open has finished.
    details:    String
    services:   Viewer.HostServices
}

impl Panel
{
    // Reports whether work remains whose result has not reached the waveform or the sheet yet.
    //
    // The worker can publish its last waveform point before it ends, so the waveform may look
    // complete while the levels it measures last are still unknown to the sheet.
    mtd isLoading()->bool
    {
        if not .openFinished do
            return true

        let built = .publishedWaveformCount()
        return .waveformTask.isPending() or
               .waveform.readyCount < built or
               (.waveform.samples.count != 0 and not .levelsShown)
    }

    // Reports whether the host should cover the view, which is until the sound has opened.
    mtd needsLoadingOverlay()->bool => not .openFinished or (.thumbnail and .isLoading())

    // Publishes the file opened in the background and initializes playback on the GUI thread.
    mtd completeOpen() fail
    {
        if .openFinished do
            return

        .openFinished = true
        var opened    = try .openTask.take()
        .sound        = #move opened.sound
        .tags         = #move opened.tags
        .coverImage   = #move opened.coverImage
        .landmarks    = #move opened.landmarks
        .landmarkWarning = opened.landmarkWarning
        .duration     = .sound.durationInSeconds()
        .validateSidecarLandmarks()
        if .coverImage.isValid() and not .thumbnail
        {
            .cover      = .app().renderer.addImage(.coverImage)
            .coverImage = {}
        }

        .opened   = true
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

        // An adjusted rate and a looped passage are part of what the reader hears, so the summary
        // declares them.
        if .playbackRate != 1 do
            .details = Format.toString("% · %", .details, Viewer.playbackRateText(.playbackRate))
        if .loopEnd > .loopStart and .loopStart >= 0 do
            .details = Format.toString("% · %", .details, Format.toString(texts().ui_Loop, Viewer.timeText(.loopStart), Viewer.timeText(.loopEnd)))
        if not .landmarks.isEmpty() do
            .details = Format.toString("% · %", .details, Format.toString(texts().ui_Landmarks, .landmarks.count))
        if .landmarkWarning do
            .details = Format.toString("% · %", .details, texts().ui_InvalidCues)
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

        // A source narrower than 16 bits is widened by shifting, so its top value sits lower.
        let storage = .sound.sampleStorageBits()
        reducer.levels.ceiling = storage < 16 ? cast(s16, 32767 - ((1 << (16 - storage)) - 1)) : 32767
        var decoded = true
        var published: u64
        catch .sound.decodePcm16(func|reducer = &reducer, published = &published, view = me|(samples: const [..] s16)->bool
        {
            reducer.consume(samples)
            if reducer.readyCount > published[]
            {
                view.publishWaveform(reducer.readyCount)
                published[] = reducer.readyCount
            }

            return not Swag.isCancelled()
        })
        {
            decoded = false
        }

        reducer.finish()
        if decoded and not Swag.isCancelled() and reducer.levels.samples
        {
            Sync.scopedLock(&.waveformLock)
            .levels     = reducer.levels
            .levelsRead = true
        }

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
        // Once the worker has measured the whole recording, the sheet can state its levels.
        if not .levelsShown and .waveform.samples.count and not .waveformTask.isPending()
        {
            .levelsShown = true
            .services.informationChanged(me)
        }

        let ready = .publishedWaveformCount()
        if ready == .waveform.readyCount do
            return
        .waveform.readyCount = ready
        .waveform.invalidate()
    }

    // Shows the state of the transport after a gesture or a change of state, then where playback stands.
    mtd refreshTransport()
    {
        // Changing the icon lays the command bar out again, so it is changed only with the state.
        let icon = .playing ? ThemeIcons.Pause : ThemeIcons.Play
        if .playButton.icon.index != cast(s32, icon)
        {
            .playButton.setIcon(.theme().icon(icon, themeActionIconSize(.themeMetrics())))
            .playButton.toolTip = .playing ? texts().ui_TipPause : texts().ui_TipPlay
        }

        .stopButton.enable(.voice != null)
        .clockSecond   = -1
        .timelinePixel = -1
        .refreshTime()
    }

    // Shows where playback stands: the clock, the timeline and the played part of the wave.
    //
    // The timer calls this thirty times a second while the sound plays, so each part is touched
    // only when it would visibly change: the clock once a second, the timeline when its thumb
    // reaches another pixel, and the wave when another bar is played.
    mtd refreshTime()
    {
        let second = cast(s64, Math.floor(Math.max(.elapsed, 0)))
        if second != .clockSecond
        {
            .clockSecond = second
            .timeLabel.setText(Viewer.timeRangeText(.elapsed, .duration))
        }

        let width = .timeline.position.width
        let pixel = .duration > 0 and width > 1 ? cast(s32, .elapsed / .duration * width) : -1
        if pixel < 0 or pixel != .timelinePixel
        {
            .timelinePixel = pixel
            .timeline.setValueWithoutGesture(.elapsed)
        }

        .waveform.setProgress(.duration > 0 ? .elapsed / .duration : 0)
    }

    mtd ensureVoice()->bool
    {
        if .voice do
            return true
        catch
        {
            .voice = try Voice.create(&.sound)
            catch .voice.setVolume(.muted ? 0 : .volume)
            if .playbackRate != 1 do
                catch .voice.setFrequencyRatio(cast(f32, .playbackRate))
            return true
        }

        return false
    }

    mtd seekSeconds(seconds: f32, remember = true)
    {
        if not .engineReady or not .ensureVoice() do
            return
        let origin = .playbackPosition()
        let target = Math.clamp(seconds, 0, .duration)
        let frame  = cast(u64, Math.round(target * cast(f32, .sound.sampleRateHz())))
        catch .voice!.seekSampleFrame(frame)
        {
            return
        }

        // The voice stops playing once it has handed the device its last buffer, a moment before
        // that buffer is heard, and a seek leaves a stopped voice where it lands. A jump made in
        // that moment, such as the return of a passage looped up to the end, would park the sound
        // while the transport still plays, so the voice is started again.
        if .playing and not .voice!.isPlaying()
        {
            catch .voice!.play()
            {
                .playing = false
            }
        }

        if remember and Math.abs(target - origin) >= 0.25 do
            .rememberNavigation(origin)
        .elapsed = target
        .refreshTransport()
    }

    // Retains only recent positions, in this panel's memory. Opening another file starts a new session.
    mtd rememberNavigation(seconds: f32)
    {
        if not .backHistory.isEmpty() and Math.abs(.backHistory.back() - seconds) < 0.25 do
            return
        if .backHistory.count >= 128 do
            .backHistory.removeAtOrdered(0)
        .backHistory.add(seconds)
        .forwardHistory.clear()
    }

    mtd navigateBack()
    {
        if .backHistory.isEmpty() do
            return
        if .forwardHistory.count >= 128 do
            .forwardHistory.removeAtOrdered(0)
        .forwardHistory.add(.playbackPosition())
        .seekSeconds(.backHistory.popBack(), remember: false)
    }

    mtd navigateForward()
    {
        if .forwardHistory.isEmpty() do
            return
        if .backHistory.count >= 128 do
            .backHistory.removeAtOrdered(0)
        .backHistory.add(.playbackPosition())
        .seekSeconds(.forwardHistory.popBack(), remember: false)
    }

    // Drops cue entries that do not belong to the decoded recording's audible timeline.
    mtd validateSidecarLandmarks()
    {
        var accepted: Array'Landmark
        var previous = -1'f32
        for &mark in .landmarks where mark.source == .Sidecar
        {
            if mark.seconds > .duration or mark.seconds < previous
            {
                .landmarkWarning = true
                continue
            }
            accepted.add(mark)
            previous = mark.seconds
        }
        .landmarks = #move accepted
    }

    mtd addSessionMarker()
    {
        let seconds = Math.clamp(.playbackPosition(), 0, .duration)
        for &mark in .landmarks where mark.source == .Session and Math.abs(mark.seconds - seconds) < 0.25
            do return
        .sessionMarkerCount += 1
        .landmarks.add(Landmark{seconds, Format.toString(texts().word_Marker, .sessionMarkerCount), .Session})
    }

    mtd seekLandmark(index: u64)
    {
        if index < .landmarks.count do
            .seekSeconds(.landmarks[index].seconds)
    }

    mtd seekPreviousLandmark()
    {
        var target = Swag.U64.Max
        var latest = -1'f32
        for mark, index in .landmarks where mark.seconds < .playbackPosition() - 0.05
        {
            if mark.seconds > latest
            {
                latest = mark.seconds
                target = index
            }
        }
        if target != Swag.U64.Max do
            .seekLandmark(target)
    }

    mtd seekNextLandmark()
    {
        var target = Swag.U64.Max
        var earliest = Swag.F32.Max
        for mark, index in .landmarks where mark.seconds > .playbackPosition() + 0.05
        {
            if mark.seconds < earliest
            {
                earliest = mark.seconds
                target = index
            }
        }
        if target != Swag.U64.Max do
            .seekLandmark(target)
    }

    // Validates a direct-time prompt against the captured playback position and recording length.
    // Capturing the origin keeps relative jumps stable while a modal is open over active playback.
    mtd createTimeDialog()->*EditDlg
    {
        let origin   = cast(f64, .playbackPosition())
        let duration = cast(f64, .duration)
        let initial  = Viewer.timeText(origin)
        with var options: EditDlgOptions
        {
            .title             = texts().cmd_GoToTime
            .message           = texts().ui_TimeHelp
            .text              = initial
            .confirmButtonText = texts().ui_Go
        }

        let dialog = EditDlg.createSingleLine(unwrap .surface, options)
        dialog.edit!.setValidator(func|origin, duration, dialog|(edit: *EditBox)->EditBoxCheckResult
        {
            let valid = Viewer.parseTimeAddress(edit.text(), origin, duration) >= 0
            dialog.setMessage(valid ? texts().ui_TimeHelp : texts().ui_TimeError)
            return valid ? .Valid : .InvalidVisible
        })
        dialog.validateResult = func|view = me, dialog, origin, duration|(_, result)->bool
        {
            if result != Dialog.BtnOk do
                return true
            let target = Viewer.parseTimeAddress(dialog.text(), origin, duration)
            if target < 0
            {
                discard dialog.edit!.revalidate()
                return false
            }

            view.seekSeconds(cast(f32, target))
            return true
        }

        return dialog
    }

    // Opens the prompt only for a playable recording; seeking leaves its paused/playing state in force.
    mtd promptGoToTime()
    {
        if not .surface or not .engineReady or .duration <= 0 do
            return
        discard .createTimeDialog().doModal()
    }

    // Gives the lens the transport and the sound of the recording.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let texts  = appStrings()
        let strings = Sound.texts()
        let ready = .playButton.isEnabled()

        // `:` and an instant, or a displacement in seconds, go there.
        if entries.results.prefix == .Line
        {
            let target = ready ? Viewer.parseTimeAddress(entries.query.toString(), cast(f64, .elapsed), cast(f64, .duration)) : -1
            if target >= 0
            {
                entries.add(Viewer.timeJumpText(target, entries.query.toString()), .GoTo, func|view = me, target|() { view.seekSeconds(cast(f32, target)) })
                return
            }
        }

        entries.add(.playing ? texts.cmd_Pause : texts.cmd_Play, .playing ? .Pause : .Play, func|view = me|() { view.togglePlayback() }, disabled: not ready, defaultKey: {modifiers: .None, key: .Space}, bindId: "scope.sound.playPause")
        entries.add(texts.cmd_Stop, .Stop, func|view = me|() { view.stopPlayback() }, disabled: not .stopButton.isEnabled(), bindId: "scope.sound.stop")
        entries.add(texts.cmd_SeekBackward, .SeekBackward, func|view = me|() { view.seekRelative(-SeekSeconds) }, defaultKey: {modifiers: .None, key: .Left}, bindId: "scope.sound.seekBackward")
        entries.add(texts.cmd_SeekForward, .SeekForward, func|view = me|() { view.seekRelative(SeekSeconds) }, defaultKey: {modifiers: .None, key: .Right}, bindId: "scope.sound.seekForward")
        entries.add(Sound.texts().cmd_GoToTime, .GoTo, func|view = me|() { view.promptGoToTime() }, disabled: not ready, defaultKey: {modifiers: .Control, key: .G}, bindId: "scope.sound.goToTime")
        entries.add(strings.cmd_NavigationBack, .GoTo, func|view = me|() { view.navigateBack() }, disabled: .backHistory.isEmpty(), bindId: "scope.sound.navigationBack")
        entries.add(strings.cmd_NavigationForward, .GoTo, func|view = me|() { view.navigateForward() }, disabled: .forwardHistory.isEmpty(), bindId: "scope.sound.navigationForward")
        entries.add(strings.cmd_PreviousLandmark, .GoTo, func|view = me|() { view.seekPreviousLandmark() }, disabled: .landmarks.isEmpty(), bindId: "scope.sound.previousLandmark")
        entries.add(strings.cmd_NextLandmark, .GoTo, func|view = me|() { view.seekNextLandmark() }, disabled: .landmarks.isEmpty(), bindId: "scope.sound.nextLandmark")
        entries.add(strings.cmd_AddMarker, .GoTo, func|view = me|() { view.addSessionMarker() }, disabled: not ready, bindId: "scope.sound.addMarker")
        for &mark, index in .landmarks
        {
            let title = Format.toString("% · % · %", mark.label, Viewer.timeText(mark.seconds), landmarkSourceText(mark.source))
            entries.add(title, .GoTo, func|view = me, index|() { view.seekLandmark(index) })
        }
        entries.add(texts.cmd_Mute, .VolumeMute, func|view = me|() { view.setMuted(not view.muted) }, checked: .muted, disabled: not .muteButton.isEnabled(), defaultKey: {modifiers: .None, key: .M}, bindId: "scope.sound.mute")

        // The rate is stepped like a film's, and the row reads the rate in force.
        let faster  = entries.add(strings.cmd_Faster, .PlaybackSpeed, func|view = me|() { view.setPlaybackRate(Viewer.playbackRateStep(view.playbackRate, 1)) }, disabled: .playbackRate >= Viewer.PlaybackRates[Viewer.PlaybackRates.count - 1], bindId: "scope.sound.faster")
        if faster do
            faster.detail = Format.toString("% · %", Viewer.playbackRateText(.playbackRate), Input.formatKeyShortcut(.Shift, .Right))
        let slower = entries.add(strings.cmd_Slower, .PlaybackSpeed, func|view = me|() { view.setPlaybackRate(Viewer.playbackRateStep(view.playbackRate, -1)) }, disabled: .playbackRate <= Viewer.PlaybackRates[0], bindId: "scope.sound.slower")
        if slower do
            slower.detail = Format.toString("% · %", Viewer.playbackRateText(.playbackRate), Input.formatKeyShortcut(.Shift, .Left))

        entries.add(Format.toString(texts.cmd_CopyTime, Viewer.timeText(cast(f64, .playbackPosition()))), .Copy, func|view = me|() { Clipboard.setString(Viewer.timeText(cast(f64, view.playbackPosition()))) }, disabled: not ready, bindId: "scope.sound.copyTime")

        // A passage is looped between two points the reader marks while listening.
        entries.add(strings.cmd_LoopStart, .RepeatAll, func|view = me|() { view.setLoopStart() }, disabled: not ready, defaultKey: {modifiers: .None, key: .Oem4}, bindId: "scope.sound.loopStart")
        entries.add(strings.cmd_LoopEnd, .RepeatAll, func|view = me|() { view.setLoopEnd() }, disabled: not ready, defaultKey: {modifiers: .None, key: .Oem6}, bindId: "scope.sound.loopEnd")
        if .loopStart >= 0 do
            entries.add(strings.cmd_LoopClear, .RepeatAll, func|view = me|() { view.clearLoop() }, bindId: "scope.sound.loopClear")
    }

    // Plays the recording at `rate` source seconds per second, the pitch following it. Positions
    // and times stay in source seconds: the voice reports where it is in the recording. A voice
    // that refuses the ratio keeps its own rate.
    mtd setPlaybackRate(rate: f64)
    {
        if rate == .playbackRate do
            return
        .playbackRate = rate
        if .voice do
            catch .voice.setFrequencyRatio(cast(f32, rate))
        .refreshDetails()
    }

    // Starts the looped passage where playback stands; an end before it no longer holds. A
    // recording that cannot play has no passage to repeat.
    mtd setLoopStart()
    {
        if not .engineReady do
            return
        .loopStart = .playbackPosition()
        if .loopEnd <= .loopStart do
            .loopEnd = -1
        .refreshLoop()
    }

    // Ends the looped passage where playback stands, from its start, or from the beginning when
    // none was set. A point at or before the start sets nothing.
    mtd setLoopEnd()
    {
        if not .engineReady do
            return
        let position = .playbackPosition()
        let start    = .loopStart >= 0 ? .loopStart : 0
        if position <= start do
            return
        .loopStart = start
        .loopEnd   = position
        .refreshLoop()
    }

    // Plays the recording through again, without a looped passage.
    mtd clearLoop()
    {
        .loopStart = -1
        .loopEnd   = -1
        .refreshLoop()
    }

    // Shows the looped passage on the wave and in the summary.
    mtd refreshLoop()
    {
        let length = Math.max(.duration, 0.001)
        .waveform.loopStart = .loopStart >= 0 ? .loopStart / length : -1
        .waveform.loopEnd   = .loopEnd >= 0 ? .loopEnd / length : -1
        .waveform.invalidate()
        .refreshDetails()
    }

    // Plays a looped passage again from its start once playback has reached its end; reports
    // whether it did.
    mtd followLoop()->bool
    {
        if .loopStart < 0 or .loopEnd <= .loopStart or .elapsed < .loopEnd do
            return false
        .seekSeconds(.loopStart)
        return true
    }

    // Returns where playback stands in the recording, in seconds.
    mtd playbackPosition()->f32 => .voice ? cast(f32, .voice.playbackPositionSeconds()) : .elapsed

    mtd seekRelative(seconds: f32) => .seekSeconds(.playbackPosition() + seconds)

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

        if .followLoop() do
            return

        if .elapsed >= .duration
        {
            .finishPlayback()
            return
        }

        .refreshTime()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .retireBlocking()
        if .cover.isValid() do
            .app().renderer.removeTexture(&.cover)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .waveform != null do
            .arrangeWave()
    }

    // Draws the cover, and under it the name of the recording and who made it, centered.
    //
    // The cover is the sleeve stored beside the file, cropped square, lifted by the shadow of a
    // floating surface. Without one it is a neutral sleeve: the rings of a record on the raised
    // ground, as the explorer draws an album without artwork.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let layout  = .pageLayout()
        let cover   = layout.cover

        painter.setParams(.Antialiased)
        .theme().drawFloatingShadow(painter, cover, CoverCorner)
        if .cover.isValid()
        {
            let width  = cast(f32, .cover.width)
            let height = cast(f32, .cover.height)
            let side   = Math.min(width, height)
            var brush  = Brush.createTexture(.cover)
            brush.uvMode = .FillSubRect
            brush.uvRect = Math.Rectangle{(width - side) * 0.5, (height - side) * 0.5, side, side}
            painter.fillRoundRect(cover, CoverCorner, CoverCorner, brush)
        }
        else
        {
            painter.fillRoundRect(cover, CoverCorner, CoverCorner, colors.raised)
            let center = Math.Point{cover.horzCenter(), cover.vertCenter()}
            let radius = cover.width * 0.32
            painter.drawCircle(center.x, center.y, radius, colors.faintText, 1.5)
            painter.drawCircle(center.x, center.y, radius * 0.68, colors.line)
            painter.fillCircle(center.x, center.y, 5, colors.softText)
        }

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
        if evt.kind == .Pressed and evt.modifiers == .Control and evt.key == .G
        {
            .promptGoToTime()
            return
        }

        if evt.kind == .Pressed and evt.modifiers == .Alt and evt.key == .Left
        {
            .navigateBack()
            return
        }
        if evt.kind == .Pressed and evt.modifiers == .Alt and evt.key == .Right
        {
            .navigateForward()
            return
        }

        // Shift and an arrow step the rate, as they do over a film.
        if evt.kind == .Pressed and evt.modifiers == .Shift and (evt.key == .Left or evt.key == .Right)
        {
            .setPlaybackRate(Viewer.playbackRateStep(.playbackRate, evt.key == .Right ? 1 : -1))
            return
        }

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
        case .Oem4:                   .setLoopStart()
        case .Oem6:                   .setLoopEnd()
        case .MediaStop:              .stopPlayback()
        default:                      evt.accepted = false
        }
    }
}

impl Panel
{
    // Uses the shared media arrangement: timeline above, play and clock at the left,
    // secondary transport after them, and sound controls at the right.
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
            .setCheckIndicator(.Ink)
            .enable(false)
            .sigCheckedChanged += func|view = me|(button) { view.setMuted(button.isChecked) }
        }

        with .timeLabel = Label.create(.commands, "", {0, 0, 128, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .margin.x  = 12
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with .timeline = Slider.create(.commands, {0, 0, 0, 28})
        {
            .dockStyle = .Top
            .margin    = {12, 0, 12, 8}
            .toolTip   = texts().ui_TipSeek
            .enable(false)
            .sigEndChange += func|view = me|(slider) { view.seekSeconds(slider.value()) }
        }

        .timeLabel.sendToBack()
        .playButton.sendToBack()
        .timeline.sendToBack()
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
        result.commands.resize(CommandWidth, 72)
        result.createTransportBar()
        result.commands.hookOnEvent = func|view = result|(_, evt)->bool
        {
            if evt is ResizeEvent
            {
                let width = view.commands.position.width
                view.volumeSlider.show(width >= 580)
                view.stopButton.show(width >= 520)
                view.backwardButton.show(width >= 520)
                view.forwardButton.show(width >= 520)
            }

            return false
        }

        with result.waveform = Wnd.create'WaveformView(result, "scope.sound.waveform")
        {
            .panel = result
            .backgroundStyle = .Transparent
        }

        result.timer = result.addTimer(33'ms)
        result.refreshTransport()
        result.applyLayout()
        result.arrangeWave()
        result.openFileName = host.fileName()

        // A worker allocates with the default allocator, so the owned packet table it builds can
        // be handed to the GUI thread.
        let view = result
        result.openTask.submit(func|view|()->SoundOpenResult fail
        {
            var opened: SoundOpenResult
            opened.tags = SoundTags.read(view.openFileName, withPicture: true)
            let cueSidecar = readCueSidecar(view.openFileName)
            opened.landmarks = #move cueSidecar.markers
            opened.landmarkWarning = cueSidecar.invalid
            opened.coverImage = embeddedSleeve(&opened.tags)
            if not opened.coverImage.isValid() do
                opened.coverImage = localSleeve(view.openFileName)
            opened.sound = try SoundFile.load(view.openFileName, preloadData: false)
            return opened
        },
                               result.taskNotifier(&result.openTask))
        return result
    }
}

// Creates the integrated sound playback and waveform view and connects it to the host.
impl Panel
{
    // Describes the recording in the information sheet: its length, then how it is stored.
    mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        if .duration > 0 do
            data.addFigure(.Duration, durationText(.duration))
        data.add(.Sound, group: true)

        // How the samples are stored, then the throughput of that payload over the length.
        data.add(.Format, encodingText(.sound.sampleEncoding()))
        let bitrate = videoBitrate(.sound.payloadSize(), cast(f64, .duration))
        if bitrate.count do
            data.add(.Bitrate, bitrate)
        data.add(.SampleRate, Format.toString("% Hz", .sound.sampleRateHz()))
        data.add(.Channels, channelsText(cast(u32, .sound.numChannels())))
        data.add(.SampleSize, Format.toString("% bit", .sound.sampleStorageBits()))

        // What the tags of the file say of the recording, as they spell it.
        if .openFinished and not .tags.isEmpty()
        {
            data.add(.Tags, group: true)
            for row in [{field: MediaInfoField.Title, value: .tags.title.toString()}, {field: MediaInfoField.Artist, value: .tags.artist.toString()},
                        {field: MediaInfoField.Album, value: .tags.album.toString()}, {field: MediaInfoField.AlbumArtist, value: .tags.albumArtist.toString()},
                        {field: MediaInfoField.Year, value: .tags.year.toString()}, {field: MediaInfoField.TrackNumber, value: .tags.track.toString()},
                        {field: MediaInfoField.Disc, value: .tags.disc.toString()}, {field: MediaInfoField.Genre, value: .tags.genre.toString()}] where row.value.count do
                data.add(row.field, row.value)
        }

        // The levels are known once the waveform worker has read every sample.
        if .levelsShown and .levelsRead
        {
            data.add(.Levels, group: true)
            data.add(.SamplePeak, decibelsText(.levels.peakDecibels()))
            data.add(.RmsLevel, decibelsText(.levels.rmsDecibels()))
            data.add(.FullScale, sampleCountText(.levels.fullScale))
        }

        data.describe(sheet)
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setDetails(view.details)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    with var lifecycle: Viewer.LifecycleApi
    {
        .retire    = func|view|()->bool => view.retire()
        .isLoading = func|view|()->bool => view.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.needsLoadingOverlay()
    }

    host.setLifecycle(lifecycle)
}

// Brings `image` down to `side`, by default twice the side of the cover, which is all the page
// ever draws of it.
private func fitSleeve(image: *Image, side = cast(s32, CoverSize * 2))
{
    let largest = Math.max(image.width, image.height)
    if largest <= side do
        return
    let scale = cast(f32, side) / cast(f32, largest)
    image.resize(Math.max(1, cast(s32, cast(f32, image.width) * scale)), Math.max(1, cast(s32, cast(f32, image.height) * scale)), .Bilinear)
}

// Returns the sleeve the recording's own tags embed, decoded and fitted, or an invalid image when
// they embed none or it does not decode. The encoded picture is released either way. `side`
// bounds the result, by default to what the page draws.
func embeddedSleeve(tags: *SoundTags, side = cast(s32, CoverSize * 2))->Image
{
    var result: Image
    if not tags.picture.isEmpty()
    {
        result = catch Image.decode(tags.pictureExtension.toString(), tags.picture.toSlice()) orelse {}
        if result.isValid() do
            fitSleeve(&result, side)
    }

    tags.picture.clear()
    return result
}

// Returns the sleeve stored beside `fileName` — `cover`, `folder` or `front`, in JPEG or PNG —
// decoded and fitted, or an invalid image when there is none. A sleeve the recording embeds
// comes first; this one is shared by the folder.
func localSleeve(fileName: string)->Image
{
    const MaxBytes = 16'u64 * 1024 * 1024
    let folder = Path.directoryName(fileName) orelse ""
    for name in ["cover.jpg", "folder.jpg", "front.jpg", "cover.png", "folder.png", "front.png"]
    {
        let candidate = Path.combine(folder, name)
        if not File.exists(candidate) do
            continue
        let info = catch File.info(candidate) { continue }
        if info.size > MaxBytes do
            continue
        var image = catch Image.load(candidate) { continue }
        fitSleeve(&image)
        return image
    }

    return {}
}

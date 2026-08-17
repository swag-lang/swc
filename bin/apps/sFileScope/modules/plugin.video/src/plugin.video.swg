#global public

using Core, Pixel, Gui, Video

private const VideoGlyphSize = 18.0
private const VideoCommandWidth = 350.0

internal struct VideoPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:   *Wnd
        playButton: *IconButton
        stopButton: *IconButton
        timeline:   *Slider
        frameLabel: *Label
        imageView:  *ImageView
    }

    video:      Clip
    timer:      #null *Timer
    clock:      Time.Stopwatch
    elapsed:    f64
    frameIndex: u64
    playing:    bool
    details:    String
}

internal impl VideoPluginView
{
    mtd frameSeconds(index: u64)->f64
    {
        return cast(f64) index * cast(f64) .video.frameRate().denominator() / cast(f64) .video.frameRate().numerator()
    }

    mtd currentSeconds()->f64
    {
        if !.playing do
            return .elapsed
        return .elapsed + cast(f64) .clock.elapsedMicroseconds() / 1_000_000.0
    }

    mtd refreshTransport()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, VideoGlyphSize))
        .playButton.toolTip = .playing ? videoStrings().ui_TipPause : videoStrings().ui_TipPlay
        .stopButton.enable(.frameIndex != 0 or .playing)
        .timeline.setValueWithoutGesture(cast(f32) .frameIndex)
        .frameLabel.setText(Format.toString("% / %", .frameIndex + 1, .video.frameCount()))
    }

    mtd showFrame(index: u64)->bool
    {
        if index >= .video.frameCount() do
            return false
        let frame = catch .video.decodeFrame(index) as decodeError
        if decodeError != null do
            return false
        .frameIndex = index
        .imageView.setImage(frame)
        .refreshTransport()
        return true
    }

    mtd seekFrame(index: u64)
    {
        if !.video.frameCount() do
            return
        let target = Math.min(index, .video.frameCount() - 1)
        if !.showFrame(target) do
            return
        .elapsed = .frameSeconds(target)
        if .playing do
            .clock.restart()
    }

    mtd togglePlayback()
    {
        if !.video.frameCount() do
            return
        if .playing
        {
            .elapsed = .currentSeconds()
            .clock.reset()
            .playing = false
        }
        else
        {
            if .frameIndex + 1 >= .video.frameCount()
            {
                .elapsed = 0
                discard .showFrame(0)
            }

            .clock.restart()
            .playing = true
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if !.video.frameCount() do
            return
        .playing = false
        .elapsed = 0
        .clock.reset()
        discard .showFrame(0)
        .refreshTransport()
    }

    mtd updatePlayback()
    {
        if !.playing do
            return

        let seconds = .currentSeconds()
        let rate    = .video.frameRate()
        let target  = cast(u64) (seconds * cast(f64) rate.numerator() / cast(f64) rate.denominator())
        if target >= .video.frameCount()
        {
            .playing = false
            .elapsed = .video.durationInSeconds()
            .clock.reset()
            discard .showFrame(.video.frameCount() - 1)
            .refreshTransport()
            return
        }

        if target != .frameIndex and !.showFrame(target)
        {
            .playing = false
            .clock.reset()
            .refreshTransport()
        }
    }

    mtd showDecodeError(error: #null any)
    {
        .imageView.hide()
        .playButton.enable(false)
        .stopButton.enable(false)
        .timeline.enable(false)

        with let stack = StackLayoutCtrl.create(me, .VerticalCenter)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .spacing   = 8

            with let summary = Label.create(stack, videoStrings().ui_ErrDecode, flags: .WordWrap | .AutoHeight | .SecondaryText)
            {
                .setTextAlignment(.Center, .Center)
            }

            with let detail = Label.create(stack, Errors.message(error), flags: .WordWrap | .AutoHeight)
            {
                .setTextAlignment(.Center, .Center)
                .setTextColor(.themeColors().embInfo_CriticalText)
            }
        }
    }
}

private impl IWnd for VideoPluginView
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        .updatePlayback()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        if .timer
        {
            .removeTimer(.timer!)
            .timer = null
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .Space do
            .togglePlayback()
        else do
            evt.accepted = false
    }
}

private impl VideoPluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*VideoPluginView
    {
        registerVideoStrings(contentParent.app())
        let result = Wnd.create'VideoPluginView(contentParent, "sFileScope.video")
        result.backgroundStyle = .View

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, VideoCommandWidth, 36})
        {
            .backgroundStyle = .Window
        }

        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Play, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = videoStrings().ui_TipPlay
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.togglePlayback()
            }
        }

        with result.stopButton = IconButton.create(result.commands, result.theme().icon(.Stop, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = videoStrings().ui_TipStop
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        with result.timeline = Slider.create(result.commands, {0, 0, 180, 36})
        {
            .dockStyle  = .Left
            .margin     = {8, 1, 8, 1}
            .toolTip    = videoStrings().ui_TipSeek
            .sigChanged += func|view = result|(slider)
            {
                view.seekFrame(cast(u64) Math.round(slider.value()))
            }
        }

        with result.frameLabel = Label.create(result.commands, "", {0, 0, 74, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Right, .Center)
        }

        result.imageView           = ImageView.create(result)
        result.imageView.dockStyle = .Center

        let video = catch Clip.load(fileName) as loadError
        if loadError != null
        {
            result.details = videoStrings().ui_DetailsError
            result.showDecodeError(loadError)
            result.applyLayout()
            return result
        }

        result.video = #move video
        result.timeline.setBounds(0, cast(f32) result.video.frameCount() - 1, 1)
        if !result.showFrame(0)
        {
            result.details = videoStrings().ui_DetailsError
            result.showDecodeError(Errors.InvalidFormatError{"YUV4MPEG2 first frame could not be decoded"})
            result.applyLayout()
            return result
        }

        result.details = Format.toString(videoStrings().ui_Details, result.video.width(), result.video.height(), videoFrameCountText(result.video.frameCount()), result.video.frameRate().framesPerSecond(), result.video.durationInSeconds())
        result.timer   = result.addTimer(10'ms)
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        return result
    }
}

// Creates the YUV4MPEG2 playback view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    let view = VideoPluginView.create(request.contentParent, request.commandParent, request.fileName)
    result.view     = view
    result.commands = view.commands
    result.details  = view.details
    return true
}

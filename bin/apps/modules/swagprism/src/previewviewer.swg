#global internal

using Core, Gui, Pixel

/*
The program the source builds, running: a picture a `shade` function paints, or the interface a
`buildView` function builds.

The frame takes the width of its column, with the live-edit switch and the size of the frame under
it; the timings of the build and of a frame are the viewer's reading. When the build stops, the
compiler's words take the frame's place.

Both execution viewers share transport and lifecycle, but each compiles its own entry contract.
*/
struct PreviewViewer
{
    using wnd: Wnd

    late
    {
        probe:        *Pipeline.PreviewProbe
        panel:        *ViewerPanel
        cache:        *Pipeline.CompilationCache
        sourceEditor: *RichEditCtrl
        canvas:       *PreviewCanvas
        output:       *ListingView
        liveSwitch:   *ToggleButton
        liveLabel:    *Label
    }

    gui:        bool
    paused:     bool
    running:    bool
    queued:     bool
    timer:      *Timer?
    preparing:  *Pipeline.PreviewProbe?
    retired:    Array'*Pipeline.PreviewProbe
    source:     String
    pending:    Pipeline.BuildRequest
    request:    Pipeline.BuildRequest
    generation: u64
    image:      Image
    frameCount: u32
    renderUs:   u32
    sigChanged: SigArray'func||(*Wnd)
}

impl PreviewViewer
{
    const RowHeight = 28.0     // The row of the live-edit switch and the size of the frame.
    const RowGap    = 16.0     // Air between the frame and that row.

    // Builds a preview of the native renderer or of a GUI: a canvas for the frames, a listing
    // for the diagnostics, and the live-edit switch.
    func create(parent: *ViewerPanel, editor: *RichEditCtrl, gui: bool)->*PreviewViewer
    {
        with let result = Wnd.create'PreviewViewer(parent, "prism.preview")
        {
            .backgroundStyle = .Transparent
            .probe           = Memory.new'Pipeline.PreviewProbe()
            .panel           = parent
            .cache           = parent.cache
            .sourceEditor    = editor
            .gui             = gui
        }

        with result.canvas = Wnd.create'PreviewCanvas(result, "prism.preview.canvas")
        {
            .backgroundStyle = .Transparent
            .sigClick        += func|viewer = result|(point) { viewer.forwardClick(point) }
        }

        result.output = ListingView.create(result, "prism.preview.output")
        with result.liveSwitch = ToggleButton.create(result, {0, 0, 34, 20}, "prism.preview.live")
        {
            .setChecked(true)
            .sigChanged += func|viewer = result|(_) { viewer.panel.sigLiveEditChanged.call(viewer.liveSwitch.isChecked()) }
        }

        with result.liveLabel = Label.create(result, "", {}, null, .SecondaryText)
        {
            .setTextAlignment(.Left, .Center)
        }

        result.canvas.hide()
        result.image = Image.create(Pipeline.FrameChannel.Width, Pipeline.FrameChannel.Height, .BGRA8)
        result.retranslate()
        return result
    }

    // Shows whether the source compiles again after each edit.
    mtd setLiveEdit(on: bool) => .liveSwitch.setChecked(on)

    // Places the frame at the top of the column, the switch and the size of the frame under it,
    // and the diagnostics in the frame's place.
    mtd arrangeParts()
    {
        // The viewer lays itself out while its parts are still being created.
        if .liveLabel == null do
            return

        let client = .clientRect()
        let above  = Math.max(0'f32, client.height - RowHeight - RowGap)
        .canvas.setPosition(Math.Rectangle{0, 0, client.width, above})
        .output.scroll.setPosition(Math.Rectangle{0, 0, client.width, above})

        let frame   = .canvas.frameRect()
        let rowTop  = .canvas.isLocallyVisible() ? frame.bottom() + RowGap : above + RowGap
        let rowLeft = .canvas.isLocallyVisible() ? frame.x : 0
        .liveSwitch.setPosition(Math.Rectangle{rowLeft, rowTop + (RowHeight - 20) * 0.5, 34, 20})
        .liveLabel.setPosition(Math.Rectangle{rowLeft + 44, rowTop, Math.max(0'f32, client.width - rowLeft - 44), RowHeight})
    }

    // Hands a click on the frame to the interface running in the child process.
    //
    // The child takes one click at a time: a click arriving before it has replayed the previous one
    // is dropped rather than overwriting coordinates it may be reading.
    mtd forwardClick(point: Math.Point)
    {
        if not .gui or .paused or not .running or not Atomic.get(&.probe.ready) do
            return
        let header = .probe.channel.header()
        let click  = Atomic.get(&header.click)
        if click != Atomic.get(&header.clicked) do
            return
        header.clickX = cast(u32, point.x)
        header.clickY = cast(u32, point.y)
        Atomic.exchange(&header.click, click + 1)
    }

    // Compiles `source` with this viewer's panel settings.
    mtd compileSource(source: string) { .compileRequest(.panel.request(source)) }

    // Reports whether the live preview already runs `request`, built from the current cache and not
    // on its way out. Editing another panel need not restart an unchanged live preview.
    mtd alreadyRuns(request: Pipeline.BuildRequest)->bool
    {
        return .running and
               not .probe.isCancelled() and
               (not .preparing or not .preparing.isCancelled()) and
               .generation == .cache.generation and
               .request.kind == request.kind and
               .request.sameProgram(request)
    }

    // Starts `request`, or queues it behind the build in progress; a running animation keeps
    // playing until its replacement has a first frame.
    mtd compileRequest(request: Pipeline.BuildRequest)
    {
        if .alreadyRuns(request) do
            return
        .pending = request
        if .preparing
        {
            .queued = true
            .preparing.cancel()
            return
        }

        if .running and .frameCount
        {
            .startReplacement()
            return
        }

        if .running
        {
            .queued = true
            .probe.cancel()
            return
        }

        .start()
    }

    // Builds the pending request in a second probe, while the current animation keeps running.
    mtd startReplacement()
    {
        .request    = .pending
        .source     = .request.source
        .generation = .cache.generation
        .queued     = true
        .preparing  = Memory.new'Pipeline.PreviewProbe()
        .preparing.start(.request, .cache)
        .sigChanged.call(me)
    }

    // Builds and runs the pending request in a fresh probe, and starts polling for frames.
    mtd start()
    {
        Memory.delete(.probe)
        .probe      = Memory.new'Pipeline.PreviewProbe()
        .request    = .pending
        .generation = .cache.generation
        .source     = .request.source
        .queued     = false
        .running    = true
        .frameCount = 0
        if not .timer do
            .timer = .addTimer(16'ms)
        .probe.start(.request, .cache)
        .sigChanged.call(me)
    }

    // Workers reap old children off the UI thread. Their mappings remain owned until the join.
    mtd collectRetired()
    {
        for index in reversed(.retired.count) where .retired[index].task.isDone()
        {
            Memory.delete(.retired[index])
            .retired.removeAtOrdered(index)
        }
    }

    // Replaces the frame with the diagnostics of a build that did not run.
    mtd showDiagnostics(diagnostics: string)
    {
        .output.showOutput(diagnostics)
        .output.scroll.show()
        .canvas.hide()
        .arrangeParts()
    }

    // Advances the preview at each timer tick: swaps in a replacement that has its first frame,
    // reports a failed build, restarts a queued request, and copies the newest frame to the canvas.
    mtd poll()
    {
        .collectRetired()
        if .preparing
        {
            let candidate = .preparing
            if candidate.task.isDone()
            {
                .preparing = null
                if candidate.isCancelled()
                {
                    Memory.delete(candidate)
                    .startReplacement()
                }
                else
                {
                    .queued = false
                    .showDiagnostics(candidate.diagnostics)
                    Memory.delete(candidate)
                    .sigChanged.call(me)
                }
            }
            elif not candidate.isCancelled() and
                 Atomic.get(&candidate.ready) and
                 Atomic.get(&candidate.channel.header().published)
            {
                // Keep the previous animation alive until the replacement has a complete frame.
                .probe.cancel()
                .retired.add(.probe)
                .probe      = candidate
                .preparing  = null
                .running    = true
                .queued     = false
                .frameCount = 0
            }
        }

        if .probe.task.isDone()
        {
            if .preparing do
                return
            .stopTimer(&.timer)
            .running = false
            if .queued
            {
                .start()
                return
            }

            if .probe.failed do
                .showDiagnostics(.probe.diagnostics)
            .sigChanged.call(me)
            return
        }

        if not Atomic.get(&.probe.ready) or (.paused and .frameCount != 0) or not .isVisible() do
            return
        let header = .probe.channel.header()
        let frame  = Atomic.get(&header.published)
        if frame == Atomic.get(&header.consumed) do
            return
        Memory.copy(.image.pixels.storage(), .probe.channel.pixels(), Pipeline.FrameChannel.ByteCount)
        .renderUs = header.renderUs
        let firstFrame = .frameCount == 0
        .frameCount = frame
        .probe.channel.acknowledge(frame)
        .canvas.update(&.image)
        if firstFrame
        {
            .output.scroll.hide()
            .canvas.show()
            .arrangeParts()
        }

        // The timings are read again every few frames, not at each one.
        if firstFrame or .frameCount % 15 == 0 do
            .sigChanged.call(me)
    }

    // Cancels every probe, waits for their workers, and closes the frame channel.
    mtd stop()
    {
        .probe.cancel()
        if .preparing
        {
            .preparing.cancel()
            .retired.add(.preparing)
            .preparing = null
        }

        for probe in .retired do
            probe.cancel()
        .probe.task.wait()
        for probe in .retired
        {
            probe.task.wait()
            Memory.delete(probe)
        }

        .retired.clear()

        .stopTimer(&.timer)
        .running = false
        .queued  = false
        .probe.channel.close()
    }

    // Returns the build and frame times of the running preview, or why it is not running.
    mtd statusReading()->String
    {
        if .running and .frameCount
        {
            if .probe.reused do
                return Format.toString(appStrings().ui_ReusedStats, .renderUs)
            return Format.toString(appStrings().ui_LiveStats, .probe.compileMs, .renderUs)
        }

        if .running do
            return appStrings().ui_Working
        if .probe.failed do
            return appStrings().ui_Stopped
        return {}
    }

    // Writes the hint shown before the first run and the words of the switch in the active
    // language.
    mtd retranslate()
    {
        if not .running and not .probe.failed and not .frameCount do
            .output.showHint(Format.toString("%\n\n%",
                                             .gui ? appStrings().ui_GuiHint : appStrings().ui_RenderHint,
                                             appStrings().ui_ChooseExample))
        .liveLabel.setText(appStrings().cmd_LiveEdit)
        .arrangeParts()
    }
}

impl IViewer for PreviewViewer
{
    mtd impl window()->*Wnd => &.wnd
    mtd impl compile(request: Pipeline.BuildRequest) { .compileRequest(request) }
    mtd impl inspects()->bool => false
    mtd impl isPaused()->bool => .paused
    mtd impl setPaused(paused: bool) { .paused = paused }
    mtd impl shutdown() { .stop() }
    mtd impl isRunning()->bool => .preparing != null or (.running and (not .frameCount or .queued))
    mtd impl reading()->String => .statusReading()
    mtd impl subscribeChanged(action: func||(*Wnd)) { .sigChanged += action }
}

impl IWnd for PreviewViewer
{
    // Writes the size of the frame at the end of the row of the switch, as a measure.
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .canvas.isLocallyVisible() do
            return
        let painter = evt.paintContext.painter
        let font    = .theme().createDefaultFontFs(.themeMetrics().hintLine_FontSize)
        let frame   = .canvas.frameRect()
        let size    = Format.toString("% × %", Pipeline.FrameChannel.Width, Pipeline.FrameChannel.Height)
        let width   = Painter.measureString(size, font).width
        let centerY = frame.bottom() + RowGap + RowHeight * 0.5
        painter.drawString(frame.right() - width, font.opticalLineTop(centerY), size, font, .themeColors().faintText)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrangeParts()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .timer do
            .poll()
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stop()
        Memory.delete(.probe)
        .wnd.IWnd.onDestroyEvent(evt)
    }
}

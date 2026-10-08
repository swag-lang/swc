#global internal

using Core, Gui, Pixel

// Both execution viewers share transport and lifecycle, but each compiles its own entry contract.
struct PreviewViewer
{
    using wnd: Wnd

    late
    {
        probe:        *Pipeline.PreviewProbe
        panel:        *ViewerPanel
        cache:        *Pipeline.CompilationCache
        sourceEditor: *RichEditCtrl
        status:       *Label
        canvas:       *PreviewCanvas
        output:       *RichEditCtrl
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
    outputText: CompilerOutput
    image:      Image
    frameCount: u32
    renderUs:   u32
    sigChanged: SigArray'func||(*Wnd)
}

impl PreviewViewer
{
    // Builds a preview of the native renderer or of a GUI: a canvas for the frames, an output
    // for the diagnostics, and a status line.
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

        with result.status = Label.create(result, "", {0, 0, 0, 28}, null, .SecondaryText)
        {
            .dockStyle = .Bottom
        }

        with result.canvas = Wnd.create'PreviewCanvas(result, "prism.preview.canvas")
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .sigClick        += func|viewer = result|(point) { viewer.forwardClick(point) }
        }

        with result.output = RichEditCtrl.create(result)
        {
            .dockStyle = .Center
            .setFlags(.ReadOnly)
            .setLexer(&result.outputText)
        }

        result.canvas.hide()
        result.image = Image.create(Pipeline.FrameChannel.Width, Pipeline.FrameChannel.Height, .BGRA8)
        result.retranslate()
        return result
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
               not Atomic.get(&.probe.cancelled) and
               (not .preparing or not Atomic.get(&.preparing.cancelled)) and
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
            Atomic.exchange(&.preparing.cancelled, 1)
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
            Atomic.exchange(&.probe.cancelled, 1)
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
        .refreshStatus()
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
        .outputText.parse(diagnostics)
        .outputText.show(.output)
        .output.show()
        .canvas.hide()
        .applyLayout()
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
                if Atomic.get(&candidate.cancelled)
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
            elif not Atomic.get(&candidate.cancelled) and
                 Atomic.get(&candidate.ready) and
                 Atomic.get(&candidate.channel.header().published)
            {
                // Keep the previous animation alive until the replacement has a complete frame.
                Atomic.exchange(&.probe.cancelled, 1)
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
            .refreshStatus()
            .sigChanged.call(me)
            return
        }

        if not Atomic.get(&.probe.ready) or (.paused and .frameCount != 0) or not .isVisible() do
            return
        let header = .probe.channel.header()
        let frame  = Atomic.get(&header.published)
        if frame == Atomic.get(&header.consumed) do
            return
        Memory.copy(.image.pixels.buffer, .probe.channel.pixels(), Pipeline.FrameChannel.ByteCount)
        .renderUs = header.renderUs
        let firstFrame = .frameCount == 0
        .frameCount = frame
        .probe.channel.acknowledge(frame)
        if firstFrame do
            .sigChanged.call(me)
        .canvas.update(&.image)
        if firstFrame
        {
            .output.hide()
            .canvas.show()
            .applyLayout()
        }

        if firstFrame or .frameCount % 15 == 0 do
            .refreshStatus()
    }

    // Cancels every probe, waits for their workers, and closes the frame channel.
    mtd stop()
    {
        Atomic.exchange(&.probe.cancelled, 1)
        if .preparing
        {
            Atomic.exchange(&.preparing.cancelled, 1)
            .retired.add(.preparing)
            .preparing = null
        }

        for probe in .retired do
            Atomic.exchange(&probe.cancelled, 1)
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

    // Shows the build and render times of the running preview, or why it is not running.
    mtd refreshStatus()
    {
        if .running and .frameCount do
            .status.setText(.probe.reused ? Format.toString(appStrings().ui_ReusedStats, .renderUs) : Format.toString(appStrings().ui_LiveStats, .probe.compileMs, .renderUs))
        elif .running do
            .status.setText("")
        elif .probe.failed do
            .status.setText(appStrings().ui_Stopped)
        else do
            .status.setText(appStrings().ui_Ready)
    }

    // Writes the hint shown before the first run, and the status, in the active language.
    mtd retranslate()
    {
        if not .running and not .probe.failed and not .frameCount do
            .output.setText(Format.toString("%\n\n%", .gui ? appStrings().ui_GuiHint : appStrings().ui_RenderHint, appStrings().ui_ChooseExample))
        .refreshStatus()
        .applyLayout()
    }
}

impl IViewer for PreviewViewer
{
    mtd impl window()->*Wnd => &.wnd
    mtd impl compile(request: Pipeline.BuildRequest) { .compileRequest(request) }
    mtd impl inspectionStage()->string => ""
    mtd impl isPaused()->bool => .paused
    mtd impl setPaused(paused: bool) { .paused = paused }
    mtd impl shutdown() { .stop() }
    mtd impl isRunning()->bool => .preparing != null or (.running and (not .frameCount or .queued))
    mtd impl subscribeChanged(action: func||(*Wnd)) { .sigChanged += action }
}

impl IWnd for PreviewViewer
{
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

#global internal

using Core, Gui, Pixel

// Both execution viewers share transport and lifecycle, but each compiles its own entry contract.
struct PreviewViewer
{
    using wnd: Wnd

    late
    {
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
    task:       Swag.Task
    timer:      *Timer?
    probe:      Pipeline.PreviewProbe
    source:     String
    pending:    Pipeline.BuildRequest
    request:    Pipeline.BuildRequest
    generation: u64
    level:      Swag.BuildCfgBackendOptimLevel
    outputText: CompilerOutput
    image:      Image
    frameCount: u32
    renderUs:   u32
    sigChanged: SigArray'func||(*Wnd)
}

impl PreviewViewer
{
    func create(parent: *ViewerPanel, editor: *RichEditCtrl, gui: bool, level: Swag.BuildCfgBackendOptimLevel)->*PreviewViewer
    {
        let result = Wnd.create'PreviewViewer(parent, "prism.preview")
        result.backgroundStyle        = .Transparent
        result.panel                  = parent
        result.cache                  = parent.cache
        result.sourceEditor           = editor
        result.gui                    = gui
        result.level                  = level
        result.status                 = Label.create(result, "", {0, 0, 0, 28}, null, .SecondaryText)
        result.status.dockStyle       = .Bottom
        result.canvas                 = Wnd.create'PreviewCanvas(result, "prism.preview.canvas")
        result.canvas.dockStyle       = .Center
        result.canvas.backgroundStyle = .Transparent
        result.canvas.sigClick        += func|viewer = result|(point)
        {
            if !viewer.gui or viewer.paused or !viewer.running or !Atomic.get(&viewer.probe.ready) do
                return
            let header = viewer.probe.channel.header()
            let click  = Atomic.get(&header.click)
            if click != Atomic.get(&header.clicked) do
                return
            header.clickX = cast(u32) point.x
            header.clickY = cast(u32) point.y
            Atomic.exchange(&header.click, click + 1)
        }

        result.output = RichEditCtrl.create(result)
        result.output.dockStyle = .Center
        result.output.setFlags(.ReadOnly)
        result.output.setLexer(&result.outputText)
        result.canvas.hide()
        result.image = Image.create(Pipeline.FrameChannel.Width, Pipeline.FrameChannel.Height, .BGRA8)
        result.retranslate()
        return result
    }

    mtd compileSource(source: string) { .compileRequest(.panel.request(source)) }

    mtd compileRequest(request: Pipeline.BuildRequest)
    {
        // Editing another panel need not restart an unchanged live preview.
        if .running and !Atomic.get(&.probe.cancelled) and .generation == .cache.generation and .request.kind == request.kind and .request.sameProgram(request) do
            return
        .pending = request
        if .running
        {
            .queued = true
            Atomic.exchange(&.probe.cancelled, 1)
            return
        }

        .start()
    }

    mtd start()
    {
        .request    = .pending
        .generation = .cache.generation
        .source     = .request.source
        .queued     = false
        .running    = true
        .frameCount = 0
        .probe.channel.close()
        .probe.ready     = 0
        .probe.cancelled = 0
        .probe.failed    = false
        .probe.diagnostics.clear()
        .timer = .app().addTimer(16'ms, me)
        .task.submit(func|viewer = me|()
        {
            catch viewer.probe.run(viewer.request, viewer.cache) as error
            if error != null
            {
                viewer.probe.failed      = true
                viewer.probe.diagnostics = "The preview could not be started."
            }
        })
        .refreshStatus()
        .sigChanged.call(me)
    }

    mtd poll()
    {
        if .task.isDone()
        {
            .removeTimer(.timer!)
            .timer   = null
            .running = false
            if .queued
            {
                .start()
                return
            }

            if .probe.failed
            {
                .outputText.parse(.probe.diagnostics.toString())
                .outputText.show(.output)
                .output.show()
                .canvas.hide()
                .applyLayout()
            }

            .refreshStatus()
            .sigChanged.call(me)
            return
        }

        if !Atomic.get(&.probe.ready) or (.paused and .frameCount != 0) or !.isVisible() do
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

    mtd stop()
    {
        if .running
        {
            Atomic.exchange(&.probe.cancelled, 1)
            .task.wait()
        }

        if .timer and !.isPendingDestroy do
            .removeTimer(.timer!)
        .timer   = null
        .running = false
        .queued  = false
        .probe.channel.close()
    }

    mtd refreshStatus()
    {
        if .running and .frameCount do
            .status.setText((.probe.reused ? Format.toString(appStrings().ui_ReusedStats, .renderUs) : Format.toString(appStrings().ui_LiveStats, .probe.compileMs, .renderUs)).toString())
        elif .running do
            .status.setText("")
        elif .probe.failed do
            .status.setText(appStrings().ui_Stopped)
        else do
            .status.setText(appStrings().ui_Ready)
    }

    mtd retranslate()
    {
        if !.running and !.probe.failed and !.frameCount do
            .output.setText(Format.toString("%\n\n%", .gui ? appStrings().ui_GuiHint : appStrings().ui_RenderHint, appStrings().ui_ChooseExample).toString())
        .refreshStatus()
        .applyLayout()
    }
}

impl IViewer for PreviewViewer
{
    mtd impl window()->*Wnd => &.wnd
    mtd impl compile(request: Pipeline.BuildRequest) { .compileRequest(request) }
    mtd impl inspectionStage()->string => ""
    mtd impl setOptimization(level: Swag.BuildCfgBackendOptimLevel) { .level = level }
    mtd impl isPaused()->bool => .paused
    mtd impl setPaused(paused: bool) { .paused = paused }
    mtd impl shutdown() { .stop() }
    mtd impl isRunning()->bool => .running and !.frameCount
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
        .wnd.IWnd.onDestroyEvent(evt)
    }
}

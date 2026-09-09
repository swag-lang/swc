#global internal

using Core, Gui, Pixel

// Both execution viewers share transport and lifecycle, but each compiles its own entry contract.
struct PreviewViewer
{
    using wnd: Wnd

    late
    {
        sourceEditor: *RichEditCtrl
        optimCombo:   *ComboBox
        pauseButton:  *PushButton
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
    pending:    String
    level:      Swag.BuildCfgBackendOptimLevel
    outputText: CompilerOutput
    image:      Image
    frameCount: u32
    renderUs:   u32
    sigChanged: SigArray'func||(*Wnd)
}

impl PreviewViewer
{
    func create(parent: *Wnd, editor: *RichEditCtrl, gui: bool, level: Swag.BuildCfgBackendOptimLevel)->*PreviewViewer
    {
        let result = Wnd.create'PreviewViewer(parent, "prism.preview")
        result.backgroundStyle = .Transparent
        result.sourceEditor    = editor
        result.gui = gui
        let options = Wnd.create'Wnd(result, {0, 0, 0, 44})
        options.dockStyle           = .Top
        options.backgroundStyle     = .Transparent
        options.padding             = {0, 0, 0, 8}
        result.optimCombo           = ComboBox.create(options, {0, 0, 150, 36})
        result.optimCombo.dockStyle = .Left
        for name in ["O0", "O1", "O2"] do
            result.optimCombo.addItem(name)
        result.optimCombo.setSelectedIndex(cast(u32) level, notify: false)
        result.optimCombo.sigChanged += func|viewer = result|(combo, index)
        {
            discard combo
            discard index
            viewer.compileSource(viewer.sourceEditor.text().toString())
        }

        result.pauseButton = PushButton.create(options, "", {0, 0, 120, 36})
        result.pauseButton.dockStyle  = .Right
        result.pauseButton.sigPressed += func|viewer = result|(button)
        {
            discard button
            viewer.paused = !viewer.paused
            viewer.retranslate()
        }

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

    mtd compileSource(source: string)
    {
        .pending = source
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
        .source     = .pending
        .level      = cast(Swag.BuildCfgBackendOptimLevel) .optimCombo.selectedIndex
        .queued     = false
        .running    = true
        .frameCount = 0
        .probe.channel.close()
        .probe.ready     = 0
        .probe.cancelled = 0
        .probe.failed    = false
        .probe.diagnostics.clear()
        .timer = .app().addTimer(33'ms, me)
        .task.submit(func|viewer = me|()
        {
            catch viewer.probe.run(viewer.source.toString(), viewer.gui, viewer.level) as error
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
        Atomic.exchange(&header.consumed, frame)
        if firstFrame do
            .sigChanged.call(me)
        .canvas.update(&.image)
        .output.hide()
        .canvas.show()
        .applyLayout()
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
            .status.setText(Format.toString(appStrings().ui_LiveStats, .probe.compileMs, .renderUs).toString())
        elif .running do
            .status.setText(appStrings().ui_Working)
        elif .probe.failed do
            .status.setText(appStrings().ui_Stopped)
        else do
            .status.setText(appStrings().ui_Ready)
    }

    mtd retranslate()
    {
        .optimCombo.toolTip = appStrings().ui_Optimize
        .pauseButton.setText(.paused ? appStrings().ui_Resume : appStrings().ui_Pause)
        if !.running and !.probe.failed and !.frameCount do
            .output.setText(Format.toString("%\n\n%", .gui ? appStrings().ui_GuiHint : appStrings().ui_RenderHint, appStrings().ui_ChooseExample).toString())
        .refreshStatus()
        .applyLayout()
    }
}

impl IViewer for PreviewViewer
{
    mtd impl window()->*Wnd => &.wnd
    mtd impl compile(source: string) { .compileSource(source) }
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

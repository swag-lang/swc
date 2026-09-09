#global internal

using Core, Gui

// What the status line is currently reporting.
//
// The line is named rather than written, so a language switch can say the same thing again without
// the window having kept a copy of the sentence.
internal enum StatusMessage
{
    Ready            // Nothing has been compiled yet.
    Working          // The compiler is running.
    Done             // The compiler printed the requested stage.
    NoOutput         // The compilation succeeded and printed nothing for this stage.
    Stopped          // The compiler reported an error, which the pane is showing.
    ProbeStopped     // The compiler process could not be started at all.
}

/*
One compilation running outside the interface thread.

The compiler is a separate process and a compilation is tens to hundreds of milliseconds, which is
long enough to stop a window that waits for it. The window submits the work instead and polls it on
a timer, so it keeps drawing, keeps taking text, and keeps answering the reader while the compiler
runs.

Only one compilation per viewer runs at a time. A request that arrives while one is running replaces whatever
was waiting rather than joining a queue: the reader wants the answer to what they last asked, not
every stage they passed through on the way to it.
*/
struct CompileJob
{
    task:  Swag.Task     // Runs `MicrocodeViewer.runCompile` off the interface thread.
    timer: *Timer?       // Polls the task while it runs, and is removed when it finishes.

    // Inputs, copied before the task starts so the editor stays editable while it runs.
    source:     String
    stage:      String
    optimLevel: Swag.BuildCfgBackendOptimLevel

    // What the task left behind. The interface thread reads these only once the task is done.
    result:  Pipeline.Result
    stopped: bool     // Whether the compiler could not be started at all.
    elapsed: u64      // Milliseconds the compilation took, reported on the status line.

    running: bool     // Whether a task is in flight, which is what makes a new request wait.
    queued:  bool     // Whether a request arrived while one was, and runs as soon as it ends.
}

// One microcode viewer owns its options, process, pending request, and colored result.
struct MicrocodeViewer
{
    using wnd: Wnd
        late
    {
        sourceEditor: *RichEditCtrl
        stageCombo:   *ComboBox
        optimCombo:   *ComboBox
        output:       *RichEditCtrl
        status:       *Label
        optionsBar:   *MicrocodeOptions
    }

    sigChanged:    SigArray'func||(*Wnd)
    outputText:    CompilerOutput
    probe:         Pipeline.Probe
    job:           CompileJob
    pendingSource: String
    statusMessage: StatusMessage
    outputIsHint = true
}

impl MicrocodeViewer
{
    func create(parent: *Wnd, sourceEditor: *RichEditCtrl, level: Swag.BuildCfgBackendOptimLevel)->*MicrocodeViewer
    {
        let result = Wnd.create'MicrocodeViewer(parent, "prism.microcode")
        result.backgroundStyle      = .Transparent
        result.sourceEditor         = sourceEditor
        result.optionsBar           = MicrocodeOptions.create(result)
        result.optionsBar.dockStyle = .Top
        result.optimCombo           = result.optionsBar.optimization!
        result.stageCombo           = result.optionsBar.stage!
        for name in ["O0", "O1", "O2"] do
            result.optimCombo.addItem(name)
        result.optimCombo.setSelectedIndex(cast(u32) level, notify: false)
        result.fillStages()
        result.stageCombo.sigChanged += func|viewer = result|(combo, index)
        {
            discard combo
            discard index
            viewer.optionsChanged()
        }
        result.optimCombo.sigChanged += func|viewer = result|(combo, index)
        {
            discard combo
            discard index
            viewer.optionsChanged()
        }

        let footer = Wnd.create'Wnd(result, {0, 0, 0, 28})
        footer.dockStyle        = .Bottom
        footer.backgroundStyle  = .Transparent
        footer.padding          = {0, 4, 0, 0}
        result.status           = Label.create(footer, "", {}, null, .SecondaryText)
        result.status.dockStyle = .Center
        result.status.setTextAlignment(.Left, .Center)
        result.output           = RichEditCtrl.create(result)
        result.output.dockStyle = .Center
        result.output.setFlags(.ReadOnly)
        result.output.setLexer(&result.outputText)
        result.retranslate()
        result.applyLayout()
        return result
    }

    mtd optionsChanged()
    {
        .compileSource(.sourceEditor.text().toString())
        .sigChanged.call(me)
    }

    // Fills the stage list in the active language, keeping the stage that was selected.
    mtd fillStages()
    {
        let selected = .stageCombo.items.count ? .stageCombo.selectedIndex : Pipeline.DefaultStage

        .stageCombo.clear()
        let labels = Pipeline.stageLabels()
        for i in labels.count do
            .stageCombo.addItem(labels[i])
        .stageCombo.setSelectedIndex(selected, notify: false)
    }

    // Asks for the snippet to be compiled at the selected stage.
    //
    // One compilation is in flight at a time. Asking again while one runs marks the request rather
    // than starting a second compiler, and the marked request runs as soon as the first ends — so
    // holding a key on the stage list costs one more compilation, not one per step.
    mtd compileSource(source: string)
    {
        .pendingSource = source
        if .job.running
        {
            .job.queued = true
            return
        }

        .startCompile()
    }

    // Copies what is to be compiled and submits it, leaving the window free to draw and take text.
    mtd startCompile()
    {
        let index = .stageCombo.selectedIndex
        if index >= Pipeline.Stages.count do
            return

        .job.source     = .pendingSource
        .job.stage      = String.from(Pipeline.Stages[index])
        .job.optimLevel = cast(Swag.BuildCfgBackendOptimLevel) .optimCombo.selectedIndex
        .job.queued     = false
        .job.running    = true

        // Options remain editable while this viewer compiles; another request replaces its pending input.
        .setStatus(.Working)
        .job.timer = .app().addTimer(20'ms, me)

        let window = me
        .job.task.submit(func|window|() { window.runCompile() })
    }

    // Runs on the job's thread. Nothing here may reach the window tree or anything it draws from.
    mtd runCompile()
    {
        var watch: Time.Stopwatch
        watch.start()

        let run = catch .probe.compile(.job.source.toString(), .job.stage.toString(), .job.optimLevel) as probeError
        .job.stopped = probeError != null
        if !.job.stopped do
            .job.result = run
        .job.elapsed = watch.elapsedMilliseconds()
    }

    // Reports what the finished job produced, then starts whatever was asked for meanwhile.
    mtd finishCompile()
    {
        .removeTimer(.job.timer!)
        .job.timer   = null
        .job.running = false

        if .job.stopped
        {
            .setStatus(.ProbeStopped)
        }
        else
        {
            .outputText.parse(.job.result.text.toString())
            .outputText.show(.output)
            .outputIsHint = false

            if .job.result.failed do
                .setStatus(.Stopped)
            elif .job.result.text.isEmpty() do
                .setStatus(.NoOutput)
            else do
                .setStatus(.Done)
        }

        if .job.queued do
            .startCompile()
    }

    // Waits for a compilation still in flight, so the probe it reads is not destroyed under it.
    mtd stopCompile()
    {
        if .job.running do
            .job.task.wait()
        if .job.timer and !.isPendingDestroy do
            .removeTimer(.job.timer!)
        .job.timer   = null
        .job.running = false
        .job.queued  = false
    }

    // Reports the outcome of the latest compilation on the single status line.
    mtd setStatus(message: StatusMessage)
    {
        .statusMessage = message
        .refreshStatus()
        .sigChanged.call(me)
    }

    // Writes the current status in the active language.
    mtd refreshStatus()
    {
        let strings = appStrings()
        switch .statusMessage
        {
        case .Ready:
            .status.setText(strings.ui_Ready)

        case .Working:
            .status.setText(strings.ui_Working)

        // An application about what the compiler does says how long it took to do it: the number
        // is the reader's own measurement of the tool they came here to judge.
        case .Done:
            .status.setText(Format.toString(strings.ui_Done, .job.elapsed).toString())

        case .NoOutput:
            .status.setText(strings.ui_NoOutput)

        case .Stopped:
            .status.setText(strings.ui_Stopped)

        case .ProbeStopped:
            .status.setText(strings.ui_ProbeStopped)
        }
    }

    mtd retranslate()
    {
        .stageCombo.toolTip = appStrings().ui_Stage
        .optimCombo.toolTip = appStrings().ui_Optimize
        .fillStages()
        .refreshStatus()
        if .outputIsHint do
            .output.setText(appStrings().ui_OutputHint)
        .applyLayout()
    }
}

impl IViewer for MicrocodeViewer
{
    mtd impl window()->*Wnd => &.wnd
    mtd impl compile(source: string) { .compileSource(source) }
    mtd impl shutdown() { .stopCompile() }
    mtd impl isRunning()->bool => .job.running
    mtd impl subscribeChanged(action: func||(*Wnd)) { .sigChanged += action }
}

impl IWnd for MicrocodeViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .job.timer and .job.task.isDone() do
            .finishCompile()
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
        .stopCompile()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}

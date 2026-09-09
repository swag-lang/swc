#global internal

using Core, Gui

/*
The snippet Swag Prism opens on.

A dot product is the shortest program whose compiled form is worth looking at: it is a loop over
two arrays, so the reader can watch the stack slots become registers, the address arithmetic fold
into one addressing mode, and — at the vectorizing stage — several iterations become one
instruction.
*/
private const StarterSnippet = """\
    // The first function is the one that gets inspected.
    // Pick a stage, then compile.
    func dot(a, b: const [..] f32)->f32
    {
        var total = 0'f32
        for i in a.count do
            total += a[i] * b[i]
        return total
    }
    """

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

Only one compilation runs at a time. A request that arrives while one is running replaces whatever
was waiting rather than joining a queue: the reader wants the answer to what they last asked, not
every stage they passed through on the way to it.
*/
struct CompileJob
{
    task:  Swag.Task     // Runs `MainWindow.runCompile` off the interface thread.
    timer: *Timer?       // Polls the task while it runs, and is removed when it finishes.

    // Inputs, copied before the task starts so the editor stays editable while it runs.
    source:   String
    stage:    String
    optimize: bool

    // What the task left behind. The interface thread reads these only once the task is done.
    result:  Pipeline.Result
    stopped: bool     // Whether the compiler could not be started at all.
    elapsed: u64      // Milliseconds the compilation took, reported on the status line.

    running: bool     // Whether a task is in flight, which is what makes a new request wait.
    queued:  bool     // Whether a request arrived while one was, and runs as soon as it ends.
}

// The one window of Swag Prism: a snippet on the left, what the compiler made of it on the right.
struct MainWindow
{
    using wnd: Wnd

        // Controls the window keeps, so a language switch can say everything again.
        late
    {
        appearanceButton: *AppearanceButton
        stageLabel:       *Label
        stageCombo:       *ComboBox
        optimizeCheck:    *CheckButton
        runButton:        *PushButton
        editor:           *RichEditCtrl
        output:           *RichEditCtrl
        status:           *Label
    }

    lexer:         RichEditLexerSwag
    statusMessage: StatusMessage

    // Owned by the compile job between submission and completion: nothing on the interface thread
    // may reach into either while `job.running` holds.
    probe: Pipeline.Probe
    job:   CompileJob

    // Whether the output pane still holds its opening sentence rather than a compilation, so a
    // language switch can say that sentence again without overwriting a result.
    outputIsHint = true

    // Persisted presentation choices, restored before the window is shown.
    language:   String
    themeIndex: u32
}

impl MainWindow
{
    const WindowWidth  = 1280's32
    const WindowHeight = 820's32
    const MinWidth     = 900.0
    const MinHeight    = 560.0

    // One row of 20-pixel controls in a 36-pixel cell, and the shared 16-pixel outer air.
    const BarHeight    = 36.0
    const StatusHeight = 28.0
    const Gutter       = 16.0

    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "prism.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        surface.minSize        = {MinWidth, MinHeight}
        result.backgroundStyle = .View
        result.language        = ReferenceLanguage

        result.appearanceButton                 = AppearanceButton.create(surface, "prism.appearance")
        result.appearanceButton.sigThemeChanged += func|window = result|(button)
        {
            window.themeIndex = cast(u32) button.appearanceTheme
            catch g_App.saveState()
        }
        result.appearanceButton.sigLanguageChanged += func|window = result|(button)
        {
            window.language = button.language
            catch g_App.saveState()
        }
        result.appearanceButton.sigAboutRequested += func|window = result|(button)
        {
            discard button
            window.showAbout()
        }

        // One accent rule across the top identifies every standard Swag application surface.
        Separator.create(result, .Top, .Accent)

        result.createCommandBar()
        result.createStatusLine()
        result.createPanes()

        result.applyLanguage()
        result.applyLayout()
        result.setStatus(.Ready)
        return result
    }

    mtd createCommandBar()
    {
        let bar = Wnd.create'Wnd(&.wnd, {0, 0, 0, BarHeight})
        bar.dockStyle = .Top
        bar.margin    = {Gutter, 12, Gutter, 0}

        .stageLabel           = Label.create(bar, appStrings().ui_Stage, {0, 0, 56}, null, .SecondaryText)
        .stageLabel.dockStyle = .Left
        .stageLabel.setTextAlignment(.Left, .Center)

        // The stage list is the whole interface of the pane beside it, so it is the one control
        // wide enough to read its longest entry without opening.
        .stageCombo            = ComboBox.create(bar, {0, 0, 260, BarHeight - 8}, "prism.stage")
        .stageCombo.dockStyle  = .Left
        .stageCombo.margin.z   = Gutter
        .stageCombo.sigChanged += func|window = me|(combo, index)
        {
            discard combo
            discard index
            window.compile()
        }

        .optimizeCheck           = CheckButton.create(bar, appStrings().ui_Optimize, {0, 0, 130, BarHeight - 8}, "prism.optimize")
        .optimizeCheck.dockStyle = .Left
        .optimizeCheck.margin.z  = Gutter
        .optimizeCheck.setState(.Checked)
        .optimizeCheck.sigChanged += func|window = me|(check)
        {
            discard check
            window.compile()
        }

        // The bar reads as the sentence it is: which stage, at which optimization level, compile.
        // Pushed to the far edge instead, the action that closes that sentence reads as belonging
        // to the window rather than to the two controls it acts on.
        .runButton            = PushButton.create(bar, appStrings().ui_Run, {0, 0, 130, BarHeight - 8}, "prism.run", .Strong)
        .runButton.dockStyle  = .Left
        .runButton.sigPressed += func|window = me|(button)
        {
            discard button
            window.compile()
        }

        .fillStages()
        bar.applyLayout()
    }

    mtd createStatusLine()
    {
        let row = Wnd.create'Wnd(&.wnd, {0, 0, 0, StatusHeight})
        row.dockStyle = .Bottom
        row.margin    = {Gutter, 4, Gutter, 8}

        .status           = Label.create(row, "", {}, null, .SecondaryText)
        .status.dockStyle = .Center
        .status.setTextAlignment(.Left, .Center)
        row.applyLayout()
    }

    mtd createPanes()
    {
        let split = SplitterCtrl.create(&.wnd, {}, false, "prism.split")
        split.dockStyle = .Center
        split.margin    = {Gutter, 12, Gutter, 0}

        .editor = RichEditCtrl.create(split)
        .editor.setLexer(&.lexer)
        .editor.setText(StarterSnippet)

        // The output is a document, not a field: it is read, scrolled, and copied out of, and any
        // edit it could take would be thrown away by the next compilation.
        //
        // It opens on a sentence rather than on nothing. Half a window of empty ground says the
        // application has failed to load, and the reader has no way to know it is waiting on them.
        .output = RichEditCtrl.create(split)
        .output.setFlags(.ReadOnly)
        .output.setText(appStrings().ui_OutputHint)

        split.addPane(.editor, 460)
        split.addPane(.output, 700)
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

    // Compiles what the editor holds and shows what the compiler printed about the chosen stage.
    //
    // The compiler runs to completion before this returns, so the window is unresponsive while it
    // does. A snippet is one small module and its build folder is reused, which keeps that pause
    // short; moving it off the frame is what this pane needs before it can host a running program.
    // Asks for the snippet to be compiled at the selected stage.
    //
    // One compilation is in flight at a time. Asking again while one runs marks the request rather
    // than starting a second compiler, and the marked request runs as soon as the first ends — so
    // holding a key on the stage list costs one more compilation, not one per step.
    mtd compile()
    {
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

        .job.source   = .editor.text()
        .job.stage    = String.from(Pipeline.Stages[index])
        .job.optimize = .optimizeCheck.isChecked()
        .job.queued   = false
        .job.running  = true

        // The action that starts the work says so by being unavailable while it runs. The stage
        // list and the optimization toggle stay live, because changing either is a new request and
        // the job above already knows how to hold one.
        .runButton.disable()
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

        let run = catch .probe.compile(.job.source.toString(), .job.stage.toString(), .job.optimize) as probeError
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
        .runButton.enable()

        if .job.stopped
        {
            .setStatus(.ProbeStopped)
        }
        else
        {
            .output.setText(.job.result.text.toString())
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
    mtd shutdown()
    {
        if !.job.running do
            return
        .job.task.wait()
        .job.running = false
    }

    // Reports the outcome of the latest compilation on the single status line.
    mtd setStatus(message: StatusMessage)
    {
        .statusMessage = message
        .refreshStatus()
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

    // Says everything the window put on its surface again, in the language that is now active.
    //
    // Every one of these was assigned at construction, so nothing else would ever replace it. The
    // stage list is rebuilt rather than relabelled, and keeps its selection across the rebuild.
    mtd retranslate()
    {
        let strings = appStrings()
        .stageLabel.setText(strings.ui_Stage)
        .optimizeCheck.setText(strings.ui_Optimize)
        .runButton.setText(strings.ui_Run)
        .fillStages()
        .refreshStatus()

        if .outputIsHint do
            .output.setText(strings.ui_OutputHint)

        .surface!.setTitle(strings.ui_WindowTitle)
        .applyLayout()
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language.toString())
    }

    // Applies the persisted standard application palette.
    mtd applyTheme()
    {
        .themeIndex = Math.min(.themeIndex, cast(u32) AppearanceTheme.Dark)
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme) .themeIndex)
    }

    mtd showAbout()
    {
        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)
        let dlg     = AboutDlg.createApplication(.surface!, {
            productName: ProductName,
            version: version.toString(),
            buildDate: BuildDate,
            sourceUrl: "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagprism",
            copyrightHolder: "Christophe Beaudet"})
        discard dlg.doModal()
    }

}

impl IWnd for MainWindow
{
    // Picks up a finished compilation and reports it.
    //
    // The job is polled rather than pushed: the task runs on another thread, and everything the
    // result touches — the pane, the status line, the button — belongs to this one.
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

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch evt.serializer.serialize("MainWindow.language", &me.language)
        catch evt.serializer.serialize("MainWindow.themeIndex", &me.themeIndex)
    }
}

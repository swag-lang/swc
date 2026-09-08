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
    probe:         Pipeline.Probe
    statusMessage: StatusMessage

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
    mtd compile()
    {
        let index = .stageCombo.selectedIndex
        if index >= Pipeline.Stages.count do
            return

        .setStatus(.Working)

        let source = .editor.text()
        let run    = catch .probe.compile(source.toString(), Pipeline.Stages[index], .optimizeCheck.isChecked()) as probeError
        if probeError != null
        {
            .setStatus(.ProbeStopped)
            return
        }

        .output.setText(run.text.toString())
        .outputIsHint = false

        if run.failed do
            .setStatus(.Stopped)
        elif run.text.isEmpty() do
            .setStatus(.NoOutput)
        else do
            .setStatus(.Done)
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
        case .Ready:        .status.setText(strings.ui_Ready)
        case .Working:      .status.setText(strings.ui_Working)
        case .Done:         .status.setText(strings.ui_Done)
        case .NoOutput:     .status.setText(strings.ui_NoOutput)
        case .Stopped:      .status.setText(strings.ui_Stopped)
        case .ProbeStopped: .status.setText(strings.ui_ProbeStopped)
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

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
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

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch evt.serializer.serialize("MainWindow.language", &me.language)
        catch evt.serializer.serialize("MainWindow.themeIndex", &me.themeIndex)
    }
}

#global internal

using Core, Gui

// What the status line says about the formatter.
enum FormatStatus
{
    None        // Nothing to report, or a compilation has replaced the report.
    Working     // The formatter is running.
    Done        // The formatted source replaced the editor text.
    Failed      // The formatter stopped on an error, shown as the status tooltip.
    Changed     // The source was edited while it was formatted, so the result was dropped.
}

// Owns the shared source and one or two independently configured viewers.
struct MainWindow
{
    using wnd: Wnd

    late
    {
        appearanceButton: *AppearanceButton
        spinner:          *Spinner
        layoutButton:     *IconButton
        sourcePanel:      *Wnd
        editor:           *RichEditCtrl
        status:           *Label
        commandBar:       *SourceActions
        statusBar:        *Wnd
        sourceSplit:      *SplitterCtrl
        viewerSplit:      *SplitterCtrl
    }

    cache:             Pipeline.CompilationCache
    formatter:         Pipeline.SourceFormatter
    formatTask:        Swag.Task
    formatTimer:       *Timer?
    formatCancelled:   u32
    formatSource:      String
    formatResult:      Pipeline.Result
    formatStatus:      FormatStatus
    editTimer:         *Timer?
    selectedExample:   ExampleKind
    panels:            Array'*ViewerPanel
    icons:             IconSet
    comparisonEnabled: bool
    lexer:             RichEditLexerSwag
    language:          String
    themeIndex:        u32
}

impl MainWindow
{
    const WindowWidth  = 1500's32
    const WindowHeight = 900's32
    const MinWidth     = 1080.0
    const MinHeight    = 560.0
    const Gutter       = 16.0

    // Builds the window: the appearance button, the status line, the source and viewer panes,
    // and the texts of the active language.
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "prism.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        result.icons.setup(result.app().renderer, prismIcons())
        surface.minSize        = {MinWidth, MinHeight}
        result.backgroundStyle = .ToolBar
        result.language        = ReferenceLanguage

        result.createAppearanceButton()
        Separator.create(result, .Top, .Accent)
        result.createStatusLine()
        result.createPanes()
        result.applyLanguage()
        result.retranslate()
        result.applyLayout()
        return result
    }

    // Returns an application glyph at the toolbar size.
    mtd icon(kind: PrismIcon)->Icon => .icons.icon(cast(s32, kind), 18, .theme().res.atlasScale)

    // Creates the caption's appearance action, which persists the palette and language it applies.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(.surface!, "prism.appearance")
        {
            .sigThemeChanged += func|window = me|(button)
            {
                window.themeIndex = cast(u32, button.appearanceTheme)
                catch g_App.saveState()
            }

            .sigLanguageChanged += func|window = me|(button)
            {
                window.language = button.language
                catch g_App.saveState()
            }

            .sigAboutRequested += func|window = me|(?)
            {
                window.showAbout()
            }
        }
    }

    // Creates the source toolbar above the editor and routes its actions to the window.
    mtd createCommandBar()
    {
        with .commandBar = Wnd.create'SourceActions(.sourcePanel)
        {
            .dockStyle       = .Top
            .backgroundStyle = .CommandBar
            .padding         = 0
            .margin          = {0, 0, 0, 8}
        }

        with .commandBar.runButton = PushButton.create(.commandBar, appStrings().ui_CompileVisible, {0, 0, 0, 36}, "prism.run", .Strong)
        {
            .style.setStyleSheetMetrics("btnPush_Width 0")
            .setIcon(me.theme().icon(.Play, 18))
            .setIconSize(18, 18)
            .sigPressed += func|window = me|(?) { window.compile(force: true) }
        }

        with .commandBar.formatButton = PushButton.create(.commandBar, "", {0, 0, 0, 36}, "prism.format")
        {
            .style.setStyleSheetMetrics("btnPush_Width 0")
            .setIcon(me.icon(.Format))
            .setIconSize(18, 18)
            .sigPressed += func|window = me|(?) { window.format() }
        }

        with .commandBar.liveEdit = CheckButton.create(.commandBar, "", {0, 0, 0, 36}, "prism.liveEdit")
        {
            .style.setStyleSheetMetrics("btnPush_Width 0")
            .setState(.Checked)
            .sigChanged += func|window = me|(?) { window.scheduleCompile() }
        }

        with .commandBar.exampleCombo = ComboBox.create(.commandBar, {0, 0, 0, 36}, "prism.examples")
        {
            .sigChanged += func|window = me|(?, index) { window.openExample(cast(ExampleKind, index)) }
        }
    }

    // Creates the one-or-two-viewers toggle in the header of the first panel.
    mtd createLayoutButton()
    {
        with .layoutButton = IconButton.create(.panels[0].header, .icon(.Layout), {0, 0, 36, 36}, "prism.layout", flags: .Toggle)
        {
            .dockStyle = .Right
            .margin    = {8, 0, 0, 0}
            .setIconSize(18, 18)
            .setCheckIndicator(.Frame)
            .sendToBack()
            .sigCheckedChanged += func|window = me|(button) { window.setComparisonEnabled(button.isChecked) }
        }
    }

    // Creates the status line at the bottom of the window.
    mtd createStatusLine()
    {
        with .statusBar = Wnd.create'Wnd(&.wnd, {0, 0, 0, 32})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .InformationBar
            .padding         = {Gutter, 4, Gutter, 4}
        }

        with .spinner = Spinner.create(.statusBar, {0, 0, 16, 16}, "prism.busy")
        {
            .dockStyle = .Left
            .margin    = {0, 4, 8, 4}
            .hide()
        }

        with .status = Label.create(.statusBar, "", {}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
        }
    }

    // Creates the source pane and the viewer split beside it.
    mtd createPanes()
    {
        with .sourceSplit = SplitterCtrl.create(&.wnd, {}, false, "prism.split")
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with .sourcePanel = Wnd.create'Wnd(.sourceSplit)
        {
            .backgroundStyle = .Panel
            .padding         = 8
        }

        .createCommandBar()
        with .editor = RichEditCtrl.create(.sourcePanel)
        {
            .dockStyle = .Center
            .setLexer(&me.lexer)
            .setText(exampleSource(.Plasma))
        }

        // The first viewer opens on unoptimized code, the comparison on optimized code.
        with .viewerSplit = SplitterCtrl.create(.sourceSplit, {}, false, "prism.viewers")
        {
            .backgroundStyle = .Transparent
        }

        .createViewerPanel(.O0)
        .createViewerPanel(.O2)

        .sourceSplit.addPane(.sourcePanel, 480).minimumSize = 360
        .sourceSplit.addPane(.viewerSplit, 960).minimumSize = ViewerPanel.MinWidth
        .viewerSplit.setPaneVisible(1, false)
        .panels[0].selectViewer(.Render2D)
        .createLayoutButton()
        .refreshPaneLayout()
        .editor.sigChanged += func|window = me|(?) { window.scheduleCompile() }
    }

    // Creates one viewer panel in the viewer split and routes its requests to the window.
    mtd createViewerPanel(level: Swag.BuildCfgBackendOptimLevel)
    {
        with let panel = ViewerPanel.create(.viewerSplit, .editor, level, &.cache)
        {
            .sigChanged          += func|window = me|(?) { window.refreshStatus() }
            .sigCompileRequested += func|window = me|(?) { window.compile() }
            .sigOptionsChanged   += func|window = me|(?) { window.scheduleCompile() }
        }

        .panels.add(panel)
        .viewerSplit.addPane(panel, 540).minimumSize = ViewerPanel.MinWidth
    }

    // Applies the theme gutter, and keeps the viewer side wide enough for every visible panel.
    mtd refreshPaneLayout()
    {
        let gutter = .themeMetrics().panel_GutterSize
        .sourceSplit.margin = {gutter, gutter, gutter, gutter}
        .sourceSplit.items[1]!.minimumSize = .comparisonEnabled ? 2 * ViewerPanel.MinWidth + .themeMetrics().splitView_BarSize : ViewerPanel.MinWidth
        .applyLayout()
    }

    // Shows one viewer panel or two side by side, splitting the space evenly when the second
    // appears.
    mtd setComparisonEnabled(enabled: bool)
    {
        if .comparisonEnabled == enabled do
            return
        .comparisonEnabled = enabled
        .layoutButton.setParent(.panels[enabled ? 1 : 0].header)
        .layoutButton.sendToBack()
        .viewerSplit.setPaneVisible(1, enabled)
        .refreshPaneLayout()
        if enabled do
            .viewerSplit.setPaneSize(0, (.viewerSplit.paddedClientRect().width - .themeMetrics().splitView_BarSize) / 2)
        .retranslate()
    }

    // One native build can print the inspected function and run the same program: the microcode
    // request takes the kind of the native one, which inspects the same stage when both compile
    // the same program.
    func shareNativeBuild(microcode, native: *Pipeline.BuildRequest)
    {
        microcode.kind = native.kind
        if microcode.sameProgram(native[]) do
            native.stage = microcode.stage
    }

    // Only visible viewers receive the source snapshot; the hidden comparison keeps its result.
    mtd compile(force = false)
    {
        .cancelEditTimer()
        if .formatStatus != .Working do
            .formatStatus = .None
        if force do
            .cache.invalidate()
        let source = .editor.text()
        var requests: [2] Pipeline.BuildRequest
        for panel, index in .panels where index == 0 or .comparisonEnabled do
            requests[index] = panel.request(source)
        if .comparisonEnabled
        {
            if requests[0].kind == .Microcode and requests[1].kind != .Microcode do
                shareNativeBuild(&requests[0], &requests[1])
            elif requests[1].kind == .Microcode and requests[0].kind != .Microcode do
                shareNativeBuild(&requests[1], &requests[0])
        }

        for panel, index in .panels where index == 0 or .comparisonEnabled do
            panel.compile(requests[index])
        .refreshStatus()
    }

    // Stops the edit timer, cancels a running format, and shuts every panel and the build cache
    // down before the window closes.
    mtd shutdown()
    {
        .cancelEditTimer()
        if .formatStatus == .Working
        {
            Atomic.exchange(&.formatCancelled, 1)
            .formatTask.wait()
            .stopTimer(&.formatTimer)
            .formatStatus = .None
        }

        for panel in .panels do
            panel.shutdown()
        .cache.close()
    }

    // Formats the editor source on a worker; `finishFormat` applies the result once the timer sees
    // the task done.
    mtd format()
    {
        if .formatStatus == .Working do
            return
        .cancelEditTimer()
        .formatSource    = .editor.text()
        .formatCancelled = 0
        .formatStatus    = .Working
        .commandBar.formatButton.enable(false)
        .formatTimer = .addTimer(20'ms)
        .formatTask.submit(func|window = me|()
        {
            window.formatResult = catch window.formatter.format(window.formatSource, &window.formatCancelled) as error
            if error != null do
                window.formatResult.failed = true
        })
        .refreshStatus()
    }

    // Applies a finished format as one undo step, unless it failed or the source changed while it
    // ran, and recompiles what it rewrote.
    mtd finishFormat()
    {
        .stopTimer(&.formatTimer)
        .commandBar.formatButton.enable()
        if .formatResult.failed
        {
            .formatStatus = .Failed
        }
        elif .editor.text() != .formatSource
        {
            .formatStatus = .Changed
        }
        else
        {
            .formatStatus = .Done
            if .editor.text() != .formatResult.text
            {
                let cursor = .editor.selectionEnd()
                .editor.pushUndo()
                .editor.selectAll()
                .editor.deleteSelection()
                .editor.insertText(.formatResult.text)
                .editor.popUndo()
                .editor.setCursorPos(.editor.cursorFromLogicalPosition(cursor.lineIndex, cursor.charPosInLine))
                .editor.clearSelection()
                .scheduleCompile()
            }
        }

        .refreshStatus()
    }

    mtd cancelEditTimer() { .stopTimer(&.editTimer) }

    // Recompiles shortly after the last keystroke, when live edit is on.
    mtd scheduleCompile()
    {
        .cancelEditTimer()
        if .commandBar.liveEdit.isChecked() do
            .editTimer = .addTimer(150'ms)
    }

    // Loads example `kind` into the editor, shows it in the viewer it was written for, and
    // compiles it.
    mtd openExample(kind: ExampleKind)
    {
        .selectedExample = kind
        .editor.setText(exampleSource(kind))
        .panels[0].selectViewer(exampleViewer(kind))
        .commandBar.exampleCombo.setSelectedIndex(cast(u32, kind), notify: false)
        .compile()
    }

    // Shows the running viewers or the outcome of the last format in the status line, with the
    // formatter diagnostics as its tooltip on failure.
    mtd refreshStatus()
    {
        var running = 0'u64
        for panel in .panels where panel.isRunning() do
            running += 1

        .spinner.show(running != 0 or .formatStatus == .Working)
        .status.toolTip = ""
        if running > 1
        {
            .status.setText(Format.toString(appStrings().ui_RunningViewers, running))
        }
        elif running
        {
            .status.setText(appStrings().ui_Working)
        }
        else
        {
            switch #complete .formatStatus
            {
            case .None:
                .status.setText(appStrings().ui_Ready)

            case .Working:
                .status.setText(appStrings().ui_Formatting)

            case .Done:
                .status.setText(appStrings().ui_Formatted)

            case .Changed:
                .status.setText(appStrings().ui_FormatChanged)

            case .Failed:
                .status.setText(appStrings().ui_FormatFailed)
                var output: CompilerOutput
                output.parse(.formatResult.text)
                .status.toolTip = output.text
            }
        }

        .statusBar.applyLayout()
    }

    // Writes the command bar, layout button, and window title in the active language.
    mtd retranslate()
    {
        .commandBar.retranslate(.selectedExample)
        .layoutButton.setChecked(.comparisonEnabled)
        .layoutButton.toolTip = .comparisonEnabled ? appStrings().ui_OneViewer : appStrings().ui_TwoViewers
        .surface!.setTitle(appStrings().ui_WindowTitle)
        .refreshStatus()
        .applyLayout()
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language)
    }

    // Applies the persisted standard application palette.
    mtd applyTheme()
    {
        .themeIndex = Math.min(.themeIndex, cast(u32, AppearanceTheme.Dark))
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme, .themeIndex))
    }

    // Opens the standard About box, dated and versioned by the compilation of this executable.
    mtd showAbout()
    {
        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)

        with var about: ApplicationAboutDlgParams
        {
            .productName     = ProductName
            .version         = version
            .buildDate       = BuildDate
            .sourceUrl       = "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagprism"
            .copyrightHolder = "Christophe Beaudet"
        }

        discard AboutDlg.createApplication(.surface!, about).doModal()
    }
}

impl IWnd for MainWindow
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .editTimer do
            .compile()
        if evt.timer == .formatTimer and .formatTask.isDone() do
            .finishFormat()
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged:
            .retranslate()

        case .ThemeChanged:
            .layoutButton.setIcon(.icon(.Layout))
            .commandBar.runButton.setIcon(.theme().icon(.Play, 18))
            .commandBar.formatButton.setIcon(.icon(.Format))
            .refreshPaneLayout()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .shutdown()
        .icons.free()
        .wnd.IWnd.onDestroyEvent(evt)
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch evt.serializer.serialize("MainWindow.language", &me.language)
        catch evt.serializer.serialize("MainWindow.themeIndex", &me.themeIndex)
    }
}

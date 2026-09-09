#global internal

using Core, Gui

enum FormatStatus
{
    None
    Working
    Done
    Failed
    Changed
}

// Owns the shared source and one or two independently configured viewers.
struct MainWindow
{
    using wnd: Wnd

    late
    {
        appearanceButton: *AppearanceButton
        exampleCombo:     *ComboBox
        liveEdit:         *CheckButton
        formatButton:     *PushButton
        spinner:          *Spinner
        runButton:        *PushButton
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
    const MinWidth     = 1040.0
    const MinHeight    = 560.0
    const Gutter       = 16.0

    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "prism.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        result.icons.setup(result.app().renderer, prismIcons())
        surface.minSize        = {MinWidth, MinHeight}
        result.backgroundStyle = .ToolBar
        result.language        = ReferenceLanguage

        result.appearanceButton = AppearanceButton.create(surface, "prism.appearance")
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

        Separator.create(result, .Top, .Accent)
        result.createStatusLine()
        result.createPanes()
        result.applyLanguage()
        result.retranslate()
        result.applyLayout()
        return result
    }

    mtd createCommandBar()
    {
        .commandBar                 = Wnd.create'SourceActions(.sourcePanel)
        .commandBar.dockStyle       = .Top
        .commandBar.backgroundStyle = .CommandBar
        .commandBar.padding         = 0
        .commandBar.margin          = {0, 0, 0, 8}
        .runButton                  = PushButton.create(.commandBar, appStrings().ui_CompileVisible, {0, 0, 0, 36}, "prism.run", .Strong)
        .runButton.style.setStyleSheetMetrics("btnPush_Width 0")
        .runButton.setIcon(.theme().icon(.Play, 18))
        .runButton.setIconSize(18, 18)
        .runButton.sigPressed += func|window = me|(button)
        {
            discard button
            window.compile(force: true)
        }

        .formatButton = PushButton.create(.commandBar, "", {0, 0, 0, 36}, "prism.format")
        .formatButton.style.setStyleSheetMetrics("btnPush_Width 0")
        .formatButton.setIcon(.icons.icon(1, 18, .theme().res.atlasScale))
        .formatButton.setIconSize(18, 18)
        .formatButton.sigPressed += func|window = me|(button)
        {
            discard button
            window.format()
        }

        .liveEdit = CheckButton.create(.commandBar, "", {0, 0, 0, 36}, "prism.liveEdit")
        .liveEdit.style.setStyleSheetMetrics("btnPush_Width 0")
        .liveEdit.setState(.Checked)
        .liveEdit.sigChanged += func|window = me|(button)
        {
            discard button
            window.scheduleCompile()
        }

        .exampleCombo = ComboBox.create(.commandBar, {0, 0, 200, 36}, "prism.examples")
        .exampleCombo.sigChanged += func|window = me|(combo, index)
        {
            discard combo
            window.openExample(cast(ExampleKind) index)
        }
    }

    mtd createLayoutButton()
    {
        .layoutButton        = IconButton.create(.panels[0].header, .icons.icon(0, 18, .theme().res.atlasScale), {0, 0, 36, 36}, "prism.layout", flags: .Toggle)
        .layoutButton.margin = {8, 0, 0, 0}
        .layoutButton.setIconSize(18, 18)
        .layoutButton.setCheckIndicator(.Frame)
        .layoutButton.sendToBack()
        .layoutButton.dockStyle         = .Right
        .layoutButton.sigCheckedChanged += func|window = me|(button)
        {
            window.setComparisonEnabled(button.isChecked)
        }
    }

    mtd createStatusLine()
    {
        .statusBar                 = Wnd.create'Wnd(&.wnd, {0, 0, 0, 32})
        .statusBar.dockStyle       = .Bottom
        .statusBar.backgroundStyle = .InformationBar
        .statusBar.padding         = {Gutter, 4, Gutter, 4}
        .spinner                   = Spinner.create(.statusBar, {0, 0, 16, 16}, "prism.busy")
        .spinner.dockStyle         = .Left
        .spinner.margin            = {0, 4, 8, 4}
        .spinner.hide()
        .status = Label.create(.statusBar, "", {}, null, .SecondaryText)
        .status.dockStyle = .Center
        .status.setTextAlignment(.Left, .Center)
    }

    mtd createPanes()
    {
        .sourceSplit                 = SplitterCtrl.create(&.wnd, {}, false, "prism.split")
        .sourceSplit.dockStyle       = .Center
        .sourceSplit.backgroundStyle = .Transparent
        .sourcePanel                 = Wnd.create'Wnd(.sourceSplit)
        .sourcePanel.backgroundStyle = .Panel
        .sourcePanel.padding         = 8
        .createCommandBar()
        .editor = RichEditCtrl.create(.sourcePanel)
        .editor.dockStyle = .Center
        .editor.setLexer(&.lexer)
        .editor.setText(exampleSource(.Plasma))

        .viewerSplit = SplitterCtrl.create(.sourceSplit, {}, false, "prism.viewers")
        .viewerSplit.backgroundStyle = .Transparent
        for index in 2
        {
            let level: Swag.BuildCfgBackendOptimLevel = index == 0 ? .O0 : .O2
            let panel = ViewerPanel.create(.viewerSplit, .editor, level, &.cache)
            panel.sigChanged += func|window = me|(sender)
            {
                discard sender
                window.refreshStatus()
            }

            panel.sigCompileRequested += func|window = me|(sender)
            {
                discard sender
                window.compile()
            }

            panel.sigOptionsChanged += func|window = me|(sender)
            {
                discard sender
                window.scheduleCompile()
            }

            .panels.add(panel)
            let pane = .viewerSplit.addPane(panel, 540)
            pane.minimumSize = ViewerPanel.MinWidth
        }

        let sourcePane = .sourceSplit.addPane(.sourcePanel, 480)
        sourcePane.minimumSize = 300
        let viewersPane = .sourceSplit.addPane(.viewerSplit, 960)
        viewersPane.minimumSize = ViewerPanel.MinWidth
        .viewerSplit.setPaneVisible(1, false)
        .panels[0].selectViewer(.Render2D)
        .createLayoutButton()
        .refreshPaneLayout()
        .editor.sigChanged += func|window = me|(editor)
        {
            discard editor
            window.scheduleCompile()
        }
    }

    mtd refreshPaneLayout()
    {
        let gutter = .themeMetrics().panel_GutterSize
        .sourceSplit.margin = {gutter, gutter, gutter, gutter}
        .sourceSplit.items[1]!.minimumSize = .comparisonEnabled ? 2 * ViewerPanel.MinWidth + .themeMetrics().splitView_BarSize : ViewerPanel.MinWidth
        .applyLayout()
    }

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
            requests[index] = panel.request(source.toString())
        if .comparisonEnabled
        {
            // One native build can print the inspected function and run the same program.
            if requests[0].kind == .Microcode and requests[1].kind != .Microcode
            {
                requests[0].kind = requests[1].kind
                if requests[0].sameProgram(requests[1]) do
                    requests[1].stage = requests[0].stage
            }
            elif requests[1].kind == .Microcode and requests[0].kind != .Microcode
            {
                requests[1].kind = requests[0].kind
                if requests[0].sameProgram(requests[1]) do
                    requests[0].stage = requests[1].stage
            }
        }

        for panel, index in .panels where index == 0 or .comparisonEnabled do
            panel.compile(requests[index])
        .refreshStatus()
    }

    mtd shutdown()
    {
        .cancelEditTimer()
        if .formatStatus == .Working
        {
            Atomic.exchange(&.formatCancelled, 1)
            .formatTask.wait()
            if .formatTimer and !.isPendingDestroy do
                .removeTimer(.formatTimer!)
            .formatTimer  = null
            .formatStatus = .None
        }

        for panel in .panels do
            panel.shutdown()
        .cache.close()
    }

    mtd format()
    {
        if .formatStatus == .Working do
            return
        .cancelEditTimer()
        .formatSource    = .editor.text()
        .formatCancelled = 0
        .formatStatus    = .Working
        .formatButton.enable(false)
        .formatTimer = .app().addTimer(20'ms, me)
        .formatTask.submit(func|window = me|()
        {
            let result = catch window.formatter.format(window.formatSource.toString(), &window.formatCancelled) as error
            if error != null do
                window.formatResult = {failed: true}
            else do
                window.formatResult = result
        })
        .refreshStatus()
    }

    mtd finishFormat()
    {
        .removeTimer(.formatTimer!)
        .formatTimer = null
        .formatButton.enable()
        if .formatResult.failed do
            .formatStatus = .Failed
        elif .editor.text() != .formatSource do
            .formatStatus = .Changed
        else
        {
            .formatStatus = .Done
            if .editor.text() != .formatResult.text
            {
                let cursor = .editor.selectionEnd()
                .editor.pushUndo()
                .editor.selectAll()
                .editor.deleteSelection()
                .editor.insertText(.formatResult.text.toString())
                .editor.popUndo()
                .editor.setCursorPos(.editor.cursorFromLogicalPosition(cursor.lineIndex, cursor.charPosInLine))
                .editor.clearSelection()
                .scheduleCompile()
            }
        }

        .refreshStatus()
    }

    mtd cancelEditTimer()
    {
        if .editTimer and !.isPendingDestroy do
            .removeTimer(.editTimer!)
        .editTimer = null
    }

    mtd scheduleCompile()
    {
        .cancelEditTimer()
        if .liveEdit.isChecked() do
            .editTimer = .app().addTimer(150'ms, me)
    }

    mtd openExample(kind: ExampleKind)
    {
        .selectedExample = kind
        .editor.setText(exampleSource(kind))
        .panels[0].selectViewer(exampleViewer(kind))
        .exampleCombo.setSelectedIndex(cast(u32) kind, notify: false)
        .compile()
    }

    mtd refreshStatus()
    {
        var running = 0'u64
        for panel in .panels where panel.isRunning() do
            running += 1

        .spinner.show(running != 0 or .formatStatus == .Working)
        .status.toolTip = ""
        if running > 1 do
            .status.setText(Format.toString(appStrings().ui_RunningViewers, running).toString())
        elif running do
            .status.setText(appStrings().ui_Working)
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
                output.parse(.formatResult.text.toString())
                .status.toolTip = output.text
            }
        }

        .statusBar.applyLayout()
    }

    mtd retranslate()
    {
        .exampleCombo.clear()
        for label in [appStrings().ui_Plasma, appStrings().ui_Julia, appStrings().ui_GuiExample, appStrings().ui_Dot] do
            .exampleCombo.addItem(label)
        .exampleCombo.setSelectedIndex(cast(u32) .selectedExample, notify: false)
        .exampleCombo.toolTip = appStrings().ui_Examples
        .liveEdit.setText(appStrings().ui_AutoCompile)
        .liveEdit.toolTip = appStrings().ui_LiveEdit
        .formatButton.setText(appStrings().ui_Format)
        .formatButton.toolTip = appStrings().ui_FormatHint
        .runButton.setText(appStrings().ui_CompileVisible)
        .runButton.toolTip = appStrings().ui_CompileVisibleHint
        .commandBar.layoutFields()
        .layoutButton.setChecked(.comparisonEnabled)
        .layoutButton.toolTip = .comparisonEnabled ? appStrings().ui_OneViewer : appStrings().ui_TwoViewers
        .surface!.setTitle(appStrings().ui_WindowTitle)
        .refreshStatus()
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
        if evt.kind == .LanguageChanged do
            .retranslate()
        elif evt.kind == .ThemeChanged
        {
            .layoutButton.setIcon(.icons.icon(0, 18, .theme().res.atlasScale))
            .runButton.setIcon(.theme().icon(.Play, 18))
            .formatButton.setIcon(.icons.icon(1, 18, .theme().res.atlasScale))
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

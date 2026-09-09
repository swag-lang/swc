#global internal

using Core, Gui

// Owns the shared source and one or two independently configured viewers.
struct MainWindow
{
    using wnd: Wnd

    late
    {
        appearanceButton: *AppearanceButton
        exampleCombo:     *ComboBox
        liveEdit:         *CheckButton
        runButton:        *PushButton
        layoutButton:     *IconButton
        sourcePanel:      *Wnd
        editor:           *RichEditCtrl
        status:           *Label
        commandBar:       *Wnd
        statusBar:        *Wnd
        sourceSplit:      *SplitterCtrl
        viewerSplit:      *SplitterCtrl
    }

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
        result.createCommandBar()
        result.createStatusLine()
        result.createPanes()
        result.applyLanguage()
        result.retranslate()
        result.applyLayout()
        return result
    }

    mtd createCommandBar()
    {
        .commandBar                 = Wnd.create'Wnd(&.wnd, {0, 0, 0, 56})
        .commandBar.dockStyle       = .Top
        .commandBar.backgroundStyle = .CommandBar
        .commandBar.padding         = {Gutter, 10, Gutter, 10}
        .runButton                  = PushButton.create(.commandBar, appStrings().ui_CompileVisible, {0, 0, 180, 36}, "prism.run", .Strong)
        .runButton.dockStyle        = .Left
        .runButton.sigPressed       += func|window = me|(button)
        {
            discard button
            window.compile()
        }

        .exampleCombo            = ComboBox.create(.commandBar, {0, 0, 200, 36}, "prism.examples")
        .exampleCombo.dockStyle  = .Left
        .exampleCombo.margin     = {16, 0, 0, 0}
        .exampleCombo.sigChanged += func|window = me|(combo, index)
        {
            discard combo
            window.openExample(cast(ExampleKind) index)
        }

        .liveEdit           = CheckButton.create(.commandBar, "", {0, 0, 0, 36}, "prism.liveEdit")
        .liveEdit.dockStyle = .Left
        .liveEdit.margin    = {16, 0, 0, 0}
        .liveEdit.setState(.Checked)
        .liveEdit.sigChanged += func|window = me|(button)
        {
            discard button
            window.scheduleCompile()
        }

        .layoutButton = IconButton.create(.commandBar, .icons.icon(0, 18, .theme().res.atlasScale), {0, 0, 36, 36}, "prism.layout", flags: .Toggle)
        .layoutButton.setIconSize(18, 18)
        .layoutButton.setCheckIndicator(.Frame)
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
        .status                    = Label.create(.statusBar, "", {}, null, .SecondaryText)
        .status.dockStyle          = .Center
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
        .editor                      = RichEditCtrl.create(.sourcePanel)
        .editor.dockStyle            = .Center
        .editor.setLexer(&.lexer)
        .editor.setText(exampleSource(.Plasma))

        .viewerSplit = SplitterCtrl.create(.sourceSplit, {}, false, "prism.viewers")
        .viewerSplit.backgroundStyle = .Transparent
        for index in 2
        {
            let level: Swag.BuildCfgBackendOptimLevel = index == 0 ? .O0 : .O2
            let panel = ViewerPanel.create(.viewerSplit, .editor, level)
            panel.sigChanged += func|window = me|(sender)
            {
                discard sender
                window.refreshStatus()
            }

            .panels.add(panel)
            let pane = .viewerSplit.addPane(panel, 540)
            pane.minimumSize = ViewerPanel.MinWidth
        }

        let sourcePane = .sourceSplit.addPane(.sourcePanel, 480)
        sourcePane.minimumSize = 260
        let viewersPane = .sourceSplit.addPane(.viewerSplit, 960)
        viewersPane.minimumSize = ViewerPanel.MinWidth
        .viewerSplit.setPaneVisible(1, false)
        .panels[0].selectViewer(.Render2D)
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
        .viewerSplit.setPaneVisible(1, enabled)
        .refreshPaneLayout()
        if enabled do
            .viewerSplit.setPaneSize(0, (.viewerSplit.paddedClientRect().width - .themeMetrics().splitView_BarSize) / 2)
        .retranslate()
    }

    // Only visible viewers receive the source snapshot; the hidden comparison keeps its result.
    mtd compile()
    {
        .cancelEditTimer()
        let source = .editor.text()
        for panel, index in .panels where index == 0 or .comparisonEnabled do
            panel.compile(source.toString())
        .refreshStatus()
    }

    mtd shutdown()
    {
        .cancelEditTimer()
        for panel in .panels do
            panel.shutdown()
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
            .editTimer = .app().addTimer(700'ms, me)
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

        if running > 1 do
            .status.setText(Format.toString(appStrings().ui_RunningViewers, running).toString())
        else do
            .status.setText(running ? appStrings().ui_Working : appStrings().ui_Ready)
    }

    mtd retranslate()
    {
        .exampleCombo.clear()
        for label in [appStrings().ui_Plasma, appStrings().ui_Julia, appStrings().ui_GuiExample, appStrings().ui_Dot] do
            .exampleCombo.addItem(label)
        .exampleCombo.setSelectedIndex(cast(u32) .selectedExample, notify: false)
        .exampleCombo.toolTip = appStrings().ui_Examples
        .liveEdit.setText(appStrings().ui_LiveEdit)
        .runButton.setText(appStrings().ui_CompileVisible)
        .runButton.toolTip = appStrings().ui_CompileVisibleHint
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
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        elif evt.kind == .ThemeChanged
        {
            .layoutButton.setIcon(.icons.icon(0, 18, .theme().res.atlasScale))
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

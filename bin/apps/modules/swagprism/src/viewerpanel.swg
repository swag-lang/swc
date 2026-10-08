#global internal

using Core, Gui

// A comparison panel selects a viewer type and owns its independent compilation state.
struct ViewerPanel
{
    using wnd: Wnd

    late
    {
        cache:         *Pipeline.CompilationCache
        options:       *BuildOptions
        optionsButton: *IconButton
        header:        *Wnd
        optimCombo:    *ComboBox
        pauseButton:   *IconButton
        kindCombo:     *ComboBox
        sourceEditor:  *RichEditCtrl
    }

    defaultLevel:        Swag.BuildCfgBackendOptimLevel
    cached:              [3] (IViewer?)     // The viewer created for each `ViewerKind`, kept while the panel shows another.
    viewer:              IViewer?
    kind:                ViewerKind
    sigChanged:          SigArray'func||(*ViewerPanel)
    sigCompileRequested: SigArray'func||(*ViewerPanel)
    sigOptionsChanged:   SigArray'func||(*ViewerPanel)
}

impl ViewerPanel
{
    const MinWidth = 330.0

    func create(parent: *Wnd, sourceEditor: *RichEditCtrl, level: Swag.BuildCfgBackendOptimLevel, cache: *Pipeline.CompilationCache)->*ViewerPanel
    {
        with let result = Wnd.create'ViewerPanel(parent, "prism.viewerPanel")
        {
            .backgroundStyle = .Panel
            .padding         = 8
            .sourceEditor    = sourceEditor
            .cache           = cache
            .defaultLevel    = level
        }

        result.createHeader()
        result.createBuildOptions()
        result.retranslate()
        result.selectViewer(.Microcode)
        result.applyLayout()
        return result
    }

    // Creates the header row: the viewer type, then the optimization level, playback, and build
    // configuration actions docked to its right edge.
    mtd createHeader()
    {
        with .header = Wnd.create'Wnd(me, {0, 0, 0, 36})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {0, 0, 0, 8}
        }

        // Header fields follow their short entries instead of the default form-field width.
        with .kindCombo = ComboBox.create(.header, {}, "prism.viewer.kind")
        {
            .dockStyle = .Center
            .style.setStyleSheetMetrics("comboBox_Width 0")
            .sigChanged += func|panel = me|(?, index)
            {
                panel.selectViewer(cast(ViewerKind, index))
                panel.requestCompile()
            }
        }

        with .optionsButton = IconButton.create(.header, .theme().icon(.Options, 18), {0, 0, 36, 36}, "prism.buildOptions", flags: .Toggle)
        {
            .dockStyle = .Right
            .margin    = {8, 0, 0, 0}
            .setIconSize(18, 18)
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|panel = me|(button) { panel.showOptions(button.isChecked) }
        }

        with .pauseButton = IconButton.create(.header, .theme().icon(.Pause, 18), {0, 0, 36, 36}, "prism.pause", flags: .Toggle)
        {
            .dockStyle = .Right
            .margin    = {8, 0, 0, 0}
            .setIconSize(18, 18)
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|panel = me|(button)
            {
                panel.viewer!.setPaused(button.isChecked)
                panel.refreshPlayback()
            }
        }

        with .optimCombo = ComboBox.create(.header, {0, 0, 72, 36}, "prism.optimize")
        {
            .dockStyle = .Right
            .style.setStyleSheetMetrics("comboBox_Width 0")
            .margin = {8, 0, 0, 0}
            for name in ["O0", "O1", "O2"] do
                .addItem(name)
            .setSelectedIndex(cast(u32, me.defaultLevel), notify: false)
            .sigChanged += func|panel = me|(?, ?) { panel.requestCompile() }
        }
    }

    // Creates the build configuration editor, which takes the place of the viewer while it is open.
    mtd createBuildOptions()
    {
        with .options = BuildOptions.create(me)
        {
            .dockStyle = .Center
            .hide()
            .sigChanged += func|panel = me|(?)
            {
                panel.sigOptionsChanged.call(panel)
            }

            .sigReset += func|panel = me|(?)
            {
                panel.optimCombo.setSelectedIndex(cast(u32, panel.defaultLevel), notify: false)
                panel.requestCompile()
            }
        }
    }

    mtd selectViewer(kind: ViewerKind)
    {
        if .viewer and .kind == kind do
            return
        if .viewer
        {
            .viewer.shutdown()
            .viewer.window().hide()
        }

        .kind = kind
        let index = cast(u32, kind)
        if not .cached[index]
        {
            .cached[index] = createViewer(me, .sourceEditor, kind)
            .cached[index]!.window().dockStyle = .Center
            .cached[index]!.subscribeChanged(func|panel = me|(?) { panel.sigChanged.call(panel) })
        }

        .viewer = .cached[index]
        .viewer!.window().show(not .optionsButton.isChecked)
        .refreshPlayback()
        .kindCombo.setSelectedIndex(cast(u32, kind), notify: false)
        .applyLayout()
        .sigChanged.call(me)
    }

    mtd refreshPlayback()
    {
        .pauseButton.show(.viewer != null and .kind != .Microcode)
        let paused = .viewer ? .viewer.isPaused() : false
        .pauseButton.setChecked(paused)
        .pauseButton.setIcon(.theme().icon(paused ? .Play : .Pause, 18))
        .pauseButton.toolTip = paused ? appStrings().ui_Resume : appStrings().ui_Pause
        .header.applyLayout()
    }

    mtd showOptions(visible: bool)
    {
        .optionsButton.setChecked(visible)
        .options.show(visible)
        .viewer!.window().show(not visible)
        .applyLayout()
    }

    mtd request(source: string)->Pipeline.BuildRequest => {source: source, stage: .viewer!.inspectionStage(), kind: .kind, settings: .options.settings(cast(Swag.BuildCfgBackendOptimLevel, .optimCombo.selectedIndex))}

    mtd requestCompile() { .sigCompileRequested.call(me) }

    mtd compile(request: Pipeline.BuildRequest) { .viewer!.compile(request) }
    mtd shutdown() { .viewer!.shutdown() }
    mtd isRunning()->bool => .viewer!.isRunning()

    // Writes the tooltips and viewer names in the active language.
    mtd retranslate()
    {
        .optionsButton.toolTip = appStrings().ui_BuildOptions
        .optimCombo.toolTip    = appStrings().ui_Optimize
        .kindCombo.toolTip     = appStrings().ui_ViewerType

        // The entries follow the order of `ViewerKind`.
        .kindCombo.clear()
        for label in [appStrings().ui_Microcode, appStrings().ui_Render2D, appStrings().ui_Gui] do
            .kindCombo.addItem(label)
        .kindCombo.setSelectedIndex(cast(u32, .kind), notify: false)

        .refreshPlayback()
        .applyLayout()
    }
}

impl IWnd for ViewerPanel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .retranslate()
        }
        elif evt.kind == .ThemeChanged
        {
            .optionsButton.setIcon(.theme().icon(.Options, 18))
            .refreshPlayback()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

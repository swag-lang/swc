#global internal

using Core, Gui

struct ViewerSlot
{
    viewer: IViewer?
}

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
    sigCompileRequested: SigArray'func||(*ViewerPanel)
    sigOptionsChanged:   SigArray'func||(*ViewerPanel)
    cached:              [3] ViewerSlot
    viewer:              IViewer?
    kind:                ViewerKind
    sigChanged:          SigArray'func||(*ViewerPanel)
}

impl ViewerPanel
{
    const MinWidth = 330.0

    func create(parent: *Wnd, sourceEditor: *RichEditCtrl, level: Swag.BuildCfgBackendOptimLevel, cache: *Pipeline.CompilationCache)->*ViewerPanel
    {
        let result = Wnd.create'ViewerPanel(parent, "prism.viewerPanel")
        result.backgroundStyle        = .Panel
        result.padding                = 8
        result.sourceEditor           = sourceEditor
        result.cache                  = cache
        result.defaultLevel           = level
        result.header                 = Wnd.create'Wnd(result, {0, 0, 0, 36})
        result.header.dockStyle       = .Top
        result.header.backgroundStyle = .Transparent
        result.header.margin          = {0, 0, 0, 8}
        result.kindCombo              = ComboBox.create(result.header, {}, "prism.viewer.kind")
        result.kindCombo.dockStyle    = .Center

        // Header fields follow their short entries instead of the default form-field width.
        result.kindCombo.style.setStyleSheetMetrics("comboBox_Width 0")
        result.optionsButton           = IconButton.create(result.header, result.theme().icon(.Options, 18), {0, 0, 36, 36}, "prism.buildOptions", flags: .Toggle)
        result.optionsButton.dockStyle = .Right
        result.optionsButton.margin    = {8, 0, 0, 0}
        result.optionsButton.setIconSize(18, 18)
        result.optionsButton.setCheckIndicator(.Frame)
        result.optionsButton.sigCheckedChanged += func|panel = result|(button) { panel.showOptions(button.isChecked) }
        result.pauseButton           = IconButton.create(result.header, result.theme().icon(.Pause, 18), {0, 0, 36, 36}, "prism.pause", flags: .Toggle)
        result.pauseButton.dockStyle = .Right
        result.pauseButton.margin    = {8, 0, 0, 0}
        result.pauseButton.setIconSize(18, 18)
        result.pauseButton.setCheckIndicator(.Frame)
        result.pauseButton.sigCheckedChanged += func|panel = result|(button)
        {
            panel.viewer!.setPaused(button.isChecked)
            panel.refreshPlayback()
        }

        result.optimCombo = ComboBox.create(result.header, {0, 0, 72, 36}, "prism.optimize")
        result.optimCombo.dockStyle = .Right
        result.optimCombo.style.setStyleSheetMetrics("comboBox_Width 0")
        result.optimCombo.margin = {8, 0, 0, 0}
        for name in ["O0", "O1", "O2"] do
            result.optimCombo.addItem(name)
        result.optimCombo.setSelectedIndex(cast(u32) level, notify: false)
        result.optimCombo.sigChanged += func|panel = result|(combo, index)
        {
            discard combo
            discard index
            panel.requestCompile()
        }

        result.options = BuildOptions.create(result)
        result.options.dockStyle = .Center
        result.options.hide()
        result.options.sigChanged += func|panel = result|(options)
        {
            discard options
            panel.sigOptionsChanged.call(panel)
        }

        result.options.sigReset += func|panel = result|(options)
        {
            discard options
            panel.optimCombo.setSelectedIndex(cast(u32) panel.defaultLevel, notify: false)
            panel.viewer!.setOptimization(panel.defaultLevel)
            panel.requestCompile()
        }

        result.retranslate()
        result.selectViewer(.Microcode)
        result.kindCombo.sigChanged += func|panel = result|(combo, index)
        {
            discard combo
            panel.selectViewer(cast(ViewerKind) index)
            panel.requestCompile()
        }

        result.applyLayout()
        return result
    }

    mtd selectViewer(kind: ViewerKind)
    {
        if .viewer and .kind == kind do
            return
        if .viewer
        {
            .viewer!.shutdown()
            .viewer!.window().hide()
        }

        .kind = kind
        let index = cast(u32) kind
        if not .cached[index].viewer
        {
            .cached[index].viewer = createViewer(me, .sourceEditor, kind, cast(Swag.BuildCfgBackendOptimLevel) .optimCombo.selectedIndex)
            .cached[index].viewer!.window().dockStyle = .Center
            .cached[index].viewer!.subscribeChanged(func|panel = me|(sender)
            {
                discard sender
                panel.sigChanged.call(panel)
            })
        }

        .viewer = .cached[index].viewer
        .viewer!.setOptimization(cast(Swag.BuildCfgBackendOptimLevel) .optimCombo.selectedIndex)
        .viewer!.window().show(not .optionsButton.isChecked)
        .refreshPlayback()
        .kindCombo.setSelectedIndex(cast(u32) kind, notify: false)
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

    mtd request(source: string)->Pipeline.BuildRequest
    {
        return {source: String.from(source), stage: String.from(.viewer!.inspectionStage()), kind: .kind, settings: .options.settings(cast(Swag.BuildCfgBackendOptimLevel) .optimCombo.selectedIndex)}
    }

    mtd requestCompile() { .sigCompileRequested.call(me) }

    mtd compile(source: string) { .compile(.request(source)) }

    mtd compile(request: Pipeline.BuildRequest)
    {
        .viewer!.setOptimization(request.settings.optimization)
        .viewer!.compile(request)
    }

    mtd shutdown() { .viewer!.shutdown() }
    mtd isRunning()->bool => .viewer!.isRunning()

    mtd retranslate()
    {
        .optionsButton.toolTip = appStrings().ui_BuildOptions
        .optimCombo.toolTip    = appStrings().ui_Optimize
        .refreshPlayback()
        .kindCombo.toolTip = appStrings().ui_ViewerType
        .kindCombo.clear()
        .kindCombo.addItem(appStrings().ui_Microcode)
        .kindCombo.addItem(appStrings().ui_Render2D)
        .kindCombo.addItem(appStrings().ui_Gui)
        .kindCombo.setSelectedIndex(cast(u32) .kind, notify: false)
        .applyLayout()
    }
}

impl IWnd for ViewerPanel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        elif evt.kind == .ThemeChanged
        {
            .optionsButton.setIcon(.theme().icon(.Options, 18))
            .refreshPlayback()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

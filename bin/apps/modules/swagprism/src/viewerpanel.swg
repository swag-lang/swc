#global internal

using Core, Gui, Pixel

/*
One column of results: a viewer under a header of quiet menus, with its own build.

The header names what the column shows and carries its settings as quiet menus — the view, the
stage of the instructions, the optimization level — with a reading at its right: the count of the
instructions, or the pause of a running preview. Beside another build, a column of instructions
heads itself with its count instead, large and light, and with what it gains in Arc. Stage by
stage, the frieze is the header. The build configuration takes the viewer's place when asked for,
its preset and its actions in the header.
*/
struct ViewerPanel
{
    using wnd: Wnd

    late
    {
        cache:         *Pipeline.CompilationCache
        options:       *BuildOptions
        sourceEditor:  *RichEditCtrl
        viewMenu:      *IconButton
        stageMenu:     *IconButton
        optimMenu:     *IconButton
        pauseButton:   *IconButton
        presetMenu:    *IconButton
        restoreButton: *IconButton
        closeButton:   *IconButton
    }

    defaultLevel:        Swag.Build.BackendOptimLevel
    level:               Swag.Build.BackendOptimLevel
    cached:              [3] (IViewer?)     // The viewer created for each `ViewerKind`, kept while the panel shows another.
    viewer:              IViewer?
    kind:                ViewerKind
    layout:              PanelLayout
    showingOptions:      bool
    gain:                String     // What this build gains over the other one, beside its count.
    sigChanged:          SigArray'func||(*Wnd)
    sigCompileRequested: SigArray'func||(*Wnd)
    sigOptionsChanged:   SigArray'func||(*Wnd)
    sigLiveEditChanged:  SigArray'func||(bool)
}

// Identities of the entries of the quiet menus. A menu borrows the identity of each entry, so they
// are constants.
const ViewIds  = ["prism.view.microcode", "prism.view.render2d", "prism.view.gui"]
const LevelIds = ["O0", "O1", "O2"]

// Returns the name of the viewer `kind`, as its menu and the lens write it.
func viewerName(kind: ViewerKind)->string
{
    switch #complete kind
    {
    case .Microcode: return appStrings().ui_Microcode
    case .Render2D:  return appStrings().ui_Render2D
    case .Gui:       return appStrings().ui_Gui
    }
}

impl ViewerPanel
{
    const MinWidth  = 300.0
    const CompareHeaderHeight = 44.0     // A header carrying the count of the instructions, large.
    const HeaderGap = 20.0               // Air between the header and what it heads.
    const CountSize = 32'u32             // Size of the count heading a compared build.

    // Builds a panel showing the microcode viewer, with its header and build options.
    func create(parent: *Wnd, sourceEditor: *RichEditCtrl, level: Swag.Build.BackendOptimLevel, cache: *Pipeline.CompilationCache)->*ViewerPanel
    {
        with let result = Wnd.create'ViewerPanel(parent, "prism.viewerPanel")
        {
            .backgroundStyle = .Transparent
            .sourceEditor    = sourceEditor
            .cache           = cache
            .defaultLevel    = level
            .level           = level
        }

        result.createHeader()
        result.createBuildOptions()
        result.selectViewer(.Microcode)
        result.retranslate()
        return result
    }

    // Creates the quiet controls of the header; which of them show depends on what the panel shows.
    mtd createHeader()
    {
        with .viewMenu = createQuietMenu(me, "prism.viewMenu", heading: true)
        {
            .sigPressed += func|panel = me|(_) { panel.showViewMenu() }
        }

        with .stageMenu = createQuietMenu(me, "prism.stageMenu")
        {
            .sigPressed += func|panel = me|(_) { panel.showStageMenu() }
        }

        with .optimMenu = createQuietMenu(me, "prism.optimize")
        {
            .sigPressed += func|panel = me|(_) { panel.showOptimMenu() }
        }

        with .pauseButton = createQuietButton(me, "prism.pause")
        {
            .sigPressed += func|panel = me|(_) { panel.setPaused(not panel.viewer!.isPaused()) }
        }

        with .presetMenu = createQuietMenu(me, "prism.preset")
        {
            .sigPressed += func|panel = me|(_) { panel.showPresetMenu() }
        }

        with .restoreButton = createQuietButton(me, "prism.restoreBuild")
        {
            .sigPressed += func|panel = me|(_) { panel.options.reset() }
        }

        with .closeButton = createQuietButton(me, "prism.closeBuild")
        {
            .sigPressed += func|panel = me|(_) { panel.showOptions(false) }
        }
    }

    // Creates the build configuration, which takes the place of the viewer while it is shown.
    mtd createBuildOptions()
    {
        with .options = BuildOptions.create(me)
        {
            .hide()
            .sigChanged += func|panel = me|(_)
            {
                panel.refreshHeader()
                panel.sigOptionsChanged.call(panel)
            }

            .sigReset += func|panel = me|(_)
            {
                panel.level = panel.defaultLevel
                panel.refreshHeader()
                panel.requestCompile()
            }
        }
    }

    // Switches the panel to the viewer of `kind`, creating it the first time and keeping it for
    // later switches.
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
            .cached[index]!.subscribeChanged(func|panel = me|(_)
            {
                panel.refreshHeader()
                panel.sigChanged.call(panel)
            })
        }

        .viewer = .cached[index]
        .viewer!.window().show(not .showingOptions)
        .micro()?.setLayout(.layout)
        .refreshHeader()
        .sigChanged.call(me)
    }

    // Returns the microcode viewer when the panel shows it.
    mtd micro()->*MicrocodeViewer?
    {
        if .kind != .Microcode or not .viewer do
            return null
        return assume cast(*MicrocodeViewer, .viewer.window())
    }

    // Returns the microcode viewer of the panel, shown or kept, once it has been created.
    mtd cachedMicro()->*MicrocodeViewer?
    {
        let viewer = .cached[cast(u32, ViewerKind.Microcode)]
        if not viewer do
            return null
        return assume cast(*MicrocodeViewer, viewer.window())
    }

    // Returns the preview when the panel shows one.
    mtd preview()->*PreviewViewer?
    {
        if .kind == .Microcode or not .viewer do
            return null
        return assume cast(*PreviewViewer, .viewer.window())
    }

    // Lays the panel out beside the source, stage by stage, or beside another build.
    mtd setLayout(layout: PanelLayout)
    {
        .layout = layout
        .micro()?.setLayout(layout)
        .refreshHeader()
    }

    // Builds with the optimization `level`, compiling again when `notify` asks.
    mtd setLevel(level: Swag.Build.BackendOptimLevel, notify = true)
    {
        .level = level
        .refreshHeader()
        if notify do
            .requestCompile()
    }

    // Pauses or resumes the running preview.
    mtd setPaused(paused: bool)
    {
        if not .viewer do
            return
        .viewer.setPaused(paused)
        .refreshHeader()
        .sigChanged.call(me)
    }

    // Shows the build configuration in place of the viewer, or the viewer again.
    mtd showOptions(visible: bool)
    {
        .showingOptions = visible
        .options.show(visible)
        .viewer!.window().show(not visible)
        if visible do
            .options.editor.setFocus()
        .refreshHeader()
        .sigChanged.call(me)
    }

    // Shows whether the source compiles again after each edit on every preview of the panel.
    mtd syncLiveEdit(on: bool)
    {
        for kind in [ViewerKind.Render2D, ViewerKind.Gui] where .cached[cast(u32, kind)]
        {
            let preview = assume cast(*PreviewViewer, .cached[cast(u32, kind)]!.window())
            preview.setLiveEdit(on)
        }
    }

    // The request compiling `source` for this panel: its viewer and its build settings.
    mtd request(source: string)->Pipeline.BuildRequest
    {
        return {source: source, inspect: .kind == .Microcode, kind: .kind, settings: .options.settings(.level)}
    }

    // `requestCompile` asks the window to recompile; the others forward to the active viewer.
    mtd requestCompile() { .sigCompileRequested.call(me) }
    mtd compile(request: Pipeline.BuildRequest) { .viewer!.compile(request) }
    mtd shutdown() { .viewer!.shutdown() }
    mtd isRunning()->bool => .viewer!.isRunning()

    // Returns the count of instructions the panel lists, or `U32.Max` when it lists none.
    mtd listedInstructions()->u32
    {
        let micro = .micro()
        if not micro do
            return Swag.U32.Max
        let shown = micro.shown()
        return shown ? shown.instructions : Swag.U32.Max
    }

    // Shows the views of the panel under its menu, the one in use checked.
    mtd showViewMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id, index in ViewIds do
            menu.addRadioItem(viewerName(cast(ViewerKind, cast(u32, index))), id, checked: cast(u64, .kind) == index)

        let chosen = menu.doModal(.viewMenu, autoDestroy: true) orelse ""
        for id, index in ViewIds where chosen == id
        {
            .selectViewer(cast(ViewerKind, cast(u32, index)))
            .requestCompile()
        }
    }

    // Shows the stages under their menu, the one listed checked. Choosing one compiles nothing:
    // the build printed them all.
    mtd showStageMenu()
    {
        let micro = .micro()
        if not micro do
            return
        let menu   = MenuCtrl.createPopup(me, owner: me)
        let labels = Pipeline.stageLabels()
        for id, index in Pipeline.Stages do
            menu.addRadioItem(labels[index], id, checked: micro.stage == index)

        let chosen = menu.doModal(.stageMenu, autoDestroy: true) orelse ""
        for id, index in Pipeline.Stages where chosen == id do
            micro.setStage(cast(u32, index))
    }

    // Shows the optimization levels under their menu, the one in use checked.
    mtd showOptimMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id, index in LevelIds do
            menu.addRadioItem(id, id, checked: cast(u64, .level) == index)

        let chosen = menu.doModal(.optimMenu, autoDestroy: true) orelse ""
        for id, index in LevelIds where chosen == id do
            .setLevel(cast(Swag.Build.BackendOptimLevel, cast(u8, index)))
    }

    // Shows the build presets under their menu, the one in use checked.
    mtd showPresetMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id, index in BuildOptions.PresetNames do
            menu.addRadioItem(id, id, checked: cast(u64, .options.preset) == index)

        let chosen = menu.doModal(.presetMenu, autoDestroy: true) orelse ""
        for id, index in BuildOptions.PresetNames where chosen == id do
            .options.setPreset(cast(Pipeline.BuildPreset, cast(u32, index)))
    }

    // Returns the height of the header, which stage by stage has none.
    mtd headerHeight()->f32
    {
        if .layout == .Stages and not .showingOptions do
            return 0
        if .layout == .Compare and .kind == .Microcode and not .showingOptions do
            return CompareHeaderHeight
        return QuietHeight
    }

    // Writes the header's menus and buttons and shows the ones that apply.
    mtd refreshHeader()
    {
        let strings  = appStrings()
        let header   = .headerHeight() > 0
        let options  = header and .showingOptions
        let compared = header and not options and .layout == .Compare and .kind == .Microcode
        let plain    = header and not options and not compared

        .viewMenu.show(plain)
        .stageMenu.show(plain and .kind == .Microcode and .layout == .Column)
        .optimMenu.show(header and not options)
        .pauseButton.show(plain and .kind != .Microcode)
        .presetMenu.show(options)
        .restoreButton.show(options)
        .closeButton.show(options)

        setQuietText(.viewMenu, viewerName(.kind))
        let micro = .micro()
        if micro do
            setQuietText(.stageMenu, Pipeline.stageLabels()[Math.min(micro.stage, Pipeline.Stages.count - 1)])
        setQuietText(.optimMenu, LevelIds[cast(u64, .level)])
        let paused = .viewer != null and .viewer.isPaused()
        setQuietText(.pauseButton, paused ? strings.ui_Resume : strings.ui_Pause)
        setQuietText(.presetMenu, BuildOptions.PresetNames[cast(u64, .options.preset)])
        setQuietText(.restoreButton, strings.cmd_RestoreBuild)
        setQuietText(.closeButton, strings.ui_CloseBuild)

        .viewMenu.toolTip    = strings.ui_ViewerType
        .stageMenu.toolTip   = strings.ui_Stage
        .optimMenu.toolTip   = strings.ui_Optimize
        .presetMenu.toolTip  = strings.ui_BuildPreset
        .pauseButton.toolTip = paused ? strings.cmd_ResumePreview : strings.cmd_PausePreview

        .arrangeParts()
        .invalidate()
    }

    // Places the header's controls, from the left for the settings and from the right for the
    // actions, then the viewer or the build configuration under it.
    mtd arrangeParts()
    {
        // The panel lays itself out while its parts are still being created.
        if .options == null do
            return

        let client = .clientRect()
        let height = .headerHeight()
        let rowTop = height - QuietHeight

        var x = 0'f32
        if .showingOptions do
            x = .titleWidth() + 8
        elif .layout == .Compare and .kind == .Microcode do
            x = client.width
        for control in [.viewMenu, .stageMenu, .presetMenu] where control.isLocallyVisible()
        {
            control.setPosition(Math.Rectangle{x, rowTop, control.position.width, QuietHeight})
            x += control.position.width + 4
        }

        var right = client.width
        for control in [.closeButton, .restoreButton, .pauseButton] where control.isLocallyVisible()
        {
            right -= control.position.width
            control.setPosition(Math.Rectangle{right, rowTop, control.position.width, QuietHeight})
            right -= 4
        }

        // The optimization level follows the view and the stage beside the source, and stands at
        // the right beside another build.
        let optimX = .layout == .Compare ? right - .optimMenu.position.width : x
        .optimMenu.setPosition(Math.Rectangle{optimX, rowTop, .optimMenu.position.width, QuietHeight})

        let bodyTop = height > 0 ? height + HeaderGap : 0'f32
        let body    = Math.Rectangle{0, bodyTop, client.width, Math.max(0'f32, client.height - bodyTop)}
        .options.setPosition(body)
        if .viewer do
            .viewer.window().setPosition(body)
    }

    // Returns the width of the title the build configuration is headed with.
    mtd titleWidth()->f32  => Painter.measureString(appStrings().ui_BuildHeading, .titleFont()).width
    mtd titleFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize, .Bold)

    // Writes the tooltips and the menus in the active language.
    mtd retranslate()
    {
        .refreshHeader()
    }
}

impl IWnd for ViewerPanel
{
    // Writes the words of the header that are not controls: the title of the build
    // configuration, the count of a compared build, the count of a listed stage.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let height = .headerHeight()
        if height == 0 do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let theme   = .theme()
        let metrics = .themeMetrics()
        let centerY = height - QuietHeight * 0.5
        if .showingOptions
        {
            let font = .titleFont()
            painter.drawString(0, font.opticalLineTop(centerY), appStrings().ui_BuildHeading, font, colors.text)
            return
        }

        let count = .listedInstructions()
        if count == Swag.U32.Max do
            return

        // Beside another build, the count heads the column, large and light, with what the build
        // gains in Arc; beside the source, it is a soft reading at the right.
        let unit     = count == 1 ? appStrings().ui_InstructionOne : appStrings().ui_InstructionMany
        let wordFont = theme.createDefaultFont(metrics.defaultFontSize)
        if .layout == .Compare
        {
            let figureFont = theme.createDefaultFont(CountSize)
            let figure     = Format.toString("%", count)
            painter.drawString(0, figureFont.opticalLineTop(centerY), figure, figureFont, colors.text)
            var x = Painter.measureString(figure, figureFont).width + 12
            painter.drawString(x, wordFont.opticalLineTop(centerY + 3), unit, wordFont, colors.softText)
            if not .gain.isEmpty()
            {
                let gainFont = theme.createDefaultFontFs(metrics.defaultFontSize)
                x += Painter.measureString(unit, wordFont).width + 16
                painter.drawString(x, gainFont.opticalLineTop(centerY + 3), .gain, gainFont, colors.arc)
            }

            return
        }

        let reading = countText(count)
        let width   = Painter.measureString(reading, wordFont).width
        painter.drawString(.clientRect().width - width, wordFont.opticalLineTop(centerY), reading, wordFont, colors.faintText)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrangeParts()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged: .retranslate()
        case .ThemeChanged:    .refreshHeader()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

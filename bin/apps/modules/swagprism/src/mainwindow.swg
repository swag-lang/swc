#global internal

using Core, Gui, Pixel

// What the reading of the window says about the formatter.
enum FormatStatus
{
    None        // Nothing to report, or a compilation has replaced the report.
    Working     // The formatter is running.
    Done        // The formatted source replaced the editor text.
    Failed      // The formatter stopped on an error, which the sheet shows.
    Changed     // The source was edited while it was formatted, so the result was dropped.
}

// The ways the window lays the work out.
enum PrismView
{
    Columns     // The source and one result, separated by a hairline.
    Stages      // The instructions alone, stage by stage.
    Compare     // Two builds of the source side by side, the reference at the left.
}

/*
The window of Swag Prism: the source, and what the compiler makes of it.

Beside the source, one column shows a result: the instructions of the first function, the picture
a `shade` function paints, or the interface a `buildView` function builds. Stage by stage, the
instructions take the window and a frieze steps through what each pass did. Two builds of the same
source can stand side by side, the reference at the left.

Everything else is asked for. Every command is an entry of the lens, which `Ctrl K` opens (and
`Space` where nothing types); the readings of the build are in the sheet (`Ctrl I`); the window
keeps only a hint line and the reading of the last build at its foot.
*/
struct MainWindow
{
    using wnd: Wnd

    late
    {
        appearanceButton: *AppearanceButton
        editor:           *RichEditCtrl
        exampleMenu:      *IconButton
        lens:             *Lens.View
        infoSheet:        *InfoSheet
        hintLine:         *HintLine
        readingLine:      *HintLine
    }

    cache:           Pipeline.CompilationCache
    formatter:       Pipeline.SourceFormatter
    formatTask:      Swag.Task
    formatSource:    String
    formatResult:    Pipeline.Result
    formatStatus:    FormatStatus
    editTimer:       *Timer?
    selectedExample: ExampleKind
    panels:          Array'*ViewerPanel     // The main build, then the reference it is compared with.
    icons:           IconSet
    lexer:           RichEditLexerSwag
    language:        String
    themeIndex:      u32
    view:            PrismView
    liveEdit:        bool = true
    listingForm:     ListingForm
    showSource:      bool
    doorKnown:       bool     // Whether the reader has opened the lens; the hint line stops teaching it then.
}

impl MainWindow
{
    const WindowWidth  = 1280's32
    const WindowHeight = 800's32
    const MinWidth     = 1080.0
    const MinHeight    = 560.0

    // The measures of the page: the air above the headers, under the columns, at the sides and
    // around the hairline between the columns.
    const TopGap         = 36.0
    const FooterHeight   = 96.0
    const MaxSideMargin  = 96.0
    const MaxHalfGutter  = 64.0
    const MinSideMargin  = 32.0
    const MinHalfGutter  = 24.0
    const SourceTitleGap = 12.0     // Air between the name of the source and the menu of examples.

    // Builds the window: the source, the results, the foot, the sheet and the lens.
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "prism.mainWindow")
        let surface = unwrap result.surface
        surface.setView(result)
        result.icons.setup(result.app().renderer, prismIcons())
        surface.minSize        = {MinWidth, MinHeight}
        result.backgroundStyle = .Window
        result.language        = ReferenceLanguage

        result.createAppearanceButton()
        result.createSourceColumn()
        result.createFoot()
        result.infoSheet = InfoSheet.create(result, "prism.information")
        result.createPanels()
        result.createLens()
        result.applyLanguage()
        result.applyView(.Columns)
        return result
    }

    // Returns an application glyph at the size of a lens row.
    mtd icon(kind: PrismIcon)->Icon => .icons.icon(cast(s32, kind), cast(s32, .themeMetrics().menuPopup_IconSize), .theme().res.atlasScale)

    // Creates the owner of the palette and language the reader picks, which persists them and
    // opens the About box. Its choices are lens entries, so the button itself stays hidden.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(unwrap .surface, "prism.appearance")
        {
            .hide()
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

            .sigAboutRequested += func|window = me|(_)
            {
                window.showAbout()
            }
        }
    }

    // Creates the source column: its editor, and the menu of examples beside its name.
    mtd createSourceColumn()
    {
        with .exampleMenu = IconButton.createQuiet(me, "prism.examples")
        {
            .sigPressed += func|window = me|(_) { window.showExampleMenu() }
        }

        with .editor = RichEditCtrl.create(me)
        {
            .lineSpacing = ListingView.LineSpacing
            .setFlags(.LineNumbers)
            .setLexer(&me.lexer)
            .setText(exampleSource(.Plasma))
            .sigChanged    += func|window = me|(_) { window.scheduleCompile() }
            .sigCaretMoved += func|window = me|(_) { window.refreshCaretPlace() }
        }

        // The editor takes `Enter` with any modifier as a new line; `Ctrl Enter` compiles instead,
        // and its character must not reach the text.
        .hookOnChildEvent = func|window = me|(_, evt)->bool
        {
            if evt is KeyEvent as key where key.key == .Return and key.modifiers.has(.Control) and not window.lens.isOpen()
            {
                if key.kind == .Pressed do
                    window.compile(force: true)
                key.accepted = true
                return true
            }

            return false
        }
    }

    // Creates the main build, which opens on the picture of the first example, and the reference
    // build it can be compared with, which opens on unoptimized instructions.
    mtd createPanels()
    {
        .createViewerPanel(.O2)
        .createViewerPanel(.O0)
        .panels[0].selectViewer(.Render2D)
        .panels[1].hide()
    }

    // Creates one viewer panel and routes its requests to the window.
    mtd createViewerPanel(level: Swag.Build.BackendOptimLevel)
    {
        with let panel = ViewerPanel.create(me, .editor, level, &.cache)
        {
            .sigChanged          += func|window = me|(_) { window.refreshStatus() }
            .sigCompileRequested += func|window = me|(_) { window.compile() }
            .sigOptionsChanged   += func|window = me|(_) { window.scheduleCompile() }
            .sigLiveEditChanged  += func|window = me|(on) { window.setLiveEdit(on) }
        }

        .panels.add(panel)
    }

    // Creates the foot of the window: the hint line at the left, the reading of the last build at
    // the right.
    mtd createFoot()
    {
        with .hintLine = HintLine.create(me, "prism.hint")
        {
            .setAlignment(.Leading)
        }

        with .readingLine = HintLine.create(me, "prism.reading")
        {
            .setAlignment(.Trailing)
        }
    }

    // Lays the work out as `view`: the source and one result, the instructions stage by stage, or
    // two builds side by side, and compiles for the panels it shows.
    mtd setView(view: PrismView)
    {
        .applyView(view)
        .compile()
    }

    // Lays the work out as `view`, compiling nothing.
    mtd applyView(view: PrismView)
    {
        .view = view
        if view == .Stages
        {
            .panels[0].selectViewer(.Microcode)
            .panels[0].showOptions(false)
        }

        let compare = view == .Compare
        .editor.show(view == .Columns)
        .exampleMenu.show(view == .Columns)
        .panels[1].show(compare)
        .panels[0].setLayout(view == .Columns ? PanelLayout.Column : (compare ? PanelLayout.Compare : PanelLayout.Stages))
        .panels[1].setLayout(.Compare)
        .retranslate()
    }

    // Returns the room of the page: the side margin and half the gutter between the columns, which
    // both shrink with a narrow window.
    mtd sideMargin()->f32 => Math.round(Math.clamp(.clientRect().width * 0.075, MinSideMargin, MaxSideMargin))
    mtd halfGutter()->f32 => Math.round(Math.clamp(.clientRect().width * 0.05, MinHalfGutter, MaxHalfGutter))

    // Places the source and the results on the page of the window for the view in force.
    mtd arrangeParts()
    {
        // The window lays itself out while its parts are still being created.
        if .panels.count < 2 do
            return

        let client = .clientRect()
        let margin = .sideMargin()
        let gutter = .halfGutter()
        let top    = .stripInset() + TopGap
        let height = Math.max(0'f32, client.height - FooterHeight - top)
        let center = Math.round(client.width * 0.5)
        let left   = Math.Rectangle{margin, top, Math.max(0'f32, center - gutter - margin), height}
        let right  = Math.Rectangle{center + gutter, top, Math.max(0'f32, client.width - margin - center - gutter), height}

        // The foot reads at the sides of the page.
        .padding.x = margin
        .padding.z = margin

        switch .view
        {
        case .Columns:
            let editorTop = top + .themeMetrics().quiet_Height + ViewerPanel.HeaderGap
            .exampleMenu.setPosition(Math.Rectangle{margin + .sourceTitleWidth() + SourceTitleGap, top, .exampleMenu.position.width, .themeMetrics().quiet_Height})

            // The source is text on the ground: it may run into the gutter, short of the hairline.
            let editorWidth = Math.max(0'f32, center - MinHalfGutter - margin)
            .editor.setPosition(Math.Rectangle{margin, editorTop, editorWidth, Math.max(0'f32, top + height - editorTop)})
            .panels[0].setPosition(right)

        case .Compare:
            .panels[1].setPosition(left)
            .panels[0].setPosition(right)

        case .Stages:
            .panels[0].setPosition(Math.Rectangle{margin, top, Math.max(0'f32, client.width - 2 * margin), height})
        }

        .hintLine.itf.onLayout()
        .readingLine.itf.onLayout()
        .invalidate()
    }

    // Returns the name of the example the source started from, as its column writes it.
    mtd sourceTitle()->string    => exampleFileName(.selectedExample)
    mtd sourceTitleFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize, .Bold)
    mtd sourceTitleWidth()->f32  => Painter.measureString(.sourceTitle(), .sourceTitleFont()).width

    // One native build can print the inspected function and run the same program: the microcode
    // request takes the kind of the native one, which inspects the function when both compile the
    // same program.
    func shareNativeBuild(microcode, native: *Pipeline.BuildRequest)
    {
        microcode.kind = native.kind
        if microcode.sameProgram(native[]) do
            native.inspect = true
    }

    // Returns whether the panel `index` shows in the view in force.
    mtd isShown(index: u64)->bool => index == 0 or .view == .Compare

    // Compiles the source for the panels that show; a hidden panel keeps its result.
    mtd compile(force = false)
    {
        .cancelEditTimer()
        if .formatStatus != .Working do
            .formatStatus = .None
        if force do
            .cache.invalidate()
        let source = .editor.text()
        var requests: [2] Pipeline.BuildRequest
        for panel, index in .panels where .isShown(index) do
            requests[index] = panel.request(source)
        if .view == .Compare
        {
            if requests[0].kind == .Microcode and requests[1].kind != .Microcode do
                shareNativeBuild(&requests[0], &requests[1])
            elif requests[1].kind == .Microcode and requests[0].kind != .Microcode do
                shareNativeBuild(&requests[1], &requests[0])
        }

        for panel, index in .panels where .isShown(index) do
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
            .formatTask.cancel()
            .formatTask.wait()
            .formatStatus = .None
        }

        for panel in .panels do
            panel.shutdown()
        .cache.close()
    }

    // Formats the editor source on a worker; `finishFormat` applies the result when the task's
    // event arrives.
    mtd format()
    {
        if .formatStatus == .Working do
            return
        .cancelEditTimer()
        .formatSource = .editor.text()
        .formatStatus = .Working
        .formatTask.submit(func|window = me|()
        {
            var errorOutcome: Swag.Error
            catch { window.formatResult = try window.formatter.format(window.formatSource) } as errorOutcome
            let error = errorOutcome.value()
            if error != null do
                window.formatResult.failed = true
        },
                           .taskNotifier(&.formatTask))
        .refreshStatus()
    }

    // Applies a finished format as one undo step, unless it failed or the source changed while it
    // ran, and recompiles what it rewrote.
    mtd finishFormat()
    {
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
        if .liveEdit do
            .editTimer = .addTimer(150'ms)
    }

    // Compiles again after each edit, or only when asked.
    mtd setLiveEdit(on: bool)
    {
        .liveEdit = on
        for panel in .panels do
            panel.syncLiveEdit(on)
        if on do
            .scheduleCompile()
        else do
            .cancelEditTimer()
    }

    // Loads example `kind` into the editor, shows it in the viewer it was written for, and
    // compiles it.
    mtd openExample(kind: ExampleKind)
    {
        .selectedExample = kind
        .editor.setText(exampleSource(kind))
        .panels[0].selectViewer(exampleViewer(kind))
        .retranslate()
        .compile()
    }

    // Shows the examples under their menu, the one the source started from checked.
    mtd showExampleMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id, index in ExampleIds do
            menu.addRadioItem(exampleName(cast(ExampleKind, cast(u32, index))), id, checked: cast(u64, .selectedExample) == index)

        let chosen = menu.doModal(.exampleMenu, autoDestroy: true) orelse ""
        for id, index in ExampleIds where chosen == id do
            .openExample(cast(ExampleKind, cast(u32, index)))
    }

    // Returns what the window reports about its latest work: the viewers still compiling, the
    // outcome of a format, or the reading of the main build.
    mtd reading()->String
    {
        var running = 0'u64
        for panel, index in .panels where .isShown(index) and panel.isRunning() do
            running += 1

        let strings = appStrings()
        if running > 1 do
            return Format.toString(strings.ui_RunningViewers, running)
        if running do
            return strings.ui_Working

        switch #complete .formatStatus
        {
        case .None:    return .panels[0].viewer!.reading()
        case .Working: return strings.ui_Formatting
        case .Done:    return strings.ui_Formatted
        case .Changed: return strings.ui_FormatChanged
        case .Failed:  return strings.ui_FormatFailed
        }
    }

    // Writes the reading at the foot, compares the two builds, and keeps the sheet current.
    mtd refreshStatus()
    {
        .applyListingOptions()
        .readingLine.setReading(.reading())
        .refreshComparison()
        .refreshHints()
        if .infoSheet.isLocallyVisible() do
            .refreshInformation()
    }

    // Teaches the keys of the view in force: the steps stage by stage, and while the lens has not
    // been opened yet, compiling and the lens itself.
    mtd refreshHints()
    {
        let strings = appStrings()
        .hintLine.clearHints()
        if .view == .Stages
        {
            let micro = .panels[0].micro()
            if micro and not micro.inspection.steps.isEmpty()
            {
                let place = Format.toString(strings.hint_Steps, micro.step + 1, micro.inspection.steps.count)
                .hintLine.addHint(strings.key_Steps, place)
            }
        }
        elif not .doorKnown
        {
            if .view == .Columns do
                .hintLine.addHint(strings.key_Compile, strings.hint_Compile)
            .hintLine.addHint(strings.key_Lens, strings.hint_Lens)
        }

        .refreshCaretPlace()
    }

    // Once the hint line has stopped teaching the lens, its place under the source says where the
    // caret is: the line and the column, counted from one.
    mtd refreshCaretPlace()
    {
        if not .doorKnown or .view != .Columns
        {
            .hintLine.setReading(null)
            return
        }

        let line   = .editor.cursorLogicalLineIndex() + 1
        let column = .editor.cursorLogicalCharPos() + 1
        .hintLine.setReading(Format.toString(appStrings().ui_CaretPlace, line, column))
    }

    // Beside another build, the main build says what it gains over the reference, and its
    // listing how its innermost loop changed.
    mtd refreshComparison()
    {
        let main      = .panels[0]
        let reference = .panels[1]
        main.gain.clear()
        let mainMicro = main.micro()
        if mainMicro do
            mainMicro.listing.setNote("")
        if .view != .Compare do
            return

        let mine   = main.listedInstructions()
        let theirs = reference.listedInstructions()
        if mine != Swag.U32.Max and theirs != Swag.U32.Max and theirs != 0
        {
            let percent = (cast(f64, mine) - cast(f64, theirs)) * 100 / cast(f64, theirs)
            let rounded = cast(s64, Math.round(percent))
            main.gain.append(signOf(rounded))
            main.gain.appendFormat("% %%", Math.abs(rounded))
        }

        let referenceMicro = reference.micro()
        if mainMicro and referenceMicro
        {
            let mineShown   = mainMicro.shown()
            let theirsShown = referenceMicro.shown()
            if mineShown and theirsShown
            {
                let mineLoop   = mineShown.innermostLoop()
                let theirsLoop = theirsShown.innermostLoop()
                if mineLoop.first != Swag.U64.Max and theirsLoop.first != Swag.U64.Max do
                    mainMicro.listing.setNote(Format.toString(appStrings().ui_LoopNote, theirsLoop.instructions, mineLoop.instructions))
            }
        }

        main.invalidate()
    }

    // Writes the window title, the menus and the hints in the active language.
    mtd retranslate()
    {
        .exampleMenu.setQuietText(appStrings().ui_Examples)
        .exampleMenu.toolTip = appStrings().ui_Examples
        .surface!.setTitle(.title())
        .refreshStatus()
        .arrangeParts()
    }

    // Returns the title of the window: the example, the example and the view stage by stage, and
    // the inspected function and its stage beside another build.
    mtd title()->String
    {
        let name = exampleName(.selectedExample)
        switch #complete .view
        {
        case .Columns:
            return name

        case .Stages:
            return Format.toString("% · %", name, appStrings().ui_Microcode)

        case .Compare:
            let signature = Pipeline.inspectedSignature(.editor.text())
            if signature.count == 0 do
                return name
            let micro = .panels[0].micro()
            if micro do
                return Format.toString("% · %", signature, Pipeline.stageLabels()[Math.min(micro.stage, Pipeline.Stages.count - 1)])
            return signature
        }
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language)
    }

    // Applies the persisted standard application palette.
    mtd applyTheme()
    {
        .themeIndex = Math.min(.themeIndex, cast(u32, AppearanceTheme.System))
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

        discard AboutDlg.createApplication(unwrap .surface, about).doModal()
    }
}

impl IWnd for MainWindow
{
    // Writes the name of the source above its column and draws the hairline between the columns.
    mtd impl onPaint(evt: *PaintEvent)
    {
        if .view == .Stages do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let client  = .clientRect()
        let top     = .stripInset() + TopGap
        let bottom  = client.height - FooterHeight

        let x = painter.snapToDeviceX(Math.round(client.width * 0.5))
        painter.fillRect(Math.Rectangle{x, top, painter.hairline(.themeMetrics().separator_HairlineSize), bottom - top}, colors.line)

        if .view == .Columns
        {
            let font = .sourceTitleFont()
            painter.drawString(.sideMargin(), font.opticalLineTop(top + .themeMetrics().quiet_Height * 0.5), .sourceTitle(), font, colors.text)
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrangeParts()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .editTimer do
            .compile()
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if evt.task == &.formatTask and .formatStatus == .Working and .formatTask.isDone() do
            .finishFormat()
        else do
            evt.accepted = false
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged: .retranslate()
        case .ThemeChanged:    .arrangeParts()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        if not .computeCommandState(evt) do
            evt.accepted = false
    }

    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        evt.accepted = .runCommand(evt.id)
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

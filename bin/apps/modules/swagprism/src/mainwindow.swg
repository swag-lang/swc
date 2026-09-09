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

// Owns the shared source and two independent groups of viewer tabs.
struct MainWindow
{
    using wnd: Wnd
        late
    {
        appearanceButton: *AppearanceButton
        runButton:        *PushButton
        editor:           *RichEditCtrl
        status:           *Label
        commandBar:       *Wnd
        statusBar:        *Wnd
        sourceSplit:      *SplitterCtrl
        viewerSplit:      *SplitterCtrl
    }

    groups:     Array'*ViewerGroup
    lexer:      RichEditLexerSwag
    language:   String
    themeIndex: u32
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
        .sourceSplit           = SplitterCtrl.create(&.wnd, {}, false, "prism.split")
        .sourceSplit.dockStyle = .Center
        .sourceSplit.margin    = {Gutter, 12, Gutter, 12}
        .editor                = RichEditCtrl.create(.sourceSplit)
        .editor.setLexer(&.lexer)
        .editor.setText(StarterSnippet)

        .viewerSplit = SplitterCtrl.create(.sourceSplit, {}, false, "prism.viewers")
        for index in 2
        {
            let level: Swag.BuildCfgBackendOptimLevel = index == 0 ? .O0 : .O2
            let group = ViewerGroup.create(.viewerSplit, .editor, level)
            group.sigChanged += func|window = me|(sender)
            {
                discard sender
                window.refreshStatus()
            }
            .groups.add(group)
            let pane = .viewerSplit.addPane(group, 540)
            pane.minimumSize = ViewerGroup.MinWidth
        }

        let sourcePane = .sourceSplit.addPane(.editor, 360)
        sourcePane.minimumSize = 260
        let viewersPane = .sourceSplit.addPane(.viewerSplit, 1080)
        viewersPane.minimumSize = 2 * ViewerGroup.MinWidth + .themeMetrics().splitView_BarSize
    }

    // Both visible viewers receive the exact same source snapshot.
    mtd compile()
    {
        let source = .editor.text()
        for group in .groups do
            group.compile(source.toString())
        .refreshStatus()
    }

    mtd shutdown()
    {
        for group in .groups do
            group.shutdown()
    }

    mtd refreshStatus()
    {
        var running = 0'u64
        for group in .groups
        {
            for viewer in group.viewers where viewer.isRunning() do
                running += 1
        }

        if running > 1 do
            .status.setText(Format.toString(appStrings().ui_RunningViewers, running).toString())
        else do
            .status.setText(running ? appStrings().ui_Working : appStrings().ui_Ready)
    }

    mtd retranslate()
    {
        .runButton.setText(appStrings().ui_CompileVisible)
        .runButton.toolTip = appStrings().ui_CompileVisibleHint
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
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch evt.serializer.serialize("MainWindow.language", &me.language)
        catch evt.serializer.serialize("MainWindow.themeIndex", &me.themeIndex)
    }
}

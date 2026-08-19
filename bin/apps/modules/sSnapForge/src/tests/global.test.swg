#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testSetupGlobalMain(main: *MainWnd)
{
    main.editWnd.dockStyle = .Center

    main.topBar = Wnd.create'Wnd(main, {0, 0, 900, CommandRowHeight})
    main.createCommandRow()

    with main.recentBar = Wnd.create'Wnd(main, {0, 0, 0, 128})
    {
        .dockStyle = .Bottom
    }

    main.rightBar           = Wnd.create'Wnd(main, {0, 0, RightBarWidth, 0})
    main.rightBar.dockStyle = .Right

    main.quickStyleBar           = SplitterCtrl.create(main.rightBar, {0, 0, RightBarWidth, 600}, vertical: true)
    main.quickStyleBar.dockStyle = .Center

    main.createToolRail()
    main.setToolRailWidth()

    main.libWnd = LibraryWnd.create(main)
    main.libWnd.hide()

    // ShowLibrary calls fill(); mark the library as already loaded and seed the
    // category list so the test never scans the user's capture folder.
    g_Library.loaded = true
    g_Library.files.clear()
    discard main.libWnd.listCtrl.createLine("Seed")
    main.libWnd.filledRevision = g_Library.revision
}

// A rail-only option change must not reapply unrelated application-wide settings. Repeating the
// change used to broadcast both theme and language notifications, repaint every surface, and make
// the options dialog progressively stall.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    testSetupGlobalMain(f.main)
    f.gui.theme.setSwagLight()
    expect f.gui.app.setLanguage("fr")
    defer expect f.gui.app.setLanguage("en")

    f.main.editorOptions.theme             = .Dark
    f.main.editorOptions.language          = .English
    f.main.editorOptions.showToolBarLabels = true
    let lightBackground = f.main.themeColors().wnd_Bk
    discard f.main.applyOptionChange(#nameof(EditorOptions.showToolBarLabels))

    let metrics = f.main.themeMetrics()
    @assert(f.main.toolRail.position.width == RailLabelWidth + metrics.activeRail_Size + metrics.activeRail_Margin)
    @assert(f.main.themeColors().wnd_Bk == lightBackground)
    @assert(Gui.activeLanguage() == "fr")

    for i in 32
    {
        f.main.editorOptions.showToolBarLabels = i % 2 == 0
        discard f.main.applyOptionChange(#nameof(EditorOptions.showToolBarLabels))
        let expected = f.main.editorOptions.showToolBarLabels ? RailLabelWidth + metrics.activeRail_Size + metrics.activeRail_Margin : RailCellSize + metrics.activeRail_Size
        @assert(f.main.toolRail.position.width == expected)
        @assert(f.main.app().animator.activeCount() == 0)
    }
}

// Global window actions toggle the real sSnapForge panes and surface visibility in a
// headless surface without touching persisted app state.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let oldLibraryLoaded = g_Library.loaded
    defer
    {
        g_Library.files.clear()
        g_Library.loaded = oldLibraryLoaded
    }

    testSetupGlobalMain(f.main)
    f.gui.setReducedMotion(false)

    // In icon-only mode the active rule's own margin replaces the leading cell padding.
    // Counting both used to leave the glyph visibly adrift from its selection marker.
    let firstTool = cast(*IconButton) f.main.toolRail.children[0]
    let metrics   = f.main.themeMetrics()
    @assert(firstTool.flags.has(.IconOnly))
    @assert(firstTool.padding.x == 0)
    @assert(firstTool.padding.z == RailCellPadding)
    @assert(firstTool.position.width == RailCellSize + metrics.activeRail_Size)

    // The wait indicator of a library scan stands in the command bar, not over the captures. It
    // used to be a child of the scroll window at 8,8 — which is exactly where the view's own
    // padding puts the first thumbnail, so it landed on a cell that already carries an hour glass
    // while its picture loads. The bar is where the state of this window is said, and a control
    // standing there covers nothing; hidden, it leaves no gap, because the bar stacks only what
    // is visible.
    let bar     = f.main.libWnd.commandBar
    let spinner = cast(*Wnd) f.main.libWnd.view.imgSpin!
    @assert(spinner.parent == cast(*Wnd) bar)
    @assert(!spinner.isLocallyVisible())

    let packed = bar.measure({}).preferred.x
    spinner.show()
    @assert(bar.measure({}).preferred.x > packed)
    spinner.hide()
    @assert(bar.measure({}).preferred.x == packed)

    var evt = Gui.Testing.commandState(ActionGlobal.ShowLibrary)
    @assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.ShowLibrary, &evt))
    @assert(!evt.name.isEmpty())
    @assert(!evt.checked)
    @assert(@countof(f.main.libraryBtn.text()) != 0)
    @assert(f.main.libraryBtn.icon.isValid())
    @assert(f.main.libraryBtn.form == .Normal)
    @assert(f.main.libraryBtn.position.width == f.main.captureBtn.position.width)
    @assert(f.main.icon(.RatingStar, RatingGlyphSize).isValid())
    @assert(f.main.commandReadouts.isLocallyVisible())

    f.gui.focus(f.main.libraryBtn)
    f.gui.keyPress(Input.Key.Space)
    @assert(f.main.libraryMode)

    // Filled, Library wears the theme's alternate tone: Capture is what the surface is for and
    // keeps the signature, and the page the reader can leave to is the other thing a theme owns
    // a second color for.
    @assert(f.main.libraryBtn.form == .Alternate)
    @assert(!f.main.editWnd.isLocallyVisible())
    @assert(f.main.libWnd.isLocallyVisible())
    @assert(!f.main.commandReadouts.isLocallyVisible())
    @assert(!f.main.app().animator.isActive(f.main.libWnd, AnimationChannel.from("Gui.Page.Offset")))
    @assert(f.main.libWnd.presentationOpacity == 1 and f.main.libWnd.presentationOffset == Math.Point{})

    evt = Gui.Testing.commandState(ActionGlobal.ShowLibrary)
    @assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.ShowLibrary, &evt))
    @assert(evt.checked)

    f.gui.keyPress(Input.Key.Space)
    @assert(!f.main.libraryMode)
    @assert(f.main.libraryBtn.form == .Normal)
    @assert(f.main.editWnd.isLocallyVisible())
    @assert(!f.main.libWnd.isLocallyVisible())
    @assert(f.main.commandReadouts.isLocallyVisible())
    @assert(!f.main.app().animator.isActive(f.main.editWnd, AnimationChannel.from("Gui.Page.Offset")))
    @assert(f.main.editWnd.presentationOpacity == 1 and f.main.editWnd.presentationOffset == Math.Point{})

    let surface = f.main.surface!
    surface.show()
    @assert(!surface.isHidden)

    @assert(Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.Minimize))
    @assert(surface.isHidden)

    @assert(Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.ShowEditor))
    @assert(!surface.isHidden)

    evt = Gui.Testing.commandState(ActionGlobal.Exit)
    @assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.Exit, &evt))
    @assert(!evt.name.isEmpty())
}

// The fixed dark matte was once the persisted default. It now migrates to the
// theme-derived transparent value without changing a color the user actually chose.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    f.main.editorOptions.editBackColor = 0xFF2E2E2E'u32
    f.main.migrateStoredOptions()
    @assert(f.main.editorOptions.editBackColor == 0)

    f.main.editorOptions.editBackColor = 0xFF123456'u32
    f.main.migrateStoredOptions()
    @assert(f.main.editorOptions.editBackColor == 0xFF123456'u32)
}

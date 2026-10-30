#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testSetupGlobalMain(main: *MainWnd)
{
    with main.editArea = Wnd.create'Wnd(main)
    {
        .dockStyle = .Center
    }

    main.editWnd.setParent(main.editArea)
    main.editWnd.dockStyle = .Center
    main.createRecentBar()
    main.createDock()
    main.createInspector()
    main.createMiniBar()
    main.createHintLine()

    main.libWnd = LibraryWnd.create(main)
    main.libWnd.hide()

    // ShowLibrary calls fill(); mark the library as already loaded and seed the
    // category list so the test never scans the user's capture folder.
    g_Library.loaded = true
    g_Library.files.clear()
    main.libWnd.filledOnce     = true
    main.libWnd.filledRevision = g_Library.revision
}

// The persisted editor option reaches every palette offered by the shared appearance action.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.appearanceButton = AppearanceButton.create(&f.gui.surface, "capture.appearance")

    f.main.editorOptions.theme = .Dark
    f.main.setTheme()
    Swag.assert(f.main.appearanceButton.appearanceTheme == .Dark and f.gui.theme.colors.ground == ThemeColors.encrePalette().ground)
    f.main.editorOptions.theme = .Light
    f.main.setTheme()
    Swag.assert(f.main.appearanceButton.appearanceTheme == .Light and f.gui.theme.colors.ground == ThemeColors.papierPalette().ground)
    f.main.editorOptions.theme = .System
    f.main.setTheme()
    Swag.assert(f.main.appearanceButton.appearanceTheme == .System and f.gui.theme.colors.ground == ThemeColors.encrePalette().ground)
}

// Global window actions toggle the real Swag Capture panes and surface visibility in a
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

    // The tools stand in the dock, one cell per tool, the glyph at the size of the dock.
    let metrics   = f.main.themeMetrics()
    let firstTool = f.main.dock.tools[0]
    Swag.assert(f.main.dock.tools.count == 8)
    Swag.assert(firstTool.id == ActionToolMode.Selection)
    Swag.assert(firstTool.position.width == metrics.toolDock_CellSize)
    Swag.assert(firstTool.icon.sizeX == metrics.toolDock_Glyph)

    // A tool of a group keeps its command: chosen from the lens or its key, it comes into the
    // cell of its group, which then carries its command; the first tool of the group comes back
    // the same way.
    let lineCell = f.main.dock.tools[2]
    Swag.assert(lineCell.id == ActionToolMode.Arrow)
    f.main.editMode = .Line
    f.main.updateState()
    Swag.assert(lineCell.id == ActionToolMode.Line and lineCell.isChecked)
    f.main.dock.chooseInGroup(lineCell, ActionToolMode.Arrow)
    f.gui.pump()
    Swag.assert(lineCell.id == ActionToolMode.Arrow and f.main.editMode == .Arrow)

    // The wait indicator of a library scan stands in the command bar, not over the captures. It
    // used to be a child of the scroll window at 8,8 — which is exactly where the view's own
    // padding puts the first thumbnail, so it landed on a cell that already carries an hour glass
    // while its picture loads. The bar is where the state of this window is said, and a control
    // standing there covers nothing; hidden, it leaves no gap, because the bar stacks only what
    // is visible.
    let bar     = f.main.libWnd.commandBar
    let spinner = cast(*Wnd, f.main.libWnd.view.imgSpin)
    Swag.assert(spinner.parent == cast(*Wnd, bar))
    Swag.assert(not spinner.isLocallyVisible())

    let packed = bar.measure({}).preferred.x
    spinner.show()
    Swag.assert(bar.measure({}).preferred.x > packed)
    spinner.hide()
    Swag.assert(bar.measure({}).preferred.x == packed)

    var evt = Gui.Testing.commandState(ActionGlobal.ShowLibrary)
    Swag.assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.ShowLibrary, &evt))
    Swag.assert(not evt.name.isEmpty())
    Swag.assert(not evt.checked)
    Swag.assert(f.main.icon(.RatingStar, RatingGlyphSize).isValid())

    // The library is a lens entry: the work area, with the dock and the inspector it carries,
    // leaves while the library is on screen.
    Swag.assert(Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.ShowLibrary))
    Swag.assert(f.main.libraryMode)
    Swag.assert(not f.main.editArea.isLocallyVisible())
    Swag.assert(f.main.libWnd.isLocallyVisible())
    Swag.assert(not f.main.miniBar.isLocallyVisible())

    // The page arrives from a little below, and is reachable at once.
    let pageTravel = f.main.themeMetrics().motion_PageOffset
    Swag.assert(f.main.app().animator.isActive(f.main.libWnd, AnimationChannel.from("Capture.Page.Offset")))
    Swag.assert(not f.main.app().animator.isActive(f.main.libWnd, AnimationChannel.from("Gui.Float.Opacity")))
    Swag.assert(f.main.libWnd.presentationOpacity == 1)
    Swag.assert(f.main.libWnd.presentationOffset.y > 0 and f.main.libWnd.presentationOffset.y <= pageTravel)
    f.main.app().animator.finishAll()
    Swag.assert(f.main.libWnd.presentationOpacity == 1 and f.main.libWnd.presentationOffset == Math.Point{})

    evt = Gui.Testing.commandState(ActionGlobal.ShowLibrary)
    Swag.assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.ShowLibrary, &evt))
    Swag.assert(evt.checked)

    // The tool letters belong to the editor, which the library hides.
    var tool = Gui.Testing.commandState(ActionToolMode.Shape)
    Swag.assert(Gui.Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Shape, &tool))
    Swag.assert(tool.disabled)

    Swag.assert(Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.ShowLibrary))
    Swag.assert(not f.main.libraryMode)
    Swag.assert(f.main.editArea.isLocallyVisible())
    tool = Gui.Testing.commandState(ActionToolMode.Shape)
    Swag.assert(Gui.Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Shape, &tool))
    Swag.assert(not tool.disabled)
    Swag.assert(not f.main.libWnd.isLocallyVisible())
    f.main.app().animator.finishAll()
    Swag.assert(f.main.editArea.presentationOpacity == 1 and f.main.editArea.presentationOffset == Math.Point{})

    let surface = unwrap f.main.surface
    surface.show()
    Swag.assert(not surface.isHidden)

    var actionExecuted = Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.Minimize)
    Swag.assert(actionExecuted)
    Swag.assert(surface.isHidden)

    actionExecuted = Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.ShowEditor)
    Swag.assert(actionExecuted)
    Swag.assert(not surface.isHidden)

    evt = Gui.Testing.commandState(ActionGlobal.Exit)
    Swag.assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.Exit, &evt))
    Swag.assert(not evt.name.isEmpty())
}

// The fixed dark matte was once the persisted default. It now migrates to the theme-derived
// transparent value without changing a color the user actually chose, and an invalid stored
// appearance value returns to the standard Swag palette before it reaches the complete switch.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    f.main.editorOptions.editBackColor = 0xFF2E2E2E'u32
    f.main.migrateStoredOptions()
    Swag.assert(f.main.editorOptions.editBackColor == 0)

    f.main.editorOptions.editBackColor = 0xFF123456'u32
    f.main.migrateStoredOptions()
    Swag.assert(f.main.editorOptions.editBackColor == 0xFF123456'u32)

    f.main.editorOptions.theme = cast(AppearanceTheme, 99)
    f.main.migrateStoredOptions()
    Swag.assert(f.main.editorOptions.theme == .Dark)
}

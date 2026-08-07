#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testSetupGlobalMain(main: *MainWnd)
{
    main.editWnd.dockStyle = .Center

    with main.recentBar = Wnd.create'Wnd(main, {0, 0, 0, 128})
    {
        .dockStyle = .Bottom
    }

    main.rightBar           = Wnd.create'Wnd(main, {0, 0, RightBarWidth, 0})
    main.rightBar.dockStyle = .Right

    main.quickStyleBar           = SplitterCtrl.create(main.rightBar, {0, 0, RightBarWidth, 600}, vertical: true)
    main.quickStyleBar.dockStyle = .Center

    main.toolRail           = StackLayoutCtrl.create(main, .Top, {0, 0, RailCellSize, 0})
    main.toolRail.dockStyle = .Left

    main.libWnd = LibraryWnd.create(main)
    main.libWnd.hide()

    // ShowLibrary calls fill(); mark the library as already loaded and seed the
    // category list so the test never scans the user's capture folder.
    g_Library.loaded = true
    g_Library.files.clear()
    discard main.libWnd.listCtrl.createLine("Seed")
}

// Global window actions toggle the real sCapture panes and surface visibility in a
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

    @assert(Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.ShowLibrary))
    @assert(f.main.libraryMode)
    @assert(!f.main.editWnd.isLocallyVisible())
    @assert(f.main.libWnd.isLocallyVisible())

    evt = Gui.Testing.commandState(ActionGlobal.ShowLibrary)
    @assert(Gui.Testing.actionUpdate'ActionGlobal(f.main, ActionGlobal.ShowLibrary, &evt))
    @assert(evt.checked)

    @assert(Gui.Testing.actionExecute'ActionGlobal(f.main, ActionGlobal.ShowLibrary))
    @assert(!f.main.libraryMode)
    @assert(f.main.editWnd.isLocallyVisible())
    @assert(!f.main.libWnd.isLocallyVisible())

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

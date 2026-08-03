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

    main.quickStyleBar           = SplitterCtrl.create(main, {0, 0, 300, 600}, vertical: true)
    main.quickStyleBar.dockStyle = .Right

    main.editZoomBar           = StackLayoutCtrl.create(main, .HorizontalCenter, {0, 0, 300, 32})
    main.editZoomBar.dockStyle = .Top

    main.editToolBar           = Wnd.create'Wnd(main, {0, 0, 64, 64})
    main.editToolBar.dockStyle = .Top

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

    let surface = notnull f.main.surface
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

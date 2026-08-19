#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

struct ScenarioFixture
{
    gui:        Gui.Testing.HeadlessHost
    main:       *MainWnd = undefined
    rootFolder: String
}

impl ScenarioFixture
{
    mtd setup()
    {
        testUseScratchLibrary()
        .gui.setup(1024, 640)
        .gui.bindApplication(&g_App)
        registerAppStrings(&g_App.resources)
        registerAppStrings(&.gui.app.resources)

        .rootFolder = Gui.Testing.tempFilePath("snapforge-scenario-", "")
        expect Directory.create(.rootFolder)
        expect g_Library.setFolder(.rootFolder)

        .main = MainWnd.create(&.gui.surfaceWnd)
        .main.setPosition({0, 0, 1024, 640})
        .main.applyLayout()

        // Production registers the history observer from the initial-load timer. Run that
        // boundary synchronously so every scenario starts after the application is ready.
        .main.recentWnd.loadRecent()
    }

    mtd shutdown()
    {
        .main.libWnd.requestClose()
        @drop(&g_Library, 1)
        @init(&g_Library, 1)
        .gui.shutdown()
        discard catch Directory.delete(.rootFolder, recurse: true)
        g_Main = null
    }

    mtd settleLibrary()
    {
        if .main.libWnd.view.thread.isValid() do
            .main.libWnd.view.thread.wait()

        .gui.pump()
        .main.applyLayout()
        .gui.settleAnimations(.main)
        var rendered = .gui.render(.main)
        @assert(rendered.isValid())
    }

    mtd toggleLibrary()
    {
        .gui.focus(.main.libraryBtn)
        .gui.keyPress(Input.Key.Space)
        .gui.pump()
        if .main.libraryMode do
            .settleLibrary()
    }
}

func scenarioNewCapture(main: *MainWnd, application: string)->String
{
    main.newCapture(Gui.Testing.indexedImage(96, 64), sourceKind: .Screen)
    let capture = main.editWnd.getCapture()!
    capture.sourceApplication = application
    capture.sourceExecutable  = "scenario.exe"
    capture.sourceWindowTitle = "Scenario window"
    capture.changed           = true
    capture.computePreview()
    main.saveCapture(capture)
    return String.from(capture.file)
}

func scenarioDeleteCaptureFiles(path: String)
{
    discard catch File.delete(path)
    discard catch File.delete(Path.combine(Library.getTrashFolder(), Path.fileName(path)))
}

// A captured image crosses the complete editor/history/library boundary. Loading and painting
// the populated library is essential: automatic filters are refreshed from the loaded capture
// during paint, which a component-only library fixture never exercises.
#test
{
    var f: ScenarioFixture
    f.setup()
    defer f.shutdown()

    let path = scenarioNewCapture(f.main, "Scenario Editor")
    defer scenarioDeleteCaptureFiles(path)

    @assert(File.exists(path))
    @assert(f.main.editWnd.getCapture()!.file == path)
    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(g_Library.files.count == 1)

    f.toggleLibrary()

    @assert(f.main.libraryMode)
    @assert(f.main.libWnd.view.allItems.count == 1)
    @assert(f.main.libWnd.view.items.count == 1)
    @assert(f.main.libWnd.view.items[0]!.loaded)
    @assert(f.main.libWnd.sidebarApplications.count == 1)
    @assert(f.main.libWnd.sidebarApplications[0].name == "Scenario Editor")

    f.toggleLibrary()

    @assert(!f.main.libraryMode)
    @assert(f.main.editWnd.getCapture()!.file == path)
}

// Editing a capture schedules the real history timer, which saves it. Opening the same item
// from the populated library must load that persisted document back into the editor.
#test
{
    var f: ScenarioFixture
    f.setup()
    defer f.shutdown()

    let path = scenarioNewCapture(f.main, "Scenario Save")
    defer scenarioDeleteCaptureFiles(path)

    let capture = f.main.editWnd.getCapture()!
    capture.title = "Persisted scenario"
    discard testAddShape(capture, 8, 10, 30, 20)
    capture.changed = true
    f.main.captureHasChanged()
    @assert(f.main.recentWnd.timer != null)
    f.gui.fireTimer(f.main.recentWnd.timer)

    let saved = expect Capture.load(path)!
    @assert(saved.title == "Persisted scenario")
    @assert(saved.forms.count == 1)
    Memory.delete(saved)

    f.toggleLibrary()
    let item = f.main.libWnd.view.items[0]!
    f.main.libWnd.view.openItem(item)
    f.gui.pump()

    @assert(!f.main.libraryMode)
    @assert(f.main.editWnd.getCapture()!.file == path)
    @assert(f.main.editWnd.getCapture()!.title == "Persisted scenario")
    @assert(f.main.editWnd.getCapture()!.forms.count == 1)
}

// The history popup deletes through every production observer after the library has been
// populated. The source file moves to the recycle bin and both views lose their owned item.
#test
{
    var f: ScenarioFixture
    f.setup()
    defer f.shutdown()

    let path = scenarioNewCapture(f.main, "Scenario Delete")
    defer scenarioDeleteCaptureFiles(path)
    let trashPath = Path.combine(Library.getTrashFolder(), Path.fileName(path))

    f.toggleLibrary()
    f.toggleLibrary()
    @assert(f.main.recentWnd.recentView.selected == 0)

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)
    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DeleteCapture))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(!File.exists(path))
    @assert(File.exists(trashPath))
    @assert(g_Library.files.count == 0)
    @assert(f.main.recentWnd.recentView.items.count == 0)
    @assert(f.main.libWnd.view.items.count == 0)
}

// A library deletion remains recoverable through the recycle-bin page. Restoring it repopulates
// the root library, and opening the restored capture returns to the editor.
#test
{
    var f: ScenarioFixture
    f.setup()
    defer f.shutdown()

    let path = scenarioNewCapture(f.main, "Scenario Restore")
    defer scenarioDeleteCaptureFiles(path)
    let trashPath = Path.combine(Library.getTrashFolder(), Path.fileName(path))

    f.toggleLibrary()
    f.main.libWnd.view.focusItem = 0
    f.main.libWnd.view.selModel.select(0)
    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)
    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DeleteCapture))
    f.gui.pump()

    @assert(!File.exists(path))
    @assert(File.exists(trashPath))

    f.main.libWnd.setTrashMode(true)
    f.settleLibrary()
    @assert(f.main.libWnd.view.items.count == 1)
    f.main.libWnd.view.focusItem = 0
    f.main.libWnd.view.selModel.select(0)
    @assert(Gui.Testing.actionExecute'ActionLibTrash(f.main.libWnd, ActionLibTrash.Restore))

    @assert(File.exists(path))
    @assert(!File.exists(trashPath))
    @assert(g_Library.files.count == 1)

    f.main.libWnd.setTrashMode(false)
    f.settleLibrary()
    @assert(f.main.libWnd.view.items.count == 1)
    f.main.libWnd.view.openItem(f.main.libWnd.view.items[0]!)
    f.gui.pump()

    @assert(!f.main.libraryMode)
    @assert(f.main.editWnd.getCapture()!.file == path)
}

// Removing the last item in history selects its surviving neighbour. This protects the editor,
// recent selection and deleted file from becoming three different notions of the current item.
#test
{
    var f: ScenarioFixture
    f.setup()
    defer f.shutdown()

    let firstPath = scenarioNewCapture(f.main, "Scenario First")
    defer scenarioDeleteCaptureFiles(firstPath)
    let secondPath = scenarioNewCapture(f.main, "Scenario Second")
    defer scenarioDeleteCaptureFiles(secondPath)

    f.toggleLibrary()
    f.toggleLibrary()
    @assert(f.main.recentWnd.recentView.items.count == 2)
    f.main.recentWnd.recentView.select(1)
    @assert(f.main.editWnd.getCapture()!.file == firstPath)

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)
    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DeleteCapture))
    f.gui.pump()

    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(f.main.recentWnd.recentView.selected == 0)
    @assert(f.main.editWnd.getCapture()!.file == secondPath)
    @assert(!File.exists(firstPath))
    @assert(File.exists(secondPath))
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

func assertClassificationFolder(result: const *ViewerClassifiedFile, names: const [..] String)
{
    Swag.assert(result.folderFiles.count == names.count)
    for name, index in names do
        Swag.assert(result.folderFiles[index] == name[])
}

// Reusing the asynchronous classifier replaces its previous folder snapshot. It must never append
// a second scan when the reader selects another file from the same folder.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_classification_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    var host: Testing.HeadlessHost
    host.setup(64, 64)

    var names: Array'String
    for i in 3'u32
    {
        let fileName = Path.combine(folder, Format.toString("file%.txt", i))
        discard expect File.writeAllText(fileName, "a readable line\n")
        names.add(fileName)
    }

    var index = createViewerPluginRegistry()
    var load: ViewerChoiceLoad

    load.start(&index, names[0])
    load.task.wait()
    var first = load.finish()
    assertClassificationFolder(&first, names.toSlice())

    load.start(&index, names[2])
    load.task.wait()
    var second = load.finish()
    assertClassificationFolder(&second, names.toSlice())

    load.start(&index, names[1], includeNeighbors: false)
    load.task.wait()
    let thumbnail = load.finish()
    Swag.assert(thumbnail.exists and not thumbnail.choices.isEmpty())
    Swag.assert(thumbnail.folderFiles.isEmpty())
}

struct ClassificationRetirementGate
{
    entered:  Sync.Event
    release:  Sync.Event
    finished: u32
}

// Holds a statistics count behind `gate` until the test releases it.
func holdClassificationStatistics(gate: *ClassificationRetirementGate)->TextStatistics
{
    gate.entered.signal()
    gate.release.wait()
    Atomic.exchange(&gate.finished, 1)
    return {}
}

// A readable text document can still own native statistics work. Classification may finish
// before that work retires, so the window keeps its old presentation until retirement completes.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope_retirement_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let first = Path.combine(folder, "first.txt")
    let next  = Path.combine(folder, "next.txt")
    discard expect File.writeAllText(first, "The first document.\n")
    discard expect File.writeAllText(next, "The next document.\n")

    // The gate outlives the GUI owner, including cleanup after an assertion failure.
    var gate: ClassificationRetirementGate
    gate.entered.init(manual: true)
    gate.release.init(manual: true)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    with let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    {
        .resize(960, 680)
        .openFile(first, remember: false)
    }

    completeQueuedViewerFile(&host, window)
    Swag.assert(window.choices[window.activeChoiceIndex].key == PlainText.ViewerKey)
    let previousView = unwrap window.currentView
    let previous     = assume cast(*PlainText.Panel, previousView)
    Swag.assert(not previous.isStreaming())

    // Replace completed statistics with a count whose lifetime is controlled by this test. Like
    // every viewer task, it tells its view when it ends.
    completeTextStatistics(&host, previous)
    let held = &gate
    previous.statisticsTask.submit(func|held|()->TextStatistics => holdClassificationStatistics(held), previous.taskNotifier(&previous.statisticsTask))
    defer gate.release.signal()
    gate.entered.wait()
    Swag.assert(previous.statisticsTask.isPending())

    window.openFile(next, remember: false)
    Swag.assert(window.startupTimer != null)
    host.fireTimer(window.startupTimer)
    Swag.assert(window.choiceLoad.started)
    window.choiceLoad.task.wait()
    Swag.assert(window.choiceLoad.isDone())

    // Delivering the end of the classification must return while the statistics count remains
    // behind the gate. It is the production retirement path, not the test helper, that asks the
    // count to stop.
    host.pump()
    Swag.assert(previous.statisticsTask.isCancelled())
    Swag.assert(previous.statisticsTask.isPending())
    Swag.assert(window.currentView == previousView and window.currentFile == first)
    Swag.assert(window.pendingFile == next and window.choiceLoad.isDone())

    // Nothing asks again before the count ends: the window keeps the old document, without
    // consuming or publishing the completed classification result.
    Swag.assert(window.awaitingRetirement and window.startupTimer == null)
    host.pump()
    Swag.assert(Atomic.get(&gate.finished) == 0)
    Swag.assert(window.currentView == previousView and window.pendingFile == next)
    Swag.assert(window.choiceLoad.started and window.choiceLoad.isDone())

    gate.release.signal()
    completeViewerWindowClassification(&host, window)
    Swag.assert(Atomic.get(&gate.finished) == 1)
    Swag.assert(window.pendingFile.isEmpty() and not window.choiceLoad.started)
    Swag.assert(window.currentFile == next and window.currentView != previousView)
}

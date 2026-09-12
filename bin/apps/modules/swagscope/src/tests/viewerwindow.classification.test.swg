#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

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
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_classification_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var host: Testing.HeadlessHost
    host.setup(64, 64)
    defer host.shutdown()

    var names: Array'String
    for i in 3'u32
    {
        let fileName = Path.combine(folder.toString(), Format.toString("file%.txt", i).toString())
        discard expect File.writeAllBytes(fileName.toString(), cast(const [..] u8) "a readable line\n")
        names.add(fileName)
    }

    var index = createViewerPluginRegistry()
    var load:   ViewerChoiceLoad
    var recent: Array'String

    load.start(&index, names[0].toString(), recent.toSlice())
    load.task.wait()
    var first = load.finish()
    assertClassificationFolder(&first, names.toSlice())

    load.start(&index, names[2].toString(), recent.toSlice())
    load.task.wait()
    var second = load.finish()
    assertClassificationFolder(&second, names.toSlice())
}

struct ClassificationRetirementGate
{
    entered:  Sync.Event
    release:  Sync.Event
    finished: u32
}

func holdClassificationStatistics(thread: Threading.Thread)
{
    let gate = cast(*ClassificationRetirementGate) thread.userParam!
    gate.entered.signal()
    gate.release.wait()
    Atomic.exchange(&gate.finished, 1)
}

// A readable text document can still own native statistics work. Classification may finish
// before that work retires, so the window keeps its old presentation until retirement completes.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("scope_retirement_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)
    let first = Path.combine(folder.toString(), "first.txt")
    let next  = Path.combine(folder.toString(), "next.txt")
    discard expect File.writeAllBytes(first.toString(), cast(const [..] u8) "The first document.\n")
    discard expect File.writeAllBytes(next.toString(), cast(const [..] u8) "The next document.\n")

    // The gate outlives the GUI owner, including cleanup after an assertion failure.
    var gate: ClassificationRetirementGate
    gate.entered.init(manual: true)
    gate.release.init(manual: true)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 680)
    window.openFile(first.toString(), remember: false)
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.choices[window.activeChoiceIndex].key == TextViewerKey)
    let previousView = window.currentView!
    let previous     = cast(*TextView) previousView
    Swag.assert(previous.loadTimer == null)

    // Replace completed statistics with a worker whose lifetime is controlled by this test.
    // Remove its publication timer first: the completed operation's statisticsState must not
    // cause a GUI timer to join the replacement while its release event is still unsignaled.
    if previous.statisticsThread.isValid() do
        previous.statisticsThread.wait()
    if previous.statisticsTimer
    {
        previous.removeTimer(previous.statisticsTimer)
        previous.statisticsTimer = null
    }

    expect previous.statisticsThread.init(&holdClassificationStatistics, &gate)
    defer gate.release.signal()
    expect previous.statisticsThread.start()
    gate.entered.wait()
    Swag.assert(not previous.statisticsThread.isDone())

    window.openFile(next.toString(), remember: false)
    Swag.assert(window.startupTimer != null)
    host.fireTimer(window.startupTimer)
    Swag.assert(window.choiceLoad.started)
    window.choiceLoad.task.wait()
    Swag.assert(window.choiceLoad.isDone())

    // This callback must return while the statistics worker remains behind the gate. It is
    // the production retirement path, not the test helper, that requests the worker to stop.
    host.fireTimer(window.startupTimer)
    Swag.assert(previous.statisticsThread.requestEnd)
    Swag.assert(not previous.statisticsThread.isDone())
    Swag.assert(window.currentView == previousView and window.currentFile == first)
    Swag.assert(window.pendingFile == next and window.choiceLoad.isDone())
    Swag.assert(window.startupTimer != null)

    // Draining scheduler tasks cannot retire a native thread. Another GUI poll still keeps
    // the old document, without consuming or publishing the completed classification result.
    Swag.drainWork()
    host.fireTimer(window.startupTimer)
    Swag.assert(Atomic.get(&gate.finished) == 0)
    Swag.assert(window.currentView == previousView and window.pendingFile == next)
    Swag.assert(window.choiceLoad.started and window.choiceLoad.isDone())

    gate.release.signal()
    completeViewerWindowClassification(&host, window)
    Swag.assert(Atomic.get(&gate.finished) == 1)
    Swag.assert(window.pendingFile.isEmpty() and not window.choiceLoad.started)
    Swag.assert(window.currentFile == next and window.currentView != previousView)
}

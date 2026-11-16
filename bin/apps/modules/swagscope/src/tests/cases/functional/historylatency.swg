#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// A blocked history scan leaves both Clear and document loading usable. Clearing all while the
// scan is pending also prevents its stale result from changing a subsequently opened history.
#test
{
    var release: Sync.Event
    release.init(manual: true)
    var held: Swag.Task
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    window.historyCleanup.executor.start(.Background)
    held.submit(func|gate = &release|() { gate.wait() }, executor: &window.historyCleanup.executor)
    defer release.signal()

    host.clickPopupMenuItemWhenShown("scope.home.clear.missing")
    window.home.showClearMenu()
    Swag.require(host.autoHandled and window.historyCleanup.started and not window.historyCleanup.isDone())
    Swag.require(window.recent.count == 6)

    host.clickPopupMenuItemWhenShown("scope.home.clear.all")
    host.thenClickModalButton(Dialog.BtnYes)
    window.home.showClearMenu()
    Swag.require(host.autoHandled and window.recent.isEmpty())

    let file = scopeTestDataPath("comprehensive.txt")
    window.queueFile(file)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView != null and window.recent.count == 1)
    release.signal()
    window.historyCleanup.task.wait()
    held.wait()
    host.pump()
    Swag.require(window.recent.count == 1 and window.recent[0] == window.currentFile)
}

// Resolving saved mount aliases may block indefinitely. The GUI and settings writer cannot
// wait for it, and an unverified path cannot be written back as public history in the meantime.
#test
{
    let root = Testing.tempFilePath("scope-saved-private-", "")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(root, "confidential.txt")
    discard expect File.writeAllText(file, "private document")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, true)
    var release: Sync.Event
    release.init(manual: true)
    var held: Swag.Task
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.privacy.scan.executor.start(.Background)
    held.submit(func|gate = &release|() { gate.wait() }, executor: &window.privacy.scan.executor)
    defer release.signal()

    window.recent.add(file)
    window.recentOpened.add(HomeNow)
    window.folderHistory.add({root, file})
    window.exploredFolders.add(root)
    window.fileDlgState.currentFolder = root
    window.fileDlgState.recentFolders.add(root)
    window.privacy.sanitize()
    Swag.require(window.privacy.scan.started and not window.privacy.scan.isDone())
    let pending = saveViewerState(window)
    Swag.require(not Utf8.contains(pending, "scope-saved-private-"))
    Swag.require(window.recent.count == 1 and window.fileDlgState.currentFolder == root)

    host.clickPopupMenuItemWhenShown("scope.home.clear.all")
    host.thenClickModalButton(Dialog.BtnNo)
    window.home.showClearMenu()
    Swag.require(host.autoHandled and not window.privacy.scan.isDone())

    release.signal()
    window.privacy.scan.task.wait()
    held.wait()
    host.pump()
    Swag.require(window.recent.isEmpty() and window.folderHistory.isEmpty() and window.exploredFolders.isEmpty())
    Swag.require(window.fileDlgState.currentFolder.isEmpty() and window.fileDlgState.recentFolders.isEmpty())
    Swag.require(not Utf8.contains(saveViewerState(window), "scope-saved-private-"))
}

// A file that is already confidential can be read, but never enters recent or folder history.
#test
{
    let root = Testing.tempFilePath("scope-private-first-open-", "")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(root, "confidential.txt")
    discard expect File.writeAllText(file, "private document")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, true)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.queueFile(file)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView != null and window.currentFile == file)
    Swag.require(window.recent.isEmpty() and window.folderHistory.isEmpty() and window.resumePoints.isEmpty())
    Swag.require(not Utf8.contains(saveViewerState(window), "scope-private-first-open-"))
}

// Ordinary saved history becomes persistable again once its background policy check completes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let file   = scopeTestDataPath("comprehensive.txt")
    window.recent.add(file)
    window.recentOpened.add(HomeNow)
    window.privacy.sanitize()
    window.privacy.scan.task.wait()
    host.pump()
    Swag.require(window.recent.count == 1 and window.recent[0] == file)
    Swag.require(Utf8.contains(saveViewerState(window), "comprehensive.txt"))
}

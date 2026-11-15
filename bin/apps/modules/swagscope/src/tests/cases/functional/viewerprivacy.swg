#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Unmounting while privacy is off keeps the explicitly public history.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-public-close-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(root, "public.txt")
    discard expect File.writeAllText(file, "public document")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.rememberRecent(file)
    window.rememberExplored(root)
    publisher.close()
    host.fireTimer(window.privacyTimer)
    let saved = saveViewerState(window)
    Swag.require(window.recent.count == 1 and window.exploredFolders.count == 1)
    Swag.require(Utf8.contains(saved, "public.txt"))
}

// A private activation rewrites the actual settings file during full screen, while preserving
// both the current presentation and the normal placement saved for the next launch.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-fullscreen-policy-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(root, "fullscreen-document.txt")
    discard expect File.writeAllText(file, "document")
    let settings = Testing.tempFilePath("scope-private-state-", ".scc")
    defer catch File.delete(settings)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    var host: Testing.HeadlessHost
    host.setup(880, 560, Env.monitorForPoint(Math.Point{0, 0}).scaleFactor)
    host.surface.updateFlags(.StandardWindow)
    host.app.setStatePath(settings)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.rememberRecent(file)
    expect window.saveState()
    let normal = host.surface.position
    window.setFullScreen(true)
    let presentation = host.surface.position
    let flags        = host.surface.flags
    publisher.setPrivateMode(true)
    host.fireTimer(window.privacyTimer)
    Swag.require(window.fullScreen and host.surface.position == presentation and host.surface.flags == flags)
    Swag.require(window.recent.isEmpty() and not window.privacy.dirty)
    var reader: Scc.Reader
    expect reader.initialize(settings)
    let bytes = expect reader.readChunk(reader.chunks()[0].id)
    Swag.require(not Utf8.contains(bytes.toSlice(), "fullscreen-document.txt"))
    reader.close()
    window.setFullScreen(false)
    expect host.app.loadState()
    Swag.require(window.recent.isEmpty())
    Swag.require(host.surface.position == normal, Format.toString("saved normal placement %, restored %", normal, host.surface.position))
}

// A live switch removes all traces of an open file without closing its viewer. Returning to
// public mode records future opens, never the file that was already being read privately.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-private-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(root, "private-document.txt")
    discard expect File.writeAllText(file, "a document that stays open\n")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    defer publisher.close()
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.queueFile(file)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.recent.contains(window.currentFile))
    window.rememberExplored(root)
    window.fileDlgState.currentFolder = root
    window.fileDlgState.recentFolders.add(root)
    window.musicChoices.add({path: window.currentFile, id: "test-release"})
    window.privacy.sanitize()
    let before = saveViewerState(window)
    Swag.require(Utf8.contains(before, "private-document.txt"))

    publisher.setPrivateMode(true)
    host.fireTimer(window.privacyTimer)
    Swag.require(window.currentFile == file and window.currentView != null)
    Swag.require(window.recent.isEmpty() and window.folderHistory.isEmpty() and window.exploredFolders.isEmpty())
    Swag.require(window.resumePoints.isEmpty() and window.musicChoices.isEmpty())
    let match = ExplorerEntry{path: file}
    Swag.require(window.privacy.selectedMusicId(&match) == "test-release")
    Swag.require(window.fileDlgState.currentFolder.isEmpty() and window.fileDlgState.recentFolders.isEmpty())
    let privateState = saveViewerState(window)
    Swag.require(not Utf8.contains(privateState, "private-document.txt"))

    publisher.setPrivateMode(false)
    host.fireTimer(window.privacyTimer)
    window.captureResume()
    Swag.require(window.recent.isEmpty() and window.resumePoints.isEmpty())
    window.rememberRecent(file)
    Swag.require(window.recent.count == 1)
    publisher.setPrivateMode(true)
    publisher.setPrivateMode(false)

    // Saving also reconciles changes, without depending on the next timer tick.
    let afterCycle = saveViewerState(window)
    Swag.require(window.recent.isEmpty() and not Utf8.contains(afterCycle, "private-document.txt"))
}

// Folder exploration, extracted archive members and a late save after unmount retain the
// original policy. Unrelated public history survives the transition.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-private-folder-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let member = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-member-%.txt", Guid64.random()))
    discard expect File.writeAllText(member, "extracted member")
    defer catch File.delete(member)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(root)
    let publicFile = scopeTestDataPath("comprehensive.txt")
    window.rememberRecent(publicFile)
    window.privacy.inherit(member, root)
    window.rememberRecent(member)
    let inherited = window.privacy.policy(member)
    Swag.require(window.recent.count == 2 and window.exploredFolders.count == 1)
    publisher.setPrivateMode(true)
    publisher.close()
    host.fireTimer(window.privacyTimer)
    Swag.require(window.isExploring() and window.exploredFolders.isEmpty())
    Swag.require((expect ThumbnailCache.key(member, privacy: inherited)).isEmpty())
    window.rememberRecent(member)
    window.rememberExplored(root)
    Swag.require(window.recent.count == 1 and window.recent[0] == publicFile)
    let saved = saveViewerState(window)
    Swag.require(not Utf8.contains(saved, "scope-member-") and not Utf8.contains(saved, "scope-private-folder-"))
}

// In-flight preview writes cannot publish under an old epoch, and clearing one mount keeps
// the cache belonging to another public mount.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-private-cache-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let secondRoot = Path.combine(root, "second")
    expect Directory.create(secondRoot)
    let file      = Path.combine(root, "image.bin")
    let otherFile = Path.combine(secondRoot, "other.bin")
    discard expect File.writeAllText(file, "source")
    discard expect File.writeAllText(otherFile, "other")
    var first:  File.MountPrivacyPublisher
    var second: File.MountPrivacyPublisher
    expect first.open(root, false)
    expect second.open(secondRoot, false)
    let policy   = File.MountPrivacy.query(file)
    let key      = expect ThumbnailCache.key(file)
    let otherKey = expect ThumbnailCache.key(otherFile)
    var image    = Image.create(8, 8, .RGB8)
    expect ThumbnailCache.write(key, &image, file)
    expect ThumbnailCache.write(otherKey, &image, otherFile)
    Swag.require(File.exists(key) and File.exists(otherKey))
    first.setPrivateMode(true)
    Swag.require((expect ThumbnailCache.key(file)).isEmpty())
    expect ThumbnailCache.clearMount(policy.channel)
    Swag.require(not File.exists(key) and File.exists(otherKey))
    expect ThumbnailCache.write(key, &image, file)
    Swag.require(not File.exists(key))
    first.setPrivateMode(false)
    expect ThumbnailCache.write(key, &image, file)
    Swag.require(not File.exists(key))
    let current = expect ThumbnailCache.key(file)
    Swag.require(current != key)
    expect ThumbnailCache.write(current, &image, file)
    Swag.require(File.exists(current))
    expect ThumbnailCache.clearMount(policy.channel)
    expect ThumbnailCache.clearMount(File.MountPrivacy.query(otherFile).channel)
}

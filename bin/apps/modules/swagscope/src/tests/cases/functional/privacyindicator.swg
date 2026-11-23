#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The live privacy mark follows folders, documents, public destinations and policy changes.
#test
{
    let root          = Testing.tempFilePath("scope-private-indicator-", "")
    let privateFolder = Path.combine(root, "Private")
    let publicFolder  = Path.combine(root, "Public")
    expect Directory.create(privateFolder, recurse: true)
    expect Directory.create(publicFolder)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(privateFolder, "note.txt")
    discard expect File.writeAllText(file, "A private note.")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(privateFolder, true)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    host.surface.updateFlags(.StandardWindow | .NoShadow)
    let window  = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let caption = unwrap window.privacy.caption
    Swag.require(not caption.isLocallyVisible())
    window.openExplorer(privateFolder)
    completeExplorer(&host, unwrap window.explorer)
    Swag.require(caption.isLocallyVisible() and window.privacy.icons.isValid())
    Swag.require(caption.iconColor == host.theme.colors.critical)
    let image       = host.renderSurface(unwrap window.surface)
    let rect        = caption.surfaceRect()
    let glyphHeight = host.theme.metrics.wnd_CaptionButtonGlyph
    var shackle, body: u32
    for x in cast(s32, rect.x) until cast(s32, rect.right())
    {
        let upper = image.pixelColor(x, cast(s32, rect.vertCenter() - glyphHeight * 0.3))
        let lower = image.pixelColor(x, cast(s32, rect.vertCenter() + glyphHeight * 0.25))
        if cast(u32, upper.r) > cast(u32, upper.g) + 20 and cast(u32, upper.r) > cast(u32, upper.b) + 20 do
            shackle += 1
        if cast(u32, lower.r) > cast(u32, lower.g) + 20 and cast(u32, lower.r) > cast(u32, lower.b) + 20 do
            body += 1
    }

    Swag.require(body > shackle, "the Vault shackle must stay above its body")
    window.queueFile(file)
    completeQueuedViewerFile(&host, window)
    Swag.require(caption.isLocallyVisible())

    publisher.setPrivateMode(false)
    host.fireTimer(window.privacyTimer)
    Swag.require(not caption.isLocallyVisible())
    publisher.setPrivateMode(true)
    host.fireTimer(window.privacyTimer)
    Swag.require(caption.isLocallyVisible() and window.currentView != null)
    window.openExplorer(publicFolder)
    completeExplorer(&host, window.explorer)
    Swag.require(not caption.isLocallyVisible())
}

// The caption has one privacy indicator, even when several private documents are open.
#test
{
    let root = Testing.tempFilePath("scope-private-grid-", "")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let firstFile  = Path.combine(root, "first.txt")
    let secondFile = Path.combine(root, "second.txt")
    discard expect File.writeAllText(firstFile, "A private note.")
    discard expect File.writeAllText(secondFile, "Another private note.")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, true)

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([firstFile, secondFile, scopeTestDataPath("viewer.srt")], .Grid2)
    openViews(&host, workspace)
    let second  = unwrap workspace.scene()!.views[1].document
    let caption = unwrap workspace.primary.privacy.caption
    Swag.require(caption.isLocallyVisible() and second.privacy.caption == null)

    workspace.selectView(1)
    Swag.require(caption.isLocallyVisible())
    workspace.selectView(2)
    second.privacy.refreshIndicator()
    Swag.require(not caption.isLocallyVisible())
    workspace.selectView(0)
    Swag.require(caption.isLocallyVisible())
}

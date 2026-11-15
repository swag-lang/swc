#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A private folder carries the red Vault mark beside its navigation, in Encre.
#[Swag.TestTag("golden")]
#test
{
    let root = Testing.tempFilePath("scope-private-caption-", "")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    discard expect File.writeAllText(Path.combine(root, "note.txt"), "A private note.")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, true)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    shipFrame(&host)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(root)
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    explorer.setMode(.Names)
    explorer.address.breadcrumb.clear()
    explorer.address.breadcrumb.addItem("Swag Vault")
    explorer.address.breadcrumb.addItem("Private")
    explorer.address.refreshPath()
    window.applyLayout()
    Swag.require(window.privacy.caption!.isLocallyVisible())
    let image = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "privacy.folder.encre")
}

// A private document retains the same mark when the folder's navigation is replaced, in Papier.
#[Swag.TestTag("golden")]
#test
{
    let root = Testing.tempFilePath("scope-private-document-caption-", "")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    let file = Path.combine(root, "note.txt")
    discard expect File.writeAllText(file, "A private note.")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, true)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    host.theme.setLight()
    host.notify(.ThemeChanged)
    shipFrame(&host)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.queueFile(file)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.privacy.caption!.isLocallyVisible())
    let image = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "privacy.document.papier")
}

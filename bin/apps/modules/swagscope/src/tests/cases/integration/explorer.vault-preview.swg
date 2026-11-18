#global if #command == Swag.CompilerCommand.Test and WINDOWS and #hastag("vault.preview.integration")
#global private

using Core, Gui, Pixel, Video, Viewers

// Opening, seeking, and generating a thumbnail give the same results through a mounted volume.
#[Swag.TestTag("integration.vault.preview")]
#test
{
    let source    = Env.variable("SWAG_VAULT_PREVIEW_VIDEO")
    let mountRoot = Env.variable("SWAG_VAULT_PREVIEW_ROOT")
    Swag.require(File.exists(source) and Directory.exists(mountRoot))

    let mountedPath = Path.combine(mountRoot, Path.fileName(source) orelse "")
    Swag.require(File.exists(mountedPath))
    var local   = expect Reader.open(source, pictureOnly: true)
    var mounted = expect Reader.open(mountedPath, pictureOnly: true)
    Swag.require(local.frameCount() == mounted.frameCount())
    let at = local.durationInSeconds() * 0.3
    Swag.require(at > 0 and at < mounted.durationInSeconds())
    let original = expect local.decodeKeyPicture(at)
    let stored   = expect mounted.decodeKeyPicture(at)
    Swag.require(original.isValid() and stored.isValid())
    Swag.require(original.width == stored.width and original.height == stored.height)
    Swag.require(Slice.equals(original.pixels.toSlice(), stored.pixels.toSlice()))

    let expected = expect Film.loadThumbnail(source)
    let actual   = expect Film.loadThumbnail(mountedPath)
    Swag.require(expected.isValid() and actual.isValid())
    Swag.require(expected.width == actual.width and expected.height == actual.height)
    Swag.require(Slice.equals(expected.pixels.toSlice(), actual.pixels.toSlice()))
}

// Explorer presents previews through its normal background pipeline.
#[Swag.TestTag("integration.vault.explorer")]
#test
{
    let mountRoot = Env.variable("SWAG_VAULT_PREVIEW_ROOT")
    Swag.require(Directory.exists(mountRoot))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = Env.variable("SWAG_VAULT_PREVIEW_ONLINE") == "1"

    var pictured = 0'u64
    window.openExplorer(mountRoot)
    let explorer = unwrap window.explorer
    for 2000
    {
        host.pump()
        pictured = 0
        for &entry in explorer.entries where entry.texture.isValid() do
            pictured += 1

        if pictured and pictured == explorer.entries.count do
            break
        Threading.Thread.sleep(20'ms)
    }

    Swag.require(pictured > 0)
    for &entry in explorer.entries where entry.texture.isValid() do
        Swag.require(entry.attempted and not entry.onlinePending)
}

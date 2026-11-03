#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// The size of the charter's pictures, which the goldens are taken at to be judged whole against them.
const PictureWidth  = 1280'f32
const PictureHeight = 800'f32

// Renders the window as it stands, in Encre or in Papier, and compares it with the golden `name`.
//
// The chrome is not part of what these images pin: a headless surface has no desktop under it, so
// its shadow falls on nothing and its rounded corner only punches holes in the captured pixels.
// Applying a palette puts the geometry of that palette back, so it is squared again here.
func assertSurfaceGolden(host: *Testing.HeadlessHost, window: *MainWindow, dark: bool, name: string)
{
    if dark do
        host.theme.setDark()
    else do
        host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 6)

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, Format.toString("%.%", name, dark ? "encre" : "papier"))
}

// What the list looks like, against `vault.list`: a title, one vault mounted on its own ground
// with its actions, two at rest, the two quiet words, and the hint line. One host per palette:
// a render target keeps what the last paint left.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    fillPictureList(window)
    assertSurfaceGolden(&host, window, true, "list")
}

// A locked vault unfolded in place, against `vault.unlock.paper`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    fillPictureList(window)
    window.chooseVault("C:\\vault.bin")
    assertSurfaceGolden(&host, window, false, "unlock")
}

// The page that creates a vault, against `vault.create.paper`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    window.showPage(.Create, animate: false)
    window.createPath.setText("C:\\Users\\vault\\Documents\\papiers.bin")

    // The room left on a volume belongs to the machine, so the picture states it.
    window.createPage.showFreeSpace(212'u64 * 1024 * 1024 * 1024, "C:\\")
    assertSurfaceGolden(&host, window, true, "create")
}

// The randomisation of a new container, against `vault.progress`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    let texts  = appStrings()
    window.progressPage.begin("C:\\Users\\vault\\papiers.bin", texts.ui_Randomizing, texts.ui_RandomizeHelp, texts.ui_StopCreating)
    window.progressPage.setProgress(0.62, 159 * 1024 * 1024, 256 * 1024 * 1024, Format.toString(texts.ui_SecondsLeft, 12))
    window.showPage(.Progress, animate: false)
    assertSurfaceGolden(&host, window, false, "progress")
}

// The privacy page, against `vault.options`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    window.showPage(.Options, animate: false)
    assertSurfaceGolden(&host, window, true, "options")
}

// File actions stay first above the chosen vault, including French at a non-default scale.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    useTestDestination(window)
    window.openVault("C:\\vaults\\example")
    window.lens.open()
    Swag.assert(window.lens.chosenEntry()!.id == VaultCommands.NewVault)
    host.settleAnimations(window)
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "surface.lens.paper")
}

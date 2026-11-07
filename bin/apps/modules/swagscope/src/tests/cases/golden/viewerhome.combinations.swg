#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing

// Pins each density of recent files against each density of explored folders. System places are
// cleared so zero folders means no folder chip at all, including on a first launch.
func assertHomeCombination(files, folders: u32, light: bool, name: string)
{
    var host: HeadlessHost
    host.setup(960, 720)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 720)
    window.recent.clear()
    window.recentOpened.clear()
    window.exploredFolders.clear()
    window.systemPlaces.clear()

    const Names: [4] string = ["comprehensive.md", "title.png", "sample.cpp", "viewer.pdf"]
    for index in files
    {
        window.recent.add(scopeTestDataPath(Names[index]))
        window.recentOpened.add(HomeNow - cast(u64, index) * Time.TicksPerHour)
    }

    let data = scopeTestDataDirectory()
    let tests = Path.directoryName(data) orelse ""
    let sources = Path.directoryName(tests) orelse ""
    let Paths: [3] string = [data, tests, sources]
    for index in folders do
        window.exploredFolders.add(Paths[index])

    window.home.now = HomeNow
    window.showEmpty(appStrings().ui_DropTitle)
    window.applyLayout()
    completeHomePreviews(&host, window.home)

    let home = window.home
    let place = home.layout()
    Swag.require(home.rows.count == files and home.places.count == folders)
    Swag.require(home.explored == (folders != 0))
    Swag.require(home.openButton.isLocallyVisible() and home.exploreButton.isLocallyVisible())
    Swag.require(home.resumeButton.isLocallyVisible() == (files != 0))
    Swag.require(home.clearButton.isLocallyVisible() == (files != 0))
    Swag.require(not home.restartButton.isLocallyVisible())
    Swag.require(place.showPlaces == (folders != 0))
    Swag.require(home.openButton.position.y == place.actions and home.exploreButton.position.y == place.actions)
    Swag.require(host.mouseTargetAt(home.localToSurface(home.openButton.position.center())) == home.openButton)
    Swag.require(host.mouseTargetAt(home.localToSurface(home.exploreButton.position.center())) == home.exploreButton)
    if folders != 0 do
        Swag.require(home.placeShown(folders - 1))

    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, name)
}

#[Swag.TestTag("golden")]
#test { assertHomeCombination(0, 0, false, "home.none.encre") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(0, 1, true, "home.folder.paper") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(0, 3, false, "home.folders.encre") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(1, 0, true, "home.file.paper") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(1, 1, false, "home.file-folder.encre") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(1, 3, true, "home.file-folders.paper") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(4, 0, false, "home.files.encre") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(4, 1, true, "home.files-folder.paper") }

#[Swag.TestTag("golden")]
#test { assertHomeCombination(4, 3, false, "home.files-folders.encre") }

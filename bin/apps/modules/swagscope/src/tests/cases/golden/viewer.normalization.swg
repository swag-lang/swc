#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A narrow document keeps a useful Find field and reachable controls beside both side panels.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), true, width: ViewerWindow.MinWidth)
    window.toggleFilePanel()
    window.toggleInformation()
    window.showSearch()
    window.applyLayout()
    Swag.require(window.searchBox.position.width >= 120)
    Swag.require(window.searchBar.position.bottom() <= window.infoSheet.position.y)
    Swag.require(window.searchNavigation.position.x >= 0)
    Swag.require(window.searchBar.position.bottom() <= window.documentArea().y)
    var image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.find.narrow.paper")
}

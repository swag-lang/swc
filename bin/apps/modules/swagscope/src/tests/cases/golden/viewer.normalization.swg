#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A narrow document keeps a useful Find field and reachable controls beside the information sheet.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), true, width: ViewerWindow.MinWidth)

    window.toggleInformation()
    window.showSearch()
    window.applyLayout()
    Swag.require(window.searchBox.position.width >= 120)
    Swag.require(window.searchBar.position.right() <= window.infoSheet.position.x)
    Swag.require(window.searchNavigation.position.x >= 0)
    Swag.require(window.searchBar.position.bottom() <= window.documentArea().y)
    var image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.find.narrow.paper")
}

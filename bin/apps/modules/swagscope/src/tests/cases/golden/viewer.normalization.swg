#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A narrow document keeps a useful Find field and reachable controls beside the information sheet.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost

    // Pixel owns these faces until module shutdown; the host copies their pointer list.
    let cjk    = expect TypeFace.create("scope-fixture-cjk", #include("../../datas/font-fixture-cjk.otf"))
    let arabic = expect TypeFace.create("scope-fixture-arabic", #include("../../datas/viewer.arabic.ttf"))
    let emoji  = expect TypeFace.create("scope-fixture-emoji", #include("../../datas/font-fixture-emoji.ttf"))
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), true, width: ViewerWindow.MinWidth, fallbackFaces: [cjk, arabic, emoji])
    let font   = host.theme.createDefaultFont(16)
    for c in [cast(rune, 0xD55C), 0xAD6D, 0xC5B4, 0x0627, 0x0644, 0x0639, 0x1F642] do
        Swag.require(font.resolveRune(c).glyphIndex(c) != 0, "the multilingual fixture needs its own glyphs")

    window.toggleInformation()
    completeInformation(&host, window)
    window.information.entry.modified = "2026-01-01 12:00"
    window.information.location       = "fixtures"
    window.information.describe(window.infoSheet)
    window.showSearch()
    window.applyLayout()
    Swag.require(window.searchBox.position.width >= 120)
    Swag.require(window.searchBar.position.right() <= window.infoSheet.position.x)
    Swag.require(window.searchNavigation.position.x >= 0)
    Swag.require(window.searchBar.position.bottom() <= window.documentArea().y)
    var image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.find.narrow.paper")
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Context commands use the same live command metadata as the lens and anchored menus.
func captureScopeContextMenu(host: *Testing.HeadlessHost, golden: string)
{
    host.app.sigFrame += func|host, golden|(_)
    {
        let menu = unwrap host.capturedPopupMenu()
        for item in menu.items where item and not item.separator and not item.label do
            Swag.require(item.icon.isValid(), item.id)
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        assertScopeImageGolden(&image, golden)
        Swag.require(host.dismissPopupMenu())
    }
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.console.exe"), true)
    let view   = assume cast(*Binary.Panel, window.currentView)
    captureScopeContextMenu(&host, "menus.binary.context.paper")
    view.showContextMenu({350, 240})
    host.app.sigFrame.clear()
    host.pump()
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("title.png"), false)
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        break
    }

    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Hex.Panel, window.currentView)
    captureScopeContextMenu(&host, "menus.hex.context")
    view.grid.showContextMenu({350, 240})
    host.app.sigFrame.clear()
    host.pump()
}

// Exercise the shipped opener and modal path, keeping the surrounding view in the image.
internal func assertScopeAnchoredMenuWith(host: *Testing.HeadlessHost, window: *ViewerWindow, golden: string, open: func||())
{
    window.revealViewerBar()
    window.applyLayout()
    host.finishAnimations()
    var captured: bool
    host.app.sigFrame += func|host, golden, captured = &captured|(_)
    {
        if captured[] do
            return
        let menu  = host.capturedPopupMenu()
        let sheet = host.capturedOptionSheet()
        Swag.require(menu != null or sheet != null)
        if menu do
            for item in menu.items where item and not item.separator and not item.label do
                Swag.require(item.icon.isValid(), item.id)
        if sheet do
            for &row in sheet.page.rows where row.kind == .Action or row.kind == .Link or row.kind == .Toggle do
                Swag.require(row.icon.isValid(), row.label.raw)
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        assertScopeImageGolden(&image, golden)
        captured[] = true
        if menu do
            Swag.require(host.dismissPopupMenu())
        else do
            sheet!.close()
    }

    open()
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

internal func assertScopeAnchoredMenu(host: *Testing.HeadlessHost, window: *ViewerWindow, button: *IconButton, golden: string)
{
    assertScopeAnchoredMenuWith(host, window, golden, func|button|()
    {
        Swag.require(button.isVisible())
        button.sigPressed.call(cast(*Button, button))
    })
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: true, width: 960, height: 600)
    let explorer = unwrap window.explorer
    explorer.entries.add({name: "Illustrations", path: "Illustrations", directory: true, attempted: true})
    explorer.entries.add({name: "Notes.txt", path: "Notes.txt", attempted: true})
    showBoard(&host, window, "Projects", "Documents")
    assertScopeAnchoredMenu(&host, window, explorer.modeMenu, "menus.explorer.mode")
    assertScopeAnchoredMenu(&host, window, explorer.sortMenu, "menus.explorer.sort")
    assertScopeAnchoredMenu(&host, window, explorer.kindMenu, "menus.explorer.kind")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("title.png"), false)
    let view   = assume cast(*Picture.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.transformButton, "menus.image.transform")
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.image.zoom")
    assertScopeAnchoredMenu(&host, window, &view.playModeButton.button, "menus.image.playback")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("segoeui.ttf"), true)
    let view   = assume cast(*Typeface.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.pageLabel, "menus.font.range.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.groove.mid"), true)
    let view   = assume cast(*Midi.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.midi.zoom.paper")
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.midi.options.paper")
}

#[Swag.TestTag("golden")]
#test
{
    let file = createPdfFixture()
    defer discard catch File.delete(file)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, false)
    host.surface.setTitle("viewer.pdf")
    let view = assume cast(*PdfDocument.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.pdf.zoom")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.page.html"), true)
    let view   = assume cast(*Html.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.html.zoom.paper")
}

// A packaged document's archive alternative keeps the reader selector beside Information.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.epub"), false)
    for choice, index in window.choices where choice.key == "archive"
    {
        window.selectViewer(cast(u32, index))
        break
    }
    completeExplorer(&host, unwrap window.explorer)
    assertScopeAnchoredMenu(&host, window, &window.viewerCaptionButton.button, "menus.viewer.choices.archive")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), false)
    let view   = assume cast(*PlainText.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.text.zoom")
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.text.options")
    window.showSearch()
    assertScopeAnchoredMenu(&host, window, window.searchOptionsButton, "menus.search.options")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("sample.cpp"), true)
    let view   = assume cast(*Code.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, unwrap view.zoomLabel, "menus.code.zoom.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("title.png"), false)
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        break
    }

    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Hex.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, unwrap view.zoomLabel, "menus.hex.zoom")
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.hex.options")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, true, films: true)
    let explorer = unwrap window.explorer
    for name in ["Alien.mkv", "Arrival.mkv", "Heat.mkv"] do
        explorer.entries.add({name: name, path: name, attempted: true})
    showBoard(&host, window, "Projects", "Films")
    explorer.forceBoard(true, .Posters)
    Swag.require(explorer.showsMedia())
    assertScopeAnchoredMenu(&host, window, explorer.modeMenu, "menus.explorer.mode.films.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    assertScopeAnchoredMenu(&host, window, window.home.clearButton, "menus.home.clear")
}

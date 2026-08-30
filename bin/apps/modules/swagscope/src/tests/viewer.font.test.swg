#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType

func fontFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "segoeui.ttf")
}

func containsCharacter(characters: const [..] rune, expected: rune)->bool
{
    for character in characters where character == expected do
        return true
    return false
}

#test
{
    let bytes = expect File.readAllBytes(fontFixturePath())
    let face  = (expect Face.load(bytes.toSlice()))!
    defer face.destroy()

    let page = fontCharacterPage(face, 0x20, 192)
    Swag.assert(page.characters.count == 192)
    Swag.assert(containsCharacter(page.characters.toSlice(), 'A'))
    Swag.assert(page.end >= cast(u32) 'A' and page.hasNext)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(760, 520)
    defer host.shutdown()

    let fixture = fontFixturePath()
    var result  = openTestViewer(fontViewerPlugin(), &host.root, fixture, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)

    let view = cast(*FontViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert(view.details.indexOf("Segoe UI") != Swag.U64.Max)
    Swag.assert(view.document.hasCharacter('A'))
    let firstStart = view.document.pageStart
    view.document.nextPage()
    Swag.assert(view.document.pageStart > firstStart)
    view.document.previousPage()
    Swag.assert(view.document.pageStart == firstStart)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 720)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Top
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}

    let fixture = fontFixturePath()
    var result  = openTestViewer(fontViewerPlugin(), &host.root, fixture, commandParent: commandBar)
    Swag.assert(result.view != null)
    let view = cast(*FontViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle          = .Center
    view.commands.dockStyle = .Right

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.font.document")

    // Scrolled, because the document draws in content coordinates and the host translates it: a
    // view that also subtracted the position itself would scroll twice and leave the viewport empty
    // long before the end of the page, which is invisible in the golden above.
    let document = view.document
    document.scroll.setScrollPos(0, document.layout.gridTop + document.layout.cellHeight * 1.5)
    var scrolled = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&scrolled, "viewer.font.scrolled")
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-font-", ".ttf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a font")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    var result = openTestViewer(fontViewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let view = cast(*FontViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert(!view.failureReason.isEmpty())
}

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
    @assert(page.characters.count == 192)
    @assert(containsCharacter(page.characters.toSlice(), 'A'))
    @assert(page.end >= cast(u32) 'A' and page.hasNext)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(760, 520)
    defer host.shutdown()

    let fixture = fontFixturePath()
    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fixture}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view != null and result.commands != null)
    @assert(result.details.indexOf("Segoe UI") != Swag.U64.Max)

    let view = cast(*FontPluginView) result.view!
    @assert(view.document.hasCharacter('A'))
    let firstStart = view.document.pageStart
    view.document.nextPage()
    @assert(view.document.pageStart > firstStart)
    view.document.previousPage()
    @assert(view.document.pageStart == firstStart)
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
    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, commandBar, fixture}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view != null)
    let view = cast(*FontPluginView) result.view!
    view.dockStyle          = .Center
    view.commands.dockStyle = .Right

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "plugin.font.document")

    // Scrolled, because the document draws in content coordinates and the host translates it: a
    // view that also subtracted the position itself would scroll twice and leave the viewport empty
    // long before the end of the page, which is invisible in the golden above.
    let document = view.document
    document.scroll.setScrollPos(0, document.layout.gridTop + document.layout.cellHeight * 1.5)
    var scrolled = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&scrolled, "plugin.font.scrolled")
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-font-", ".ttf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a font")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}

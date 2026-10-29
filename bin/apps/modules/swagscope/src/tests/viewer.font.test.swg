#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType, Viewers

func fontFixturePath()->String => Path.combine(Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas"), "segoeui.ttf")

func containsCharacter(characters: const [..] rune, expected: rune)->bool
{
    for character in characters where character == expected do
        return true
    return false
}

#test
{
    let bytes = expect File.readAllBytes(fontFixturePath())
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()

    let page = Typeface.characterPage(face, 0x20, 192)
    Swag.assert(page.characters.count == 192)
    Swag.assert(containsCharacter(page.characters.toSlice(), 'A'))
    Swag.assert(page.end >= cast(u32, 'A') and page.hasNext)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(760, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let fixture = fontFixturePath()
    var result  = openTestViewer(Typeface.viewerPlugin(), &host.root, fixture, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)

    let view = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.assert(view.pageLabel.arrowPosition == .RightUpward)
    Swag.assert(view.details.indexOf("Segoe UI") != Swag.U64.Max)
    Swag.assert(view.document.hasCharacter('A'))
    let firstStart = view.document.pageStart
    view.document.nextPage()
    Swag.assert(view.document.pageStart > firstStart)
    view.document.previousPage()
    Swag.assert(view.document.pageStart == firstStart)
    view.document.goToCharacterPage(0x370)
    Swag.assert(view.document.pageStart >= 0x370 and not view.document.history.isEmpty())

    let oldPlaceholder = String.from(view.sampleEdit.name.raw)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.sampleEdit.name.raw == Typeface.texts().ui_SamplePlaceholder and view.sampleEdit.name.raw != oldPlaceholder)
    Swag.assert(view.previousButton.toolTip == Typeface.texts().ui_PreviousPage)
    Swag.assert(view.nextButton.toolTip == Typeface.texts().ui_NextPage)
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 720)

    // The commands float over the document only while the pointer asks for them: at rest the
    // window shows the document alone.
    let commands = Wnd.create'Wnd(&host.root)
    commands.hide()

    let fixture = fontFixturePath()
    var result  = openTestViewer(Typeface.viewerPlugin(), &host.root, fixture, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle = .Center

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    // Scrolled, because the document draws in content coordinates and the host translates it: a
    // view that also subtracted the position itself would scroll twice and leave the viewport empty
    // long before the end of the page, which the top of the page would never show.
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

    var result = openTestViewer(Typeface.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let view = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.assert(not view.failureReason.isEmpty())
}

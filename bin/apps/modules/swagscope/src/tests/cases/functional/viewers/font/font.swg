#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType, Viewers

internal func fontFixturePath()->String => Path.combine(scopeTestDataDirectory(), "segoeui.ttf")

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
    Swag.require(page.characters.count == 192)
    Swag.require(containsCharacter(page.characters.toSlice(), 'A'))
    Swag.require(page.end >= cast(u32, 'A') and page.hasNext)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(760, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let fixture = fontFixturePath()
    var result  = openTestViewer(Typeface.viewerPlugin(), &host.root, fixture, commandParent: &host.root)
    Swag.require(result.view != null and result.commands != null)

    let view = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.pageLabel.arrowPosition == .RightUpward)
    Swag.require(view.details.indexOf("Segoe UI") != Swag.U64.Max)
    Swag.require(view.document.hasCharacter('A'))
    let firstStart = view.document.pageStart
    view.document.nextPage()
    Swag.require(view.document.pageStart > firstStart)
    view.document.previousPage()
    Swag.require(view.document.pageStart == firstStart)
    view.document.goToCharacterPage(0x370)
    Swag.require(view.document.pageStart <= 0x370 and view.document.pageEnd >= 0x370)

    let oldPlaceholder = String.from(view.sampleEdit.name.text)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.sampleEdit.name.text == Typeface.texts().ui_SamplePlaceholder and view.sampleEdit.name.text != oldPlaceholder)
    Swag.require(view.previousButton.toolTip == appStrings().ui_PreviousPage)
    Swag.require(view.nextButton.toolTip == appStrings().ui_NextPage)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-font-", ".ttf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a font")

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    var result = openTestViewer(Typeface.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view != null and result.commands != null)
    let view = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(not view.failureReason.isEmpty())
}

// A character typed into the lens, or its `U+` code point, is a row that shows its cell marked
// in the character map; one the face does not map is named so and cannot be chosen.
#test
{
    Swag.require(Typeface.queriedCharacter("Ω") == 'Ω' and Typeface.queriedCharacter(" u+3a9 ") == 'Ω')
    Swag.require(Typeface.queriedCharacter("U+20AC") == '€' and Typeface.queriedCharacter("U+") == 0)
    Swag.require(Typeface.queriedCharacter("U+D800") == 0 and Typeface.queriedCharacter("U+110000") == 0)
    Swag.require(Typeface.queriedCharacter("ab") == 0 and Typeface.queriedCharacter("") == 0)

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fontFixturePath(), false)
    let view   = assume cast(*Typeface.Panel, window.instances[window.activeChoiceIndex].view)
    completeViewerBackgroundLoad(&host, &view.load)

    func lensRow(host: *Testing.HeadlessHost, window: *ViewerWindow, query: string)->*Lens.Entry?
    {
        window.lens.open(query)
        host.finishAnimations()
        for section in window.lens.results.sections
        {
            for &entry in section!.entries where Utf8.startsWith(entry.title.toSlice(), "Show U+") do
                return entry
        }

        Swag.require(false, query)
        return null
    }

    let row = unwrap lensRow(&host, window, "U+03A9")
    Swag.require(row.title == Format.toString(Typeface.texts().ui_ShowCharacter, "U+03A9 Ω") and not row.disabled)
    row.run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.document.shown == 'Ω' and
                 view.document.pageStart <= 0x3A9 and
                 view.document.pageEnd >= 0x3A9)
    let top = view.document.scroll.scrollPosition().y
    Swag.require(view.document.layout.gridTop < top + view.document.clientRect().height)

    let none = unwrap lensRow(&host, window, "U+1F600")
    Swag.require(none.disabled and none.detail == Typeface.texts().ui_NotInFont)
    window.lens.close()
    host.finishAnimations()
}

// The information sheet gives what the face says of itself: its version, its designer and its
// notice, each as the face writes it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(760, 520)
    var result = openTestViewer(Typeface.viewerPlugin(), &host.root, fontFixturePath(), commandParent: &host.root)
    let view   = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let face = unwrap view.document.face
    Swag.require(not face.version.isEmpty() and not face.copyright.isEmpty())

    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, Format.toString("Version\n%", face.version).toString()), text)
    Swag.require(Utf8.contains(text, Format.toString("Copyright\n%", face.copyright).toString()), text)
    if not face.designer.isEmpty() do
        Swag.require(Utf8.contains(text, Format.toString("Designer\n%", face.designer).toString()), text)

    // The sheet counts what the face maps of each block the character map jumps to.
    Swag.require(Utf8.contains(text, "Coverage\nBasic Latin\n95 characters"), text)
}

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

    // A file that is no font has no specimen to redraw when the sample or the language changes.
    view.sampleEdit.setText("Sample")
    host.notify(.LanguageChanged)
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

    // The open information sheet follows the character the lens marks, as it follows a click.
    window.toggleInformation()
    host.finishAnimations()
    let row = unwrap lensRow(&host, window, "U+03A9")
    Swag.require(row.title == Format.toString(Typeface.texts().ui_ShowCharacter, "U+03A9 Ω") and not row.disabled)
    row.run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.document.shown == 'Ω' and
                 view.document.pageStart <= 0x3A9 and
                 view.document.pageEnd >= 0x3A9)
    let information = window.infoSheet.text()
    Swag.require(Utf8.contains(information, "Unicode\nU+03A9 · Ω"), information)
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

    // The OS/2 table gives the weight class and the embedding permissions, named as written.
    Swag.require(Utf8.contains(text, "Weight\n400 · Regular"), text)
    Swag.require(Utf8.contains(text, "Embedding\n"), text)
    Swag.require(Typeface.embeddingText(0) == "installable" and Typeface.embeddingText(0x0104) == "preview and print · no subsetting")
    Swag.require(Typeface.embeddingText(0x000C) == "editable" and Typeface.weightText(680) == "680 · Bold")
}

// A click on a cell of the map marks its character; the information sheet then gives its code
// point and glyph, and the lens copies it.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fontFixturePath(), false)
    let view   = assume cast(*Typeface.Panel, window.instances[window.activeChoiceIndex].view)
    let doc    = view.document
    doc.showCharacter('A')
    discard host.render(&host.surfaceWnd)
    doc.shown = 0

    // The cell of `A` is found back from a point inside it, as a click reads it.
    var index = Swag.U64.Max
    for cell, at in doc.cells where cell.character == 'A' do
        index = at
    Swag.require(index != Swag.U64.Max)
    let pitch = doc.layout.cellHeight + Typeface.CellGap
    let point = Math.Point{doc.layout.gridLeft + cast(f32, index % doc.layout.columns) * (Typeface.CellWidth + Typeface.CellGap) + 10,
                           doc.layout.gridTop + cast(f32, index / doc.layout.columns) * pitch + 10}
    Swag.require(doc.cellAt(point) == index and doc.cellAt({doc.layout.gridLeft - 4, point.y}) == Swag.U64.Max)

    doc.shown = 'A'
    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Unicode\nU+0041 · A") and Utf8.contains(text, "Glyph index\n"), text)

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Font", host.theme)
    entries.query = "copy"
    view.describeLens(&entries)
    var found = false
    for &entry in results.sections[0]!.entries where entry.title == Format.toString(Typeface.texts().ui_CopyCharacter, "A") do
        found = true
    Swag.require(found)
}

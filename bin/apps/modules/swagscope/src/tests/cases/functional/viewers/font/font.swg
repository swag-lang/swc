#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType, Viewers

internal func fontFixturePath()->String     => scopeTestDataPath("viewer.arabic.ttf")
internal func openTypeFixturePath()->String => scopeTestDataPath("font-fixture-cjk.otf")

func containsCharacter(characters: const [..] rune, expected: rune)->bool
{
    for character in characters where character == expected do
        return true
    return false
}

// A TTC exposes its named faces; switching replaces the owned outline and renderer face together.
#test
{
    let previousStore = String.from(Typeface.g_FaceSelectionStoreOverride)
    let storePath     = Gui.Testing.tempFilePath("scope-font-face-state-", ".json")
    Typeface.g_FaceSelectionStoreOverride = storePath
    defer
    {
        discard catch File.delete(storePath)
        Typeface.g_FaceSelectionStoreOverride = previousStore
    }

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.arabic.ttc"), false)
    let view   = assume cast(*Typeface.Panel, window.instances[window.activeChoiceIndex].view)
    completeViewerBackgroundLoad(&host, &view.load)

    Swag.require(view.faceCount == 2 and view.faceButton.isVisible() and view.faceButton.isEnabled())
    Swag.require(Utf8.contains(view.faceNames[0], "Regular") and Utf8.contains(view.faceNames[1], "Bold"))
    let regular = unwrap view.document.face
    Swag.require(not view.document.typeFace.isBold() and view.document.hasCharacter('ع'))
    expect view.selectFace(1)
    let bold = view.document.face
    Swag.require(bold != regular and view.document.typeFace.isBold())
    Swag.require(bold.styleName == "Bold" and view.document.hasCharacter('ع'))
    Swag.require(view.faceButton.text() == view.faceNames[1] and view.faceIndex == 1)

    expect view.selectFace(0)
    Swag.require(not view.document.typeFace.isBold() and view.faceIndex == 0)
}

// A damaged middle collection member is skipped; valid faces before and after it remain selectable.
#test
{
    let previousStore = String.from(Typeface.g_FaceSelectionStoreOverride)
    let storePath     = Gui.Testing.tempFilePath("scope-font-partial-face-state-", ".json")
    Typeface.g_FaceSelectionStoreOverride = storePath
    defer
    {
        discard catch File.delete(storePath)
        Typeface.g_FaceSelectionStoreOverride = previousStore
    }

    let path   = scopeTestDataPath("viewer.arabic.partial.ttc")
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, path, false)
    let view   = assume cast(*Typeface.Panel, window.instances[window.activeChoiceIndex].view)
    completeViewerBackgroundLoad(&host, &view.load)

    Swag.require(view.faceCount == 2 and view.faceNames.count == 2 and view.faceIndices.count == 2)
    Swag.require(view.faceIndices[0] == 0 and view.faceIndices[1] == 2)
    Swag.require(Utf8.contains(view.details, "1 of 3 collection faces could not be read"), view.details)
    Swag.require(not view.document.typeFace.isBold())
    expect view.selectFace(1)
    Swag.require(view.document.typeFace.isBold() and view.faceIndex == 1)
}

// Face choice persists across reopening only for the same canonical path and exact file content.
#test
{
    let previousStore = String.from(Typeface.g_FaceSelectionStoreOverride)
    let storePath     = Gui.Testing.tempFilePath("scope-font-face-persist-", ".json")
    let copyPath      = Gui.Testing.tempFilePath("scope-font-face-copy-", ".ttc")
    defer
    {
        discard catch File.delete(storePath)
        discard catch File.delete(copyPath)
        Typeface.g_FaceSelectionStoreOverride = previousStore
    }

    Typeface.g_FaceSelectionStoreOverride = storePath
    let sourcePath  = scopeTestDataPath("viewer.arabic.ttc")
    let sourceBytes = expect File.readAllBytes(sourcePath)
    expect File.writeAllBytes(copyPath, sourceBytes.toSlice())

    var saved: String
    scope
    {
        var host: Testing.HeadlessHost
        let first     = framedViewerWindow(&host, sourcePath, false)
        let firstView = assume cast(*Typeface.Panel, first.instances[first.activeChoiceIndex].view)
        completeViewerBackgroundLoad(&host, &firstView.load)
        expect firstView.selectFace(1)
        Swag.require(firstView.faceIndex == 1 and firstView.document.typeFace.isBold())
        saved = expect File.readAllText(storePath)
    }

    Swag.require(not Utf8.contains(saved, "viewer.arabic.ttc"))

    scope
    {
        var host: Testing.HeadlessHost
        let otherFile = framedViewerWindow(&host, copyPath, false)
        let otherView = assume cast(*Typeface.Panel, otherFile.instances[otherFile.activeChoiceIndex].view)
        completeViewerBackgroundLoad(&host, &otherView.load)
        Swag.require(otherView.faceIndex == 0 and not otherView.document.typeFace.isBold())
    }

    scope
    {
        var host: Testing.HeadlessHost
        let reopened     = framedViewerWindow(&host, sourcePath, false)
        let reopenedView = assume cast(*Typeface.Panel, reopened.instances[reopened.activeChoiceIndex].view)
        completeViewerBackgroundLoad(&host, &reopenedView.load)
        Swag.require(reopenedView.faceIndex == 1 and reopenedView.document.typeFace.isBold())
    }
}

#test
{
    let bytes = expect File.readAllBytes(fontFixturePath())
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()

    let page = Typeface.characterPage(face, 0x600, 192)
    Swag.require(page.characters.count == 192)
    Swag.require(containsCharacter(page.characters.toSlice(), 'ع'))
    Swag.require(page.end >= 0x0639 and page.hasNext)
}

// An openly licensed CFF-flavoured OpenType font is identified and rendered by the same viewer.
#test
{
    let path    = openTypeFixturePath()
    let choices = createViewerPluginRegistry().choices(path)
    Swag.require(not choices.isEmpty() and choices[0].key == "font")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, path, false)
    let view   = assume cast(*Typeface.Panel, window.instances[window.activeChoiceIndex].view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.document.hasCharacter('日'), view.details)
}

// A damaged CFF table reports a loading error while Binary and Hex remain available.
#test
{
    let path        = scopeTestDataPath("font-fixture-damaged.otf")
    let choices     = createViewerPluginRegistry().choices(path)
    var foundFont   = false
    var foundBinary = false
    var foundHex    = false
    for &choice in choices
    {
        foundFont   = foundFont or choice.key == "font"
        foundBinary = foundBinary or choice.key == "binary"
        foundHex    = foundHex or choice.key == "hex"
    }

    Swag.require(foundFont and foundBinary and foundHex)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Typeface.viewerPlugin(), &host.root, path, commandParent: &host.root)
    let view   = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(not view.failureReason.isEmpty())
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
    Swag.require(view.details.indexOf("Swag Scope Arabic Fixture") != Swag.U64.Max)
    Swag.require(view.document.hasCharacter('ع'))
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
    Swag.require(Typeface.texts().ui_ShowGlyph == "Afficher le glyphe % dans la table des caractères" and
                 Typeface.texts().ui_GlyphNoCharacter == "Ce glyphe n'a pas de caractère Unicode associé" and
                 Typeface.texts().ui_GlyphIdAbsent == "L'identifiant est hors de cette police")
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
    Swag.require(Typeface.queriedCharacter("ع") == 'ع' and Typeface.queriedCharacter(" u+0639 ") == 'ع')
    Swag.require(Typeface.queriedCharacter("U+20AC") == '€' and Typeface.queriedCharacter("U+") == 0)
    Swag.require(Typeface.queriedCharacter("U+D800") == 0 and Typeface.queriedCharacter("U+110000") == 0)
    Swag.require(Typeface.queriedCharacter("ab") == 0 and Typeface.queriedCharacter("") == 0)
    Swag.require(Typeface.queriedGlyphIndex("#123") == 123 and
                 Typeface.queriedGlyphIndex(" #0x7B ") == 123)
    Swag.require(Typeface.queriedGlyphIndex("#") == Swag.U32.Max and
                 Typeface.queriedGlyphIndex("#0xGG") == Swag.U32.Max and
                 Typeface.queriedGlyphIndex("#4294967296") == Swag.U32.Max)

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
    let row = unwrap lensRow(&host, window, "U+0639")
    Swag.require(row.title == Format.toString(Typeface.texts().ui_ShowCharacter, "U+0639 ع") and not row.disabled)
    row.run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.document.shown == 'ع' and
                 view.document.pageStart <= 0x639 and
                 view.document.pageEnd >= 0x639)
    Swag.require(view.history.canGoBack() and not view.history.canGoForward())
    view.goBack()
    Swag.require(view.document.shown == 0)
    Swag.require(view.history.canGoForward())
    view.goForward()
    Swag.require(view.document.shown == 'ع')

    // A block-row destination records the same logical page position and can be undone.
    var otherBlockPage = 0'u32
    for pageStart in view.document.pageStarts where pageStart != view.document.pageStart
    {
        otherBlockPage = pageStart
        break
    }

    Swag.require(otherBlockPage != 0)
    view.jumpToBlock(otherBlockPage)
    Swag.require(view.history.canGoBack())
    view.goBack()
    Swag.require(view.document.shown == 'ع' and
                 view.document.pageStart <= 0x639 and
                 view.document.pageEnd >= 0x639)

    let information = window.infoSheet.text()
    Swag.require(Utf8.contains(information, "Unicode\nU+0639 · ع"), information)
    let top = view.document.scroll.scrollPosition().y
    Swag.require(view.document.layout.gridTop < top + view.document.clientRect().height)

    let none = unwrap lensRow(&host, window, "U+1F600")
    Swag.require(none.disabled and none.detail == Typeface.texts().ui_NotInFont)
    window.lens.close()
    host.finishAnimations()

    // A glyph-ID search resolves through the generated font's cmap and marks that character.
    let face       = unwrap view.document.face
    let glyphIndex = face.glyphIndex('ع')
    Swag.require(glyphIndex < view.document.glyphCharacters.count and view.document.glyphCharacters[glyphIndex] == 'ع')
    let glyphName = unwrap face.glyphName(glyphIndex)
    Swag.require(glyphName == "uni0639")

    // A post-table glyph-name query resolves to the same mapped character without rescanning
    // the cmap when the lens query changes.
    window.lens.open(glyphName)
    host.finishAnimations()
    var namedGlyph: *Lens.Entry?
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where Utf8.contains(entry.title.toSlice(), glyphName) do
            namedGlyph = entry
    }

    Swag.require(namedGlyph != null)
    let named = namedGlyph
    Swag.require(named.title == Format.toString(Typeface.texts().ui_ShowGlyphName, glyphName, glyphIndex) and not named.disabled)
    named.run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.document.shown == 'ع')

    let glyphQuery = Format.toString("#%", glyphIndex)
    window.lens.open(glyphQuery)
    host.finishAnimations()
    var glyphRow: *Lens.Entry?
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where Utf8.contains(entry.title.toSlice(), glyphQuery.toString()) do
            glyphRow = entry
    }

    Swag.require(glyphRow != null)
    let found = glyphRow
    Swag.require(found.title == Format.toString(Typeface.texts().ui_ShowGlyph, glyphQuery) and not found.disabled)
    found.run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.document.shown == 'ع')

    // Glyph zero exists as .notdef but has no Unicode character; an out-of-range ID is distinct.
    window.lens.open("#0")
    host.finishAnimations()
    var missingCharacter: *Lens.Entry?
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where Utf8.contains(entry.title.toSlice(), "#0") do
            missingCharacter = entry
    }

    Swag.require(missingCharacter != null)
    Swag.require(missingCharacter.disabled and missingCharacter.detail == Typeface.texts().ui_GlyphNoCharacter)
    window.lens.close()
    host.finishAnimations()

    let absentQuery = Format.toString("#%", face.glyphCount)
    window.lens.open(absentQuery)
    host.finishAnimations()
    var absentGlyph: *Lens.Entry?
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where Utf8.contains(entry.title.toSlice(), absentQuery.toString()) do
            absentGlyph = entry
    }

    Swag.require(absentGlyph != null)
    Swag.require(absentGlyph.disabled and absentGlyph.detail == Typeface.texts().ui_GlyphIdAbsent)
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
    Swag.require(Utf8.contains(text, "Coverage\nBasic Latin\n14 characters"), text)

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
    doc.showCharacter('ع')
    discard host.render(&host.surfaceWnd)
    doc.shown = 0

    // The Arabic fixture cell is found back from a point inside it, as a click reads it.
    var index = Swag.U64.Max
    for cell, at in doc.cells where cell.character == 'ع' do
        index = at
    Swag.require(index != Swag.U64.Max)
    let pitch = doc.layout.cellHeight + Typeface.CellGap
    let point = Math.Point{doc.layout.gridLeft + cast(f32, index % doc.layout.columns) * (Typeface.CellWidth + Typeface.CellGap) + 10,
                           doc.layout.gridTop + cast(f32, index / doc.layout.columns) * pitch + 10}
    Swag.require(doc.cellAt(point) == index and doc.cellAt({doc.layout.gridLeft - 4, point.y}) == Swag.U64.Max)

    doc.shown = 'ع'
    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Unicode\nU+0639 · ع") and Utf8.contains(text, "Glyph index\n"), text)

    var results = Testing.lensResults("copy")
    var entries = Viewer.LensEntries.create(&results, "Font", host.theme)
    view.describeLens(&entries)
    var found = false
    for &entry in results.sections[0]!.entries where entry.title == Format.toString(Typeface.texts().ui_CopyCharacter, "ع") do
        found = true
    Swag.require(found)
}

#global internal
#global namespace Viewers.Typeface

using Core, Pixel, Gui, TrueType

// Offers the glyph surface for a TrueType or OpenType font, whatever it is called.
//
// The version number of a TrueType font is `1.0` written as a fixed-point number, which is why
// the signature is four bytes rather than four letters. `ttcf` opens a collection, `true` is what
// an older Apple font writes in the same place, and `OTTO` identifies OpenType CFF outlines.
private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    if content.startsWith("ttcf") or content.startsWith("true") or content.startsWith("OTTO") do
        return true
    return content.head.count >= 4 and
           content.head[0] == 0 and
           content.head[1] == 1 and
           content.head[2] == 0 and
           content.head[3] == 0
}

// Describes the font viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "font"
        .staticName   = "Font"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Font)
        .create       = &createViewer
        .probe        = &pluginProbe
        .smokeFixture = "font-fixture-cjk.otf"
        .addSelectors(".ttf;.ttc;.otf")
    }

    return result
}

private const CommandWidth = 512.0

// The Unicode blocks the character map can jump to: their first and last code points, and their
// names in [[blockNames]].
const BlockFirst: [5] u32 = [0x20, 0xA0, 0x370, 0x400, 0x2000]
const BlockLast:  [5] u32 = [0x7E, 0xFF, 0x3FF, 0x4FF, 0x2BFF]

// Returns the names of the blocks of [[BlockFirst]] in the active language.
func blockNames()->[5] string
{
    let strings = texts()
    return [strings.ui_BasicLatin, strings.ui_Latin1, strings.ui_Greek, strings.ui_Cyrillic, strings.ui_Symbols]
}

// What the panel reads about a face beyond its own fields: how much of each block of
// [[BlockFirst]] it maps, and what its OS/2 table declares. They are gathered once, on the loading
// worker, rather than whenever the lens, the range menu or the information sheet asks.
struct FaceFacts
{
    coverage:    [BlockFirst.count] u32     // Characters of each block the face maps.
    hasMetadata: bool     // Whether the face's metadata could be read.
    weight:      u16      // Weight class, when `hasMetadata`.
    embedding:   u16      // Embedding permission bits, when `hasMetadata`.
}

// A collection face selection is keyed to one exact path and file content, then stores the
// collection's original member index. Paths themselves are never written to the preference file.
struct FaceSelection
{
    identity:   String
    memberIndex: u32
}

struct FaceSelectionStore
{
    entries: Array'FaceSelection
}

private const FaceSelectionLimit = 64'u64
var g_FaceSelectionStoreOverride: String     // Test-only destination; empty uses the app-data store.

private func faceSelectionStorePath()->String
{
    if g_FaceSelectionStoreOverride.count do
        return String.from(g_FaceSelectionStoreOverride)
    return Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "scope", "font-faces.json")
}

private func faceSelectionIdentity(path: string, bytes: const [..] u8)->String
{
    var filePath = String.from(path)
    if WINDOWS do
        filePath.makeLower(.Unicode)

    var hash: Hash.Sha256
    hash.update(cast(const [..] u8, filePath.toString()))
    const Separator: [1] u8 = [0]
    hash.update(Separator)
    hash.update(bytes)
    let digest = hash.finalize()
    var result: String = "sha256:"
    for word in digest do
        result += Format.toString("%{X08}", word)
    return result
}

private func readFaceSelectionStore(path: string)->FaceSelectionStore
{
    let bytes = catch File.readAllBytes(path) { return {} }
    var decoder: Serialization.Decoder'Serialization.Read.Json
    let decoded = catch decoder.readAll'FaceSelectionStore(bytes.toSlice()) { return {} }
    var result = #move decoded[]
    Memory.delete(decoded)
    return result
}

private func selectedFaceMember(path: string, identity: string)->u32
{
    if File.MountPrivacy.query(path).privateMode do
        return Swag.U32.Max
    let store = readFaceSelectionStore(faceSelectionStorePath())
    for entry in store.entries where entry.identity == identity do
        return entry.memberIndex
    return Swag.U32.Max
}

private func saveFaceSelection(path, identity: string, memberIndex: u32) fail
{
    if File.MountPrivacy.query(path).privateMode do
        return

    let storePath = faceSelectionStorePath()
    var store = readFaceSelectionStore(storePath)
    for entry, index in store.entries where entry.identity == identity
    {
        store.entries.removeAtOrdered(index)
        break
    }
    store.entries.insertAt(0, FaceSelection{String.from(identity), memberIndex})
    while store.entries.count > FaceSelectionLimit do
        store.entries.removeBack()

    var encoder: Serialization.Encoder'Serialization.Write.Json
    var encoded: ConcatBuffer
    try encoder.writeAll(&encoded, store)
    let folder = Path.directoryName(storePath) orelse ""
    if folder.count do
        try Directory.create(folder, recurse: true)
    let temporary = Path.combine(folder, Format.toString(".font-faces-%.tmp", Guid128.random()))
    defer discard catch File.delete(temporary)
    try File.writeAllBytes(temporary, cast(const [..] u8, encoded.toString()))
    try File.move(storePath, temporary)
}

// What loading a font file produces: its bytes, the face and typeface built on them, the details
// line, the pages of the character map, and the facts the panel reads about the face.
#[Swag.NoCopy]
struct ViewerContent
{
    bytes:      Array'u8
    face:       *Face?
    typeFace:   *TypeFace?
    faceCount:  u32
    faceNames:  Array'String
    faceIndices: Array'u32     // Original TTC member indices for the faces the parser can load.
    cacheKey:   String
    selectionIdentity: String
    selectedFaceIndex: u32
    details:    String
    pageStarts: Array'u32
    glyphCharacters: Array'rune     // First mapped Unicode scalar for each glyph ID.
    glyphNames: Array'GlyphName    // Post/CFF names sorted on the font-loading worker.
    facts:      FaceFacts
}

impl ViewerContent
{
    mtd opDrop()
    {
        .face?.destroy()
    }
}

// Loads a font file for the viewer: its first face, a type face cached under the path and content
// checksum, and the details line, which counts the faces of a collection.
private func loadViewerContent(fileName: string)->ViewerContent fail
{
    var result: #returntype
    result.bytes = try File.readAllBytes(fileName)
    let collectionCount = try Face.countFaces(result.bytes.toSlice())
    let fileInfo = try File.info(fileName)
    result.selectionIdentity = faceSelectionIdentity(fileInfo.fullName, result.bytes.toSlice())

    // A broken collection member cannot invalidate its neighbors. Probe every original index
    // independently and retain only faces whose outline parser can load.
    for memberIndex in 0 until collectionCount
    {
        var candidate: *Face?
        var loadOutcome: Swag.Error
        catch { candidate = try Face.loadAt(result.bytes.toSlice(), memberIndex) } as loadOutcome
        if loadOutcome.value() != null do
            continue

        let face = unwrap candidate
        var name: String
        catch
        {
            let metadata = try Face.metadataAt(result.bytes.toSlice(), memberIndex)
            let family = metadata.typographicFamilyName.isEmpty() ? metadata.familyName.toString() : metadata.typographicFamilyName.toString()
            let style = metadata.typographicStyleName.isEmpty() ? metadata.styleName.toString() : metadata.typographicStyleName.toString()
            name = style.count == 0 ? family : Format.toString("% · %", family, style)
        }
        if name.isEmpty()
        {
            let style = face.styleName.isEmpty() ? texts().ui_Regular : face.styleName.toString()
            name = Format.toString("% · %", face.familyName, style)
        }
        face.destroy()
        result.faceIndices.add(memberIndex)
        result.faceNames.add(#move name)
    }

    result.faceCount = cast(u32, result.faceIndices.count)
    if not result.faceCount do
        fail InvalidFormatError{Errors.mkString(texts().ui_NoValidFaces)}

    result.selectedFaceIndex = 0
    let rememberedIndex = selectedFaceMember(fileName, result.selectionIdentity)
    for memberIndex, position in result.faceIndices where memberIndex == rememberedIndex do
        result.selectedFaceIndex = cast(u32, position)
    let selectedMember = result.faceIndices[result.selectedFaceIndex]
    result.face = try Face.loadAt(result.bytes.toSlice(), selectedMember)
    result.cacheKey = Format.toString("%|scope-font|%{X08}", fileName, Hash.Crc32.compute(result.bytes.toSlice()))
    result.typeFace = try TypeFace.createAt(result.cacheKey, result.bytes.toSlice(), selectedMember)

    let style = result.face.styleName.isEmpty() ? texts().ui_Regular : result.face.styleName.toString()
    if result.faceCount == 1 do
        result.details = Format.toString(texts().ui_DetailsSingle, result.face.familyName, style, result.face.glyphCount, result.face.unitsPerEm)
    else do
        result.details = Format.toString(texts().ui_DetailsCollection, result.face.familyName, style, result.face.glyphCount, result.face.unitsPerEm, result.faceCount)
    let unreadable = collectionCount - result.faceCount
    if unreadable do
        result.details += Format.toString(" · %", Format.toString(texts().ui_UnreadableFaces, unreadable, collectionCount))
    var start = 0x20'u32
    result.glyphCharacters.resize(result.face.glyphCount)
    for glyphIndex in result.face.glyphCount
    {
        if let name = result.face.glyphName(cast(u32, glyphIndex)) do
            result.glyphNames.add(GlyphName{String.from(name), cast(u32, glyphIndex)})
    }
    result.glyphNames.sort(func(a, b) => Text.compareNames(a.name.toSlice(), b.name.toSlice()))
    while start < 0x110000
    {
        let page = characterPage(result.face, start)
        if page.characters.isEmpty() do
            break
        result.pageStarts.add(cast(u32, page.characters[0]))
        for character in page.characters
        {
            let glyphIndex = result.face.glyphIndex(character)
            if glyphIndex < result.glyphCharacters.count and not result.glyphCharacters[glyphIndex] do
                result.glyphCharacters[glyphIndex] = character
        }
        if not page.hasNext do
            break
        start = page.end + 1
    }

    for &count, index in result.facts.coverage
    {
        for code in BlockFirst[index] to BlockLast[index] where result.face.hasChar(cast(rune, code)) do
            count[] += 1
    }

    catch
    {
        let metadata = try Face.metadataAt(result.bytes.toSlice(), selectedMember)
        result.facts.weight      = metadata.weight
        result.facts.embedding   = metadata.embedding
        result.facts.hasMetadata = true
    }

    return result
}

// Returns the character `query` names, or zero when it names none: one character typed as itself,
// or a Unicode code point written `U+` and its hexadecimal digits.
func queriedCharacter(query: string)->rune
{
    let text = Latin1.trim(query)
    if not text.count do
        return 0

    let {c, eat} = Utf8.decodeRune(text)
    if eat == text.count do
        return c == ' ' ? 0 : c
    if text.count < 3 or text.count > 8 or (text[0] != 'U'u8 and text[0] != 'u'u8) or text[1] != '+'u8 do
        return 0

    var code = 0'u32
    for index in 2 until text.count
    {
        let digit = hexDigitValue(text[index])
        if digit >= 16 do
            return 0
        code = code * 16 + digit
    }

    let result = cast(rune, code)
    return Utf8.isValidRune(result) ? result : 0
}

// Reads a lens query written `#123` or `#0x7B` as a glyph ID. A sentinel distinguishes an
// ordinary lens query from an invalid or overflowing glyph-ID query.
func queriedGlyphIndex(query: string)->u32
{
    let text = Latin1.trim(query)
    if text.count < 2 or text[0] != '#' do
        return Swag.U32.Max

    var base = 10'u32
    var start = 1'u64
    if text.count >= 4 and text[1] == '0' and (text[2] == 'x' or text[2] == 'X')
    {
        base = 16
        start = 3
    }
    if start >= text.count do
        return Swag.U32.Max

    var value = 0'u32
    for at in start until text.count
    {
        let digit = base == 16 ? hexDigitValue(text[at]) :
                    text[at] >= '0' and text[at] <= '9' ? cast(u32, text[at] - '0') : 16
        if digit >= base or value > (Swag.U32.Max - digit) / base do
            return Swag.U32.Max
        value = value * base + digit
    }
    return value
}

// The font viewer: a specimen of the face, a sample field, and the glyph pages browsed from the
// command bar.
struct FontMapPosition
{
    pageStart: u32
    character: rune
}

struct Panel
{
    using wnd: Wnd

    late
    {
        commands:       *Wnd
        sampleEdit:     *EditBox
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
        faceButton:     *PushButton
        document:       *DocumentView
    }

    details:       String
    fileName:      String
    facts:         FaceFacts
    faceCount:     u32
    faceIndex:     u32
    faceNames:     Array'String
    faceIndices:   Array'u32
    cacheKey:      String
    selectionIdentity: String
    sampleDefault: String
    load:          Viewer.BackgroundLoad'ViewerContent
    services:      Viewer.HostServices
    failureReason: String
    history: Viewer.History'FontMapPosition
}

private impl Panel
{
    mtd handlePageKey(key: *KeyEvent)->bool
    {
        let direction = Viewer.pageKeyDirection(key)
        if not direction or .load.isPending() or .document == null do
            return false
        if direction < 0 do
            .document.previousPage()
        else do
            .document.nextPage()
        .refreshPageCommands()
        return true
    }

    mtd handleHistoryKey(key: *KeyEvent)->bool
    {
        let direction = Viewer.historyKeyDirection(key)
        if direction < 0 do .goBack()
        elif direction > 0 do .goForward()
        return direction != 0
    }

    mtd currentMapPosition()->FontMapPosition
    {
        let character = .document.shown >= .document.pageStart and .document.shown <= .document.pageEnd ? .document.shown : cast(rune, 0)
        return { .document.pageStart, character }
    }

    mtd targetPageStart(start: u32)->u32
    {
        if .document.pageStarts.isEmpty() do
            return 0
        var target = .document.pageStarts[0]
        for page in .document.pageStarts where page <= start do
            target = page
        return target
    }

    mtd jumpToCharacter(character: rune)
    {
        let target = .targetPageStart(cast(u32, character))
        let current = .currentMapPosition()
        if current.pageStart != target or current.character != character do
            .history.visit(current)
        .document.showCharacter(character)
        .refreshPageCommands()
    }

    internal mtd jumpToBlock(start: u32)
    {
        let target = .targetPageStart(start)
        let current = .currentMapPosition()
        if current.pageStart != target do
            .history.visit(current)
        .document.goToCharacterPage(start)
        .refreshPageCommands()
    }

    mtd restoreMapPosition(position: FontMapPosition)
    {
        .document.goToCharacterPage(position.pageStart)
        if position.character do
            .document.showCharacter(position.character)
        elif .document.shown
        {
            .document.shown = 0
            .document.sigMarked.call(.document)
            .document.revealCharacterMap()
        }
        .refreshPageCommands()
    }

    internal mtd goBack()
    {
        if .history.canGoBack() do
            .restoreMapPosition(.history.back(.currentMapPosition()))
    }

    internal mtd goForward()
    {
        if .history.canGoForward() do
            .restoreMapPosition(.history.forward(.currentMapPosition()))
    }

    mtd refreshPageCommands()
    {
        .pageLabel.enable(not .document.pageStarts.isEmpty())
        .previousButton.enable(.document.pageIndex > 0)
        .nextButton.enable(.document.hasNext)
        .pageLabel.setText(Viewer.pageText(.document.pageIndex, .document.pageStarts.count))
        .pageLabel.toolTip = Format.toString("% · U+%{X04}–U+%{X04}", texts().ui_CharacterRange, .document.pageStart, .document.pageEnd)
    }

    mtd retranslate()
    {
        let replaceSample = .sampleEdit.text() == .sampleDefault.toString()
        .sampleDefault = texts().ui_DefaultSample
        if replaceSample do
            .sampleEdit.setText(.sampleDefault)

        .sampleEdit.setPlaceholder(texts().ui_SamplePlaceholder)
        .faceButton.setText(.faceNames.isEmpty() ? texts().ui_Faces : .faceNames[.faceIndex])
        .faceButton.toolTip = texts().ui_ChooseFace
        .previousButton.toolTip = appStrings().ui_PreviousPage
        .nextButton.toolTip     = appStrings().ui_NextPage
        if .document != null do
            .document.invalidate()
    }

    mtd showFaceMenu()
    {
        if .faceCount < 2 do
            return
        let icon = .theme().icon(.GoTo, themeRowIconSize(.themeMetrics()))
        let panel = me
        let names = panel.faceNames
        let selectedFace = panel.faceIndex
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            for name, index in names
            {
                let label = index == selectedFace ? Format.toString("✓ %", name[]) : name[]
                .addItem(label, Format.toString("scope.font.face.%", index), icon)
            }
        }
        let selected = menu.doModal(.faceButton.surfaceRect().center(), autoDestroy: true) orelse ""
        for index in 0 until .faceCount
        {
            if selected == Format.toString("scope.font.face.%", index)
            {
                var error: Swag.Error
                catch .selectFace(index) as error
                if error.value() != null do
                    .services.failed(me, Viewer.failureText(error.value()))
                return
            }
        }
    }

    // Loads a collection member before replacing the displayed face, preserving the old specimen
    // if either the outline parser or Pixel's shared face cache rejects the requested index.
    internal mtd selectFace(index: u32) fail
    {
        if index >= .faceCount do
            fail Errors.InvalidFormatError{texts().ui_InvalidFace}
        if index == .faceIndex do
            return

        let memberIndex = .faceIndices[index]
        var face = try Face.loadAt(.document.fontBytes.toSlice(), memberIndex)
        var ownsFace = true
        defer if ownsFace do face.destroy()
        let typeFace = try TypeFace.createAt(.cacheKey, .document.fontBytes.toSlice(), memberIndex)

        var facts: FaceFacts
        for &count, block in facts.coverage
        {
            for code in BlockFirst[block] to BlockLast[block] where face.hasChar(cast(rune, code)) do
                count[] += 1
        }
        catch
        {
            let metadata = try Face.metadataAt(.document.fontBytes.toSlice(), memberIndex)
            facts.weight      = metadata.weight
            facts.embedding   = metadata.embedding
            facts.hasMetadata = true
        }

        .document.replaceFace(face, typeFace)
        ownsFace = false
        .faceIndex = index
        .facts     = facts
        let style = face.styleName.isEmpty() ? texts().ui_Regular : face.styleName.toString()
        .details = Format.toString(texts().ui_DetailsCollection,
                                   face.familyName, style, face.glyphCount, face.unitsPerEm, .faceCount)
        .faceButton.setText(.faceNames[index])
        try saveFaceSelection(.fileName, .selectionIdentity, memberIndex)
        .refreshPageCommands()
        .services.showDetails(me, .details)
        .services.informationChanged(me)
    }

    // Gives the lens the sample, the pages of the glyph grid and the blocks it can jump to.
    internal mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        entries.add(strings.ui_EditSample,
                    .Edit,
                    func|view = me|()
                    {
                        view.sampleEdit.setFocus()
                        view.sampleEdit.selectAll()
                    },
                    bindId: "scope.font.editSample")
        entries.add(strings.ui_PreviousPage,
                    .ChevronLeft,
                    func|view = me|()
                    {
                        view.document.previousPage()
                        view.refreshPageCommands()
                    },
                    disabled: not .previousButton.isEnabled(),
                    defaultKey: {modifiers: .Control, key: .PageUp},
                    bindId: "scope.font.previousPage")
        entries.add(strings.ui_NextPage,
                    .ChevronRight,
                    func|view = me|()
                    {
                        view.document.nextPage()
                        view.refreshPageCommands()
                    },
                    disabled: not .nextButton.isEnabled(),
                    defaultKey: {modifiers: .Control, key: .PageDown},
                    bindId: "scope.font.nextPage")
        entries.add(strings.ui_Back, .ChevronLeft, func|view = me|() { view.goBack() },
                    disabled: not .history.canGoBack(), defaultKey: {modifiers: .Alt, key: .Left}, bindId: "scope.font.back")
        entries.add(strings.ui_Forward, .ChevronRight, func|view = me|() { view.goForward() },
                    disabled: not .history.canGoForward(), defaultKey: {modifiers: .Alt, key: .Right}, bindId: "scope.font.forward")

        // The character marked in the map, to paste elsewhere.
        if .document != null and .document.shown
        {
            var text: String
            text.append(.document.shown)
            entries.add(Format.toString(strings.ui_CopyCharacter, text),
                        .Copy,
                        func|view = me|()
                        {
                            var marked: String
                            marked.append(view.document.shown)
                            Clipboard.setString(marked)
                        },
                        bindId: "scope.font.copyCharacter")
        }

        // A typed character, or its code point after `U+`, is a cell of the map to go to.
        let character = queriedCharacter(entries.query)
        if character and not .load.isPending() and .document != null
        {
            let code   = Format.toString("U+%{X04} %", cast(u32, character), character)
            let mapped = .document.face and .document.face.hasChar(character)
            let entry  = entries.add(Format.toString(strings.ui_ShowCharacter, code),
                                     .GoTo,
                                     func|view = me, character|()
                                    {
                                        view.jumpToCharacter(character)
                                    },
                                     disabled: not mapped)
            if entry and not mapped do
                entry.detail = strings.ui_NotInFont
        }

        // A `#` query addresses a glyph ID directly. Many-to-one cmap aliases resolve to the
        // first Unicode scalar in the existing ordered character map; unmapped glyphs are named.
        let glyphIndex = queriedGlyphIndex(entries.query)
        if glyphIndex != Swag.U32.Max and not .load.isPending() and .document != null
        {
            let inFont = glyphIndex < .document.glyphCharacters.count
            let mapped = inFont and .document.glyphCharacters[glyphIndex] != 0
            let title  = Format.toString(strings.ui_ShowGlyph, Format.toString("#%", glyphIndex))
            let character = mapped ? .document.glyphCharacters[glyphIndex] : cast(rune, 0)
            let entry = entries.add(title,
                                    .GoTo,
                                    func|view = me, character|()
                                    {
                                        view.jumpToCharacter(character)
                                    },
                                    disabled: not mapped)
            if entry and not mapped do
                entry.detail = inFont ? strings.ui_GlyphNoCharacter : strings.ui_GlyphIdAbsent
        }

        // Glyph names are sorted once on the loading worker; exact lookup is binary and never
        // scans or reparses the face on the GUI thread.
        if entries.query.count >= 2 and not .load.isPending() and .document != null
        {
            let query = Latin1.trim(entries.query)
            var first = 0'u64
            var last = .document.glyphNames.count
            while first < last
            {
                let middle = first + (last - first) / 2
                if Text.compareNames(.document.glyphNames[middle].name.toString(), query) < 0
                    do first = middle + 1
                else do last = middle
            }

            if first < .document.glyphNames.count and
                Text.compareNames(.document.glyphNames[first].name.toString(), query) == 0
            {
                let name = .document.glyphNames[first].name.toString()
                let glyphIndex = .document.glyphNames[first].id
                let mapped = glyphIndex < .document.glyphCharacters.count and .document.glyphCharacters[glyphIndex] != 0
                let character = mapped ? .document.glyphCharacters[glyphIndex] : cast(rune, 0)
                let title = Format.toString(strings.ui_ShowGlyphName, name, glyphIndex)
                let entry = entries.add(title,
                                        .GoTo,
                                        func|view = me, character|()
                                        {
                                            view.jumpToCharacter(character)
                                        },
                                        disabled: not mapped)
                if entry and not mapped do
                    entry.detail = strings.ui_GlyphNoCharacter
            }
        }

        // A block the face maps nothing of cannot be shown, so it is offered disabled.
        let names = blockNames()
        for range, index in BlockFirst
        {
            entries.add(names[index],
                        .GoTo,
                        func|view = me, range|()
                        {
                            view.jumpToBlock(range)
                        },
                        disabled: .facts.coverage[index] == 0,
                        bindId: Format.toString("scope.font.block.%", range))
        }
    }

    // Offers the Unicode blocks the glyph grid can jump to, and shows the first page of the one
    // chosen.
    mtd showRangeMenu()
    {
        let icon      = .theme().icon(.GoTo, themeRowIconSize(.themeMetrics()))
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(texts().ui_BasicLatin, "scope.font.range.basic", icon, disabled: me.facts.coverage[0] == 0)
            .addItem(texts().ui_Latin1, "scope.font.range.latin1", icon, disabled: me.facts.coverage[1] == 0)
            .addItem(texts().ui_Greek, "scope.font.range.greek", icon, disabled: me.facts.coverage[2] == 0)
            .addItem(texts().ui_Cyrillic, "scope.font.range.cyrillic", icon, disabled: me.facts.coverage[3] == 0)
            .addItem(texts().ui_Symbols, "scope.font.range.symbols", icon, disabled: me.facts.coverage[4] == 0)
        }

        switch menu.doModal(.pageLabel, autoDestroy: true) orelse ""
        {
        case "scope.font.range.basic":    .jumpToBlock(0x20)
        case "scope.font.range.latin1":   .jumpToBlock(0xA0)
        case "scope.font.range.greek":    .jumpToBlock(0x370)
        case "scope.font.range.cyrillic": .jumpToBlock(0x400)
        case "scope.font.range.symbols":  .jumpToBlock(0x2000)
        }

        .refreshPageCommands()
    }
}

private impl IWnd for Panel
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = .handleHistoryKey(evt) or .handlePageKey(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        var content: ViewerContent
        .failureReason = .load.finish(&content)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .document            = DocumentView.create(me, unwrap content.face, unwrap content.typeFace, #move content.bytes, .sampleEdit)
        .document.pageStarts = #move content.pageStarts
        .document.glyphCharacters = #move content.glyphCharacters
        .document.glyphNames = #move content.glyphNames
        .document.sigMarked  += func|view = me|(_) { view.services.informationChanged(view) }
        content.face         = null
        .details             = #move content.details
        .facts               = content.facts
        .faceCount           = content.faceCount
        .faceNames           = #move content.faceNames
        .faceIndices         = #move content.faceIndices
        .cacheKey            = #move content.cacheKey
        .selectionIdentity   = #move content.selectionIdentity
        .faceIndex           = content.selectedFaceIndex
        .faceButton.enable(.faceCount > 1)
        .faceButton.show(.faceCount > 1)
        .faceButton.setText(.faceNames[0])
        .refreshPageCommands()
        .applyLayout()

        .services.showDetails(me, .details)
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    mtd retire()->bool
    {
        return .load.retire()
    }

    // Creates the specimen view of `fileName`, with its sample field and character-page controls
    // in `commands`, and starts loading the font in the background.
    func create(contentParent, commands: *Wnd, fileName: string, services: Viewer.HostServices)->*Panel
    {
        with let result = Wnd.create'Panel(contentParent, "scope.font")
        {
            .backgroundStyle = .View
            .fileName        = fileName
            .services        = services
            .commands        = commands
            .sampleDefault   = texts().ui_DefaultSample
        }

        result.createCommandBar()
        result.hookOnChildEvent = func|view = result|(_, evt)->bool
        {
            if evt is KeyEvent as key do
                return view.handlePageKey(key)
            return false
        }

        result.applyLayout()
        result.load.start(fileName, &loadViewerContent, result)
        return result
    }

    // Creates the sample field and the character-page controls in the command group.
    private mtd createCommandBar()
    {
        with .faceButton = PushButton.create(.commands, texts().ui_Faces, {0, 0, 128, 36})
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_ChooseFace
            .enable(false)
            .hide()
            .sigPressed += func|view = me|(_)
            {
                view.showFaceMenu()
            }
        }

        with .previousButton = Viewer.createPageStep(.commands, -1)
        {
            .dockStyle = .Left
            .enable(false)
            .sigPressed += func|view = me|(_)
            {
                view.document.previousPage()
                view.refreshPageCommands()
            }
        }

        with .pageLabel = Viewer.createPageReadout(.commands, "scope.font.range", texts().ui_CharacterRange)
        {
            .enable(false)
            .sigPressed += func|view = me|(_) { view.showRangeMenu() }
        }

        with .nextButton = Viewer.createPageStep(.commands, 1)
        {
            .enable(false)
            .sigPressed += func|view = me|(_)
            {
                view.document.nextPage()
                view.refreshPageCommands()
            }
        }

        with .sampleEdit = EditBox.create(.commands, .sampleDefault, {0, 0, 260, 36}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Center
            .margin.x  = 16
            .setMaximumLength(128)
            .setPlaceholder(texts().ui_SamplePlaceholder)
            .sigTextChanged += func|view = me|(_)
            {
                if view.document != null do
                    view.document.invalidate()
            }
        }
    }
}

impl Panel
{
    // Describes the face in the information sheet, titled by its family with the file name
    // leading its identity: how many glyphs it draws, then its style and its design grid.
    mtd describeInformation(sheet: *InfoSheet)
    {
        if .details.isEmpty() do
            return
        let face = .document.face
        if not face or face.familyName.isEmpty() do
            return
        sheet.setIdentity(Format.toString("% · %", sheet.title, sheet.identity))
        sheet.setTitle(face.familyName)
        var data: MediaInfoData
        data.addFigure(.Custom, glyphCountText(face.glyphCount))
        data.add(.Font, group: true)
        data.add(.Style, face.styleName.isEmpty() ? texts().ui_Regular : face.styleName.toString())
        data.add(.UnitsPerEm, Format.toString("%", face.unitsPerEm))

        // What the face says of itself, set literally: the names and the notice are its own text.
        if not face.version.isEmpty() do
            data.add(.Version, face.version.toString())
        if not face.designer.isEmpty() do
            data.add(.Designer, face.designer.toString())
        if not face.copyright.isEmpty() do
            data.add(.Copyright, face.copyright.toString())

        // The weight class and the embedding permissions the OS/2 table declares.
        if .facts.hasMetadata
        {
            data.add(.Weight, weightText(.facts.weight))
            data.add(.Embedding, embeddingText(.facts.embedding))
        }

        // How much of each block the character map jumps to the face maps.
        data.add(.Coverage, group: true)
        let names = blockNames()
        for count, index in .facts.coverage do
            data.addText(names[index], count ? characterCountText(count) : String.from(texts().ui_NotCovered))

        // The character marked in the map: its code point and the glyph the face draws it with.
        let shown = .document.shown
        if shown
        {
            var text: String
            text.append(shown)
            data.add(.Character, group: true)
            data.addText("Unicode", Format.toString("U+%{X04} · %", cast(u32, shown), text))
            data.add(.GlyphIndex, Format.toString("%", face.glyphIndex(shown)))
        }

        data.describe(sheet)
    }
}

// Names a weight class by its number and the name of the nearest hundred: `400 · Regular`.
func weightText(weight: u16)->String
{
    let t     = texts()
    let names = [t.ui_WeightThin, t.ui_WeightExtraLight, t.ui_WeightLight, t.ui_Regular, t.ui_WeightMedium,
                 t.ui_WeightSemiBold, t.ui_WeightBold, t.ui_WeightExtraBold, t.ui_WeightBlack]
    let index = Math.clamp(cast(s32, Math.round(cast(f32, weight) / 100)) - 1, 0, 8)
    return Format.toString("% · %", weight, names[index])
}

// Names the embedding permissions of an OS/2 `fsType`: the least restrictive usage its bits set,
// as the specification reads several, then the restrictions that come with it.
func embeddingText(fsType: u16)->String
{
    let t = texts()
    var result: String
    if fsType & 0x8 do
        result = String.from(t.ui_EmbedEditable)
    elif fsType & 0x4 do
        result = String.from(t.ui_EmbedPreview)
    elif fsType & 0x2 do
        result = String.from(t.ui_EmbedRestricted)
    else do
        result = String.from(t.ui_EmbedInstallable)
    if fsType & 0x100 do
        result += Format.toString(" · %", t.ui_EmbedNoSubset)
    if fsType & 0x200 do
        result += Format.toString(" · %", t.ui_EmbedBitmap)
    return result
}

// Creates the integrated TrueType specimen and character-map view.
func createViewer(host: Viewer.Host)
{
    let services = host.services()
    let view     = Panel.create(host.contentParent(), host.createCommandGroup(CommandWidth), host.fileName(), services)
    host.attachView(view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}

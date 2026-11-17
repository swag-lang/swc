#global internal
#global namespace Viewers.Typeface

using Core, Pixel, Gui, TrueType

// Offers the glyph surface for an sfnt font with TrueType outlines, whatever it is called.
//
// The version number of such a font is `1.0` written as a fixed-point number, which is why the
// signature is four bytes rather than four letters. `ttcf` opens a collection of them, and `true`
// is what an older Apple font writes in the same place. The probe leaves the `OTTO` signature of
// CFF-flavoured OpenType fonts unclaimed, although the shared font engine can load them.
private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    if content.startsWith("ttcf") or content.startsWith("true") do
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
        .smokeFixture = "segoeui.ttf"
        .addSelectors(".ttf;.ttc")
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

// What loading a font file produces: its bytes, the face and typeface built on them, and the
// details line.
#[Swag.NoCopy]
struct ViewerContent
{
    bytes:      Array'u8
    face:       *Face?
    typeFace:   *TypeFace?
    details:    String
    pageStarts: Array'u32
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
    let faceCount = try Face.countFaces(result.bytes.toSlice())
    result.face = try Face.load(result.bytes.toSlice())

    let cacheKey = Format.toString("%|scope-font|%{X08}", fileName, Hash.Crc32.compute(result.bytes.toSlice()))
    result.typeFace = try TypeFace.create(cacheKey, result.bytes.toSlice())
    let style = result.face.styleName.isEmpty() ? texts().ui_Regular : result.face.styleName.toString()
    if faceCount == 1 do
        result.details = Format.toString(texts().ui_DetailsSingle, result.face.familyName, style, result.face.glyphCount, result.face.unitsPerEm)
    else do
        result.details = Format.toString(texts().ui_DetailsCollection, result.face.familyName, style, result.face.glyphCount, result.face.unitsPerEm, faceCount)
    var start = 0x20'u32
    while start < 0x110000
    {
        let page = characterPage(result.face, start)
        if page.characters.isEmpty() do
            break
        result.pageStarts.add(cast(u32, page.characters[0]))
        if not page.hasNext do
            break
        start = page.end + 1
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

// The font viewer: a specimen of the face, a sample field, and the glyph pages browsed from the
// command bar.
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
        document:       *DocumentView
    }

    details:       String
    sampleDefault: String
    load:          Viewer.BackgroundLoad'ViewerContent
    services:      Viewer.HostServices
    failureReason: String
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
        .previousButton.toolTip = appStrings().ui_PreviousPage
        .nextButton.toolTip     = appStrings().ui_NextPage
        if not .load.isPending() do
            .document.invalidate()
    }

    // Gives the lens the sample, the pages of the glyph grid and the blocks it can jump to.
    internal mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        entries.add(strings.ui_EditSample, .Edit, func|view = me|()
        {
            view.sampleEdit.setFocus()
            view.sampleEdit.selectAll()
        })
        entries.add(strings.ui_PreviousPage,
                    .ChevronLeft,
                    func|view = me|()
                    {
                        view.document.previousPage()
                        view.refreshPageCommands()
                    },
                    disabled: not .previousButton.isEnabled(),
                    shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(strings.ui_NextPage,
                    .ChevronRight,
                    func|view = me|()
                    {
                        view.document.nextPage()
                        view.refreshPageCommands()
                    },
                    disabled: not .nextButton.isEnabled(),
                    shortcut: Input.formatKeyShortcut(.Control, .PageDown))

        // The character marked in the map, to paste elsewhere.
        if .document != null and .document.shown
        {
            var text: String
            text.append(.document.shown)
            entries.add(Format.toString(strings.ui_CopyCharacter, text), .Copy, func|view = me|()
            {
                var marked: String
                marked.append(view.document.shown)
                Clipboard.setString(marked)
            })
        }

        // A typed character, or its code point after `U+`, is a cell of the map to go to.
        let character = queriedCharacter(entries.query)
        if character and not .load.isPending() and .document != null
        {
            let code       = Format.toString("U+%{X04} %", cast(u32, character), character)
            let mapped     = .document.face and .document.face.hasChar(character)
            with let entry = entries.add(Format.toString(strings.ui_ShowCharacter, code),
                                         .GoTo,
                                         func|view = me, character|()
                                         {
                                             view.document.showCharacter(character)
                                             view.refreshPageCommands()
                                         },
                                         disabled: not mapped)
            {
                if not mapped do
                    .detail = strings.ui_NotInFont
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
                            view.document.goToCharacterPage(range)
                            view.refreshPageCommands()
                        },
                        disabled: .blockCoverage(index) == 0)
        }
    }

    // Counts the characters of block `index` of [[BlockFirst]] the face maps.
    mtd blockCoverage(index: u64)->u32
    {
        let face = .document.face
        if not face do
            return 0
        var result = 0'u32
        for code in BlockFirst[index] to BlockLast[index] where face.hasChar(cast(rune, code)) do
            result += 1
        return result
    }

    // Offers the Unicode blocks the glyph grid can jump to, and shows the first page of the one
    // chosen.
    mtd showRangeMenu()
    {
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(texts().ui_BasicLatin, "scope.font.range.basic", .theme().icon(.GoTo, themeRowIconSize(.themeMetrics())), disabled: me.blockCoverage(0) == 0)
            .addItem(texts().ui_Latin1, "scope.font.range.latin1", .theme().icon(.GoTo, themeRowIconSize(.themeMetrics())), disabled: me.blockCoverage(1) == 0)
            .addItem(texts().ui_Greek, "scope.font.range.greek", .theme().icon(.GoTo, themeRowIconSize(.themeMetrics())), disabled: me.blockCoverage(2) == 0)
            .addItem(texts().ui_Cyrillic, "scope.font.range.cyrillic", .theme().icon(.GoTo, themeRowIconSize(.themeMetrics())), disabled: me.blockCoverage(3) == 0)
            .addItem(texts().ui_Symbols, "scope.font.range.symbols", .theme().icon(.GoTo, themeRowIconSize(.themeMetrics())), disabled: me.blockCoverage(4) == 0)
        }

        switch menu.doModal(.pageLabel, autoDestroy: true) orelse ""
        {
        case "scope.font.range.basic":    .document.goToCharacterPage(0x20)
        case "scope.font.range.latin1":   .document.goToCharacterPage(0xA0)
        case "scope.font.range.greek":    .document.goToCharacterPage(0x370)
        case "scope.font.range.cyrillic": .document.goToCharacterPage(0x400)
        case "scope.font.range.symbols":  .document.goToCharacterPage(0x2000)
        }

        .refreshPageCommands()
    }
}

private impl IWnd for Panel
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = .handlePageKey(evt)
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
        .document.sigMarked  += func|view = me|(_) { view.services.showDetails(view, view.details) }
        content.face         = null
        .details             = #move content.details
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
                if not view.load.isPending() do
                    view.document.invalidate()
            }
        }
    }
}

// Creates the integrated TrueType specimen and character-map view.
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
        catch
        {
            let metadata = try Face.metadataAt(.document.fontBytes.toSlice(), 0)
            data.add(.Weight, weightText(metadata.weight))
            data.add(.Embedding, embeddingText(metadata.embedding))
        }

        // How much of each block the character map jumps to the face maps.
        data.add(.Coverage, group: true)
        let names = blockNames()
        for index in BlockFirst.count
        {
            let count = .blockCoverage(index)
            data.addText(names[index], count ? characterCountText(count) : String.from(texts().ui_NotCovered))
        }

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

func createViewer(host: Viewer.Host)
{
    let services = host.services()
    let view     = Panel.create(host.contentParent(), host.createCommandGroup(CommandWidth), host.fileName(), services)
    host.attachView(view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}

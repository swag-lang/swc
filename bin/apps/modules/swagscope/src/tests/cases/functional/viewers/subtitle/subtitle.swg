#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func subtitleViewerFixturePath()->String => scopeTestDataPath("viewer.srt")

// A minimum duration hides short rows, navigation skips them, and explicit reveals restore them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var result = openTestViewer(Captions.viewerPlugin(), &host.root, subtitleViewerFixturePath(), commandParent: &host.root)
    Swag.require(result.collectMatches != null and result.revealMatch != null)
    let view = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()

    view.setMinimumCueDuration(2)
    Swag.require(view.sheet.rows.count == view.track!.cueCount() and
                 not view.sheet.rows[0].visible and
                 view.sheet.rows[1].visible and
                 view.track.cueContent(1) == "A second caption\non two lines.")
    Swag.require(view.identity().contains("Cues ≥ 2.00 s"))
    Swag.require(view.navigateCue(true) and view.currentCue == 1 and view.timeButton.text() == "0:02")
    Swag.require(not view.navigateCue(true))

    // Search still covers hidden cues and clears the filter before revealing its result.
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "first caption", &matches)
    Swag.require(matches.count == 1 and result.revealMatch(matches[0], "first caption"))
    Swag.require(view.currentCue == 0 and
                 view.minimumCueDuration == 0 and
                 view.sheet.rows[0].visible and
                 view.timeButton.text() == "0:00")

    view.setMinimumCueDuration(2)
    Swag.require(view.currentCue == Swag.U64.Max and view.navigateCue(false) and view.currentCue == 1)
    Swag.require(view.revealCue(0) and view.minimumCueDuration == 0 and view.currentCue == 0)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.identity() == "Sous-titre 1 / 2 · SubRip")
}

// A generated field report exercises an entire WebVTT transcript, metadata blocks and speaker tags.
#test
{
    let fileName = scopeTestDataPath("viewer.field-notes.vtt")
    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var result = openTestViewer(Captions.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: &host.root)
    Swag.require(result.details == "12 cues · WebVTT")

    let view = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()
    Swag.require(view.identity().contains("WebVTT") and view.track!.cueCount() == 12)
    Swag.require(view.track!.cueContent(0) == "Good morning from North Basin; the boardwalk is clear today.")
    Swag.require(view.track.cueContent(9) == "Labels match the field sheet. Thanks; mark this station complete.")
    Swag.require(Utf8.contains(view.track.cueContent(11), "field office café"))

    view.revealTime(32)
    Swag.require(view.currentCue == 6 and view.timeButton.text() == "0:30")

    // The rhythm is a direct time navigator, and its click mapping follows the moving window.
    let rhythm = view.rhythm.clientRect()
    let width  = Math.min(Captions.CueSheet.ColumnWidth,
                          Math.max(0, rhythm.width - 2 * Captions.CueSheet.Gutter)) - 2 * Captions.CueSheet.NumberX
    let left   = Math.round((rhythm.width - width) * 0.5)
    let target = 39'f64
    let x      = left + cast(f32, (target - view.rhythm.timeWindowStart()) * cast(f64, width) / 60)
    host.click(view.rhythm.localToSurface(Math.Point{x, rhythm.height * 0.5}))
    Swag.require(view.currentCue == 7 and view.timeButton.text() == "0:36",
                 Format.toString("cue % at % (target %, start %, width %)", view.currentCue, view.timeButton.text(), target, view.rhythm.timeWindowStart(), width))
}

// Shift selection keeps cue indexes stable and copies the selected cues with their times.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-selection-", ".srt")
    defer discard catch File.delete(fileName)
    var source: String
    source += "1\n00:00:01,000 --> 00:00:02,000\nFirst\n\n"
    source += "2\n00:00:03,000 --> 00:00:04,000\nSecond\n\n"
    source += "3\n00:00:05,000 --> 00:00:06,000\nThird\n"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    var result = openTestViewer(Captions.viewerPlugin(), &host.root, fileName)
    let view   = assume cast(*Captions.Panel, result.view)
    view.setCurrentCue(0)
    view.sheet.setFocus()
    host.keyPress(.Down, .Shift)
    Swag.require(view.currentCue == 1)
    Swag.require(view.selectedCueCount() == 2)
    let selected = "1\n00:00:01,000 --> 00:00:02,000\nFirst\n2\n00:00:03,000 --> 00:00:04,000\nSecond"
    Swag.require(view.selectedCuesText() == selected)
    if Clipboard.isFake()
    {
        view.copySelectedCues()
        Swag.require(Clipboard.getString() == selected)
    }

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.sheet.toolTip == Captions.texts().ui_SelectCuesHint)
    var results = Testing.lensResults("")
    var entries = Viewer.LensEntries.create(&results, "Subtitles", host.theme)
    view.describeLens(&entries)
    var localizedCopy = false
    for &entry in results.sections[0]!.entries where entry.title == Captions.texts().ui_CopySelectedCues do
        localizedCopy = true
    Swag.require(localizedCopy)
    var normalizedCopy   = false
    var normalizedExport = false
    for &entry in results.sections[0]!.entries
    {
        if entry.title == Captions.texts().ui_CopyNormalized do
            normalizedCopy = true
        if entry.title == Captions.texts().ui_ExportNormalized do
            normalizedExport = true
    }

    Swag.require(normalizedCopy and normalizedExport)
}

// Normalized export is deterministic SubRip and reports decoded omissions.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-normalize-", ".vtt")
    defer discard catch File.delete(fileName)
    var source: String
    source += "WEBVTT\n\nbroken-id\n00:00:xx.000 --> 00:00:03.000\nBroken\n\n"
    source += "cue-west-bank\n00:00:01.000 --> 00:00:02.500 align:start\n<b>Morning</b> report\n"
    discard expect File.writeAllText(fileName, source)
    let destination = Gui.Testing.tempFilePath("scope-cues-normalized-", ".srt")
    defer discard catch File.delete(destination)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    var result     = openTestViewer(Captions.viewerPlugin(), &host.root, fileName)
    let view       = assume cast(*Captions.Panel, result.view)
    let normalized = "1\n00:00:01,000 --> 00:00:02,500\nMorning report\n\n"
    Swag.require((expect view.normalizedTranscript()) == normalized)
    let loss = view.normalizationLossSummary()
    Swag.require(Utf8.contains(loss, "WebVTT") and
                 Utf8.contains(loss, "SubRip") and
                 Utf8.contains(loss, "records: 1") and
                 Utf8.contains(loss, "identifiers"),
                 loss)
    expect view.exportNormalizedTranscriptTo(destination)
    Swag.require((expect File.readAllText(destination)) == normalized)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    let frenchLoss = view.normalizationLossSummary()
    Swag.require(Utf8.contains(frenchLoss, "identifiants") and Utf8.contains(frenchLoss, "enregistrements malformés ou vides ignorés par l’analyse : 1"), frenchLoss)
}

// Go-to-time reads the time as the lens does, from the start of the track and without an end: it
// accepts its documented forms and rejects values that only look like timestamps.
#test
{
    func dialogSeconds(text: string)->f64 => Viewer.parseTimeAddress(text, 0, Swag.F64.Max)
    Swag.require(dialogSeconds("90") == 90 and dialogSeconds("1:30") == 90)
    Swag.require(dialogSeconds("1:02:03.5") == 3_723.5 and dialogSeconds("100:00:00") == 360_000)
    for text in ["", "1:", "1:2:3:4", "-1", "NaN", "Infinity", "1e308:00", "1:60", "1:99", "1.5:30"] do
        Swag.require(dialogSeconds(text) < 0, text)
}

// The cues read as a list: the keyboard moves through them, the readings say the current one, and
// the search finds and marks words inside them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let fileName = subtitleViewerFixturePath()
    var result   = openTestViewer(Captions.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: &host.root)
    Swag.require(result.view != null and result.commands == null and result.info != null)
    Swag.require(result.collectMatches != null and
                 result.revealMatch != null and
                 result.searchBounds != null and
                 result.clearSearch != null)
    Swag.require(result.details == "2 cues · SubRip")

    let view = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()
    Swag.require(view.track!.cueCount() == 2 and view.currentCue == Swag.U64.Max)
    Swag.require(view.identity().contains("SubRip") and view.timeButton.text() == "0:06")

    view.sheet.setFocus()
    host.keyPress(.PageDown, .Control)
    Swag.require(view.currentCue == 0 and
                 view.cuePosition() == "Cue 1 / 2" and
                 view.timeButton.text() == "0:00")
    host.keyPress(.Down)
    Swag.require(view.currentCue == 1 and view.timeButton.text() == "0:02")
    host.keyPress(.Down)
    Swag.require(view.currentCue == 1)
    host.keyPress(.Home)
    Swag.require(view.currentCue == 0)
    host.keyPress(.End, .Control)
    Swag.require(view.currentCue == 1)

    // The words of a cue wrap at their own line breaks, and a match is marked on its words.
    Swag.require(view.sheet.rows[1].lines.count == 2)
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "second", &matches)
    Swag.require(matches.count == 1 and matches[0].major == 1)
    view.currentCue = 0
    Swag.require(result.revealMatch(matches[0], "second") and view.currentCue == 1)
    var bounds: Math.Rectangle
    Swag.require(result.searchBounds(matches[0], &bounds) and not bounds.isEmpty())
    result.clearSearch()
    Swag.require(not result.searchBounds(matches[0], &bounds))

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.cuePosition() == Format.toString(Captions.texts().ui_CuePosition, 2, 2).toString())
    Swag.require(view.timeButton.toolTip == Captions.texts().ui_GoToTime)
}

// A colon in the lens goes to the cue on screen at an instant, or to a cue by its number; the lens
// copies the current cue or the whole dialogue without its times.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, subtitleViewerFixturePath(), false)
    let view   = assume cast(*Captions.Panel, window.instances[window.activeChoiceIndex].view)

    window.lens.open(":0:03")
    host.finishAnimations()
    let times = unwrap window.lens.results.sections[0]
    Swag.require(times.entries[0].title == Format.toString(appStrings().lens_GoToTime, "0:03"), times.entries[0].title)
    times.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.currentCue == 1)

    // The first cue ends at 2 s, exclusively: that instant and the gap after it lead to the second.
    view.revealTime(1.99)
    Swag.require(view.currentCue == 0)
    view.revealTime(2.0)
    Swag.require(view.currentCue == 1)

    window.lens.open(":1")
    host.finishAnimations()
    var found = false
    for &entry in window.lens.results.sections[0]!.entries where entry.title == Format.toString(Captions.texts().ui_GoToCueNumber, 1)
    {
        Swag.require(entry.lead == "1")
        entry.run!()
        found = true
    }

    window.lens.close()
    host.finishAnimations()
    Swag.require(found and view.currentCue == 0)

    Swag.require(view.dialogueText() == "The first caption.\n\nA second caption\non two lines.", view.dialogueText())
    if Clipboard.isFake()
    {
        view.copyCurrentCue()
        Swag.require(Clipboard.getString() == "The first caption.", Clipboard.getString())
    }
}

// The information sheet gives the timing a subtitler checks: how many cues start before the one
// before them has ended, and the shortest time a cue stays on screen.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-timing-", ".srt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "1\n00:00:01,000 --> 00:00:04,000\nOne\n\n2\n00:00:03,500 --> 00:00:03,900\nTwo\n\n3\n00:00:05,000 --> 00:00:06,000\nThree\n")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    let view   = assume cast(*Captions.Panel, window.instances[window.activeChoiceIndex].view)
    let sheet  = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Overlapping cues\n1") and Utf8.contains(text, "Shortest cue\n0.40 s"), text)
}

// The ruler groups connected overlap chains but separates ranges that only touch at an exclusive end.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-overlap-groups-", ".srt")
    defer discard catch File.delete(fileName)
    var source: String
    source += "1\n00:00:01,000 --> 00:00:04,000\nOne\n\n"
    source += "2\n00:00:02,000 --> 00:00:03,000\nNested\n\n"
    source += "3\n00:00:03,500 --> 00:00:05,000\nChain\n\n"
    source += "4\n00:00:05,000 --> 00:00:06,000\nTouches end\n\n"
    source += "5\n00:00:08,000 --> 00:00:10,000\nLater one\n\n"
    source += "6\n00:00:09,000 --> 00:00:11,000\nLater two\n"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var result = openTestViewer(Captions.viewerPlugin(), &host.root, fileName)
    let view   = assume cast(*Captions.Panel, result.view)
    Swag.require(view.overlapGroups.count == 2)
    Swag.require(view.overlapGroups[0].firstCue == 0 and
                 view.overlapGroups[0].endCue == 3 and
                 view.overlapGroups[0].start == 1 and
                 view.overlapGroups[0].end == 5)
    Swag.require(view.overlapGroups[1].firstCue == 4 and
                 view.overlapGroups[1].endCue == 6 and
                 view.overlapGroups[1].start == 8 and
                 view.overlapGroups[1].end == 11)
    Swag.require(view.rhythm.toolTip == Captions.texts().ui_OverlapMarkerHint)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.rhythm.toolTip == Captions.texts().ui_OverlapMarkerHint)
}

// The words of a cue wrap greedily between words: every line fits the column, and the next word
// would not have.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-wrap-", ".srt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "1\n00:00:01,000 --> 00:00:04,000\nThe ferry left the harbour at dusk and nobody on the pier could say where it was bound that night\n")

    var host: Testing.HeadlessHost
    host.setup(560, 400)
    var result = openTestViewer(Captions.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: &host.root)
    let view   = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()

    let sheet = view.sheet
    let font  = sheet.wordsFont()
    let width = Math.max(1, sheet.column().width - sheet.wordsOrigin.x - Captions.CueSheet.WordsRight)
    let words = view.track!.cueContent(0)
    let row   = &sheet.rows[0]
    Swag.require(row.lines.count > 1 and sheet.wordsOrigin.x > Captions.CueSheet.TimesX and sheet.wordsOrigin.y == 0)
    for line, index in row.lines
    {
        Swag.require(Painter.measureString(words[line.start until line.end], font).width <= width)
        if index + 1 == row.lines.count do
            break
        var next = row.lines[index + 1].start
        while next < words.count and words[next] != ' ' do
            next += 1
        Swag.require(words[line.end] == ' ' and Painter.measureString(words[line.start until next], font).width > width)
    }
}

// Scrolled down a long list, the row the view cuts at its top is still written: the current cue
// there stands on the selection ground, and the next cue made current does not.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-scroll-", ".srt")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 40 do
        source += Format.toString("%\n00:%{02}:00,000 --> 00:%{02}:30,000\nCue %\n\n", index + 1, index, index, index + 1)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var result = openTestViewer(Captions.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: &host.root)
    let view   = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()

    let sheet = view.sheet
    let row   = &sheet.rows[20]
    let point = sheet.localToSurface(Math.Point{sheet.column().x + 8, row.height * 0.25})

    func groundAt(host: *Testing.HeadlessHost, view: *Captions.Panel, cue: u64, top: f32, point: Math.Point)->u32
    {
        view.setCurrentCue(cue)
        view.scroll.setScrollPos(0, top)
        var image = host.render()
        return image.pixelColor(cast(s32, point.x), cast(s32, point.y)).argb
    }

    let top = row.top + row.height * 0.5
    Swag.require(sheet.rows.count == 40 and top + sheet.clientRect().height < view.scroll.scrollSize.y)
    Swag.require(groundAt(&host, view, 20, top, point) != groundAt(&host, view, 21, top, point))
}

// The Go to Time box offers the start of the current cue as the clocks spell it, so accepting it
// as offered keeps the reader on that cue.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cues-goto-", ".srt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "1\n00:00:01,000 --> 00:00:02,000\nOne\n\n2\n00:00:05,000 --> 00:00:07,000\nTwo\n")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    let view   = assume cast(*Captions.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.revealCue(1))
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    view.promptGoToTime()
    Swag.require(host.autoHandled and view.currentCue == 1)
}

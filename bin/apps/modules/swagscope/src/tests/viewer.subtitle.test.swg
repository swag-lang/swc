#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func subtitleViewerFixturePath()->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/viewer.srt")

// Go-to-time accepts its documented forms and rejects values that only look like timestamps.
#test
{
    var seconds: f64
    Swag.assert(Captions.timeSeconds("90", &seconds) and seconds == 90)
    Swag.assert(Captions.timeSeconds("1:30", &seconds) and seconds == 90)
    Swag.assert(Captions.timeSeconds("1:02:03.5", &seconds) and seconds == 3_723.5)
    Swag.assert(not Captions.timeSeconds("", &seconds))
    Swag.assert(not Captions.timeSeconds("1:", &seconds))
    Swag.assert(not Captions.timeSeconds("1:2:3:4", &seconds))
    Swag.assert(not Captions.timeSeconds("-1", &seconds))
    Swag.assert(not Captions.timeSeconds("NaN", &seconds))
    Swag.assert(not Captions.timeSeconds("Infinity", &seconds))
    Swag.assert(not Captions.timeSeconds("1e308:00", &seconds))
    Swag.assert(not Captions.timeSeconds("1:60", &seconds))
    Swag.assert(not Captions.timeSeconds("1:99", &seconds))
    Swag.assert(not Captions.timeSeconds("1.5:30", &seconds))
}

// The dedicated viewer presents a searchable timed transcript rather than raw subtitle syntax.
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let fileName = subtitleViewerFixturePath()
    var result   = openTestViewer(Captions.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.commands == null and result.info != null)
    Swag.assert(result.collectMatches != null and
                result.revealMatch != null and
                result.searchBounds != null and
                result.clearSearch != null)
    Swag.assert(result.details == "SubRip")

    let view = assume cast(*Captions.Panel, result.view)
    Swag.assert(view.track!.cueCount() == 2)
    Swag.assert(view.currentCue == Swag.U64.Max)
    Swag.assert(view.cueButton.text() == "2 cues" and view.durationButton.text().count)
    var initialCue = KeyEvent{kind: .Pressed, key: .PageDown, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &initialCue) and view.currentCue == 0)
    Swag.assert(view.editor.selectedText() == "The first caption.")
    Swag.assert(view.cueButton.text() == "1 / 2")
    Swag.assert(view.transcript.indexOf("00:00:00.500") != Swag.U64.Max)
    Swag.assert(view.transcript.indexOf("A second caption\non two lines.") != Swag.U64.Max)

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "second", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1)
    var revealed = result.revealMatch(matches[0], "second")
    Swag.assert(revealed and view.currentCue == 1 and view.cueButton.text() == "2 / 2")
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds(matches[0], &bounds) and not bounds.isEmpty())
    result.clearSearch()
    revealed = view.revealCue(1) and view.editor.selectedText() == "A second caption\non two lines."
    Swag.assert(revealed)
    view.editor.setCursorPos(view.editor.cursorFromLogicalPosition(1, 0))
    view.syncCurrentCue()
    Swag.assert(view.currentCue == 0 and view.cueButton.text() == "1 / 2")
    var previousCue = KeyEvent{kind: .Pressed, key: .PageUp, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.editor, &previousCue) and view.currentCue == 0)
    var previousAtStart = KeyEvent{kind: .Pressed, key: .PageUp, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.editor, &previousAtStart) and view.currentCue == 0)
    var nextCue = KeyEvent{kind: .Pressed, key: .PageDown, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.editor, &nextCue) and view.currentCue == 1)
    Swag.assert(view.editor.selectedText() == "A second caption\non two lines.")
    var nextAtEnd = KeyEvent{kind: .Pressed, key: .PageDown, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.editor, &nextAtEnd) and view.currentCue == 1)
    var firstCue = KeyEvent{kind: .Pressed, key: .Home, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.editor, &firstCue) and
                view.currentCue == 0 and
                view.cueButton.text() == "1 / 2")
    var lastCue = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.editor, &lastCue) and
                view.currentCue == 1 and
                view.cueButton.text() == "2 / 2")

    let oldCount = String.from(view.cueButton.text())
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    let expectedPosition = Format.toString(Captions.texts().ui_CuePosition, 2, 2)
    Swag.assert(view.cueButton.text() == expectedPosition.toString(),
                Format.toString("subtitle position: actual '%', expected '%', previous '%'", view.cueButton.text(), expectedPosition, oldCount))
    Swag.assert(view.cueButton.toolTip == Captions.texts().ui_CueNavigationTip)
    Swag.assert(view.durationButton.toolTip == Captions.texts().ui_GoToTime)
    Swag.assert(view.editor.selectedText() == "A second caption\non two lines.")
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(view.cueButton.text() == oldCount.toString())
}

// The shipped palette renders the timestamped transcript as the primary document.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 520)

    with let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    {
        .dockStyle       = .Top
        .backgroundStyle = .InformationBar
        .padding         = {16, 4, 16, 4}
    }

    let fileName = subtitleViewerFixturePath()
    var result   = openTestViewer(Captions.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: infoBar)
    Swag.assert(result.view != null)
    infoBar.centerGroup    = result.info
    result.info!.dockStyle = .None
    result.view.dockStyle  = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.subtitle.document")
}

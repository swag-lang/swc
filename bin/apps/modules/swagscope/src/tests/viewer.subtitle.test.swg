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

// The cues read as a list: the keyboard moves through them, the readings say the current one, and
// the search finds and marks words inside them.
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
    Swag.assert(result.details == "2 cues")

    let view = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()
    Swag.assert(view.track!.cueCount() == 2 and view.currentCue == Swag.U64.Max)
    Swag.assert(view.identity().contains("SubRip") and view.timeButton.text() == "0:06")

    view.sheet.setFocus()
    host.keyPress(.PageDown, .Control)
    Swag.assert(view.currentCue == 0 and
                view.cuePosition() == "Cue 1 / 2" and
                view.timeButton.text() == "00:00:00")
    host.keyPress(.Down)
    Swag.assert(view.currentCue == 1 and view.timeButton.text() == "00:00:02")
    host.keyPress(.Down)
    Swag.assert(view.currentCue == 1)
    host.keyPress(.Home)
    Swag.assert(view.currentCue == 0)
    host.keyPress(.End, .Control)
    Swag.assert(view.currentCue == 1)

    // The words of a cue wrap at their own line breaks, and a match is marked on its words.
    Swag.assert(view.sheet.rows[1].lines.count == 2)
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "second", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1)
    view.currentCue = 0
    Swag.assert(result.revealMatch(matches[0], "second") and view.currentCue == 1)
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds(matches[0], &bounds) and not bounds.isEmpty())
    result.clearSearch()
    Swag.assert(not result.searchBounds(matches[0], &bounds))

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.cuePosition() == Format.toString(Captions.texts().ui_CuePosition, 2, 2).toString())
    Swag.assert(view.timeButton.toolTip == Captions.texts().ui_GoToTime)
}

// The reading list in the window, against `scope.subtitle`: the name and its mono line, the cues
// as rows of a number, a time range and the words, the current one on the selection ground.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/viewer.reading.srt")
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window = framedViewerWindow(&host, fileName.toString(), light)
        let view   = assume cast(*Captions.Panel, window.instances[window.activeChoiceIndex].view)
        Swag.assert(view.revealCue(1))
        window.applyLayout()
        host.settleAnimations(window, 4)

        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, light ? "viewer.subtitle.paper" : "viewer.subtitle.ink")
    }
}

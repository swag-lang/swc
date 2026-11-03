#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func subtitleViewerFixturePath()->String => scopeTestDataPath("viewer.srt")

// Go-to-time accepts its documented forms and rejects values that only look like timestamps.
#test
{
    var seconds: f64
    Swag.require(Captions.timeSeconds("90", &seconds) and seconds == 90)
    Swag.require(Captions.timeSeconds("1:30", &seconds) and seconds == 90)
    Swag.require(Captions.timeSeconds("1:02:03.5", &seconds) and seconds == 3_723.5)
    Swag.require(not Captions.timeSeconds("", &seconds))
    Swag.require(not Captions.timeSeconds("1:", &seconds))
    Swag.require(not Captions.timeSeconds("1:2:3:4", &seconds))
    Swag.require(not Captions.timeSeconds("-1", &seconds))
    Swag.require(not Captions.timeSeconds("NaN", &seconds))
    Swag.require(not Captions.timeSeconds("Infinity", &seconds))
    Swag.require(not Captions.timeSeconds("1e308:00", &seconds))
    Swag.require(not Captions.timeSeconds("1:60", &seconds))
    Swag.require(not Captions.timeSeconds("1:99", &seconds))
    Swag.require(not Captions.timeSeconds("1.5:30", &seconds))
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
    Swag.require(result.details == "2 cues")

    let view = assume cast(*Captions.Panel, result.view)
    view.dockStyle = .Center
    host.root.applyLayout()
    Swag.require(view.track!.cueCount() == 2 and view.currentCue == Swag.U64.Max)
    Swag.require(view.identity().contains("SubRip") and view.timeButton.text() == "0:06")

    view.sheet.setFocus()
    host.keyPress(.PageDown, .Control)
    Swag.require(view.currentCue == 0 and
                 view.cuePosition() == "Cue 1 / 2" and
                 view.timeButton.text() == "00:00:00")
    host.keyPress(.Down)
    Swag.require(view.currentCue == 1 and view.timeButton.text() == "00:00:02")
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

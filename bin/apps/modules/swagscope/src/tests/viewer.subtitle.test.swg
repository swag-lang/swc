#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func subtitleViewerFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/viewer.srt")
}

// Go-to-time accepts its documented forms and rejects values that only look like timestamps.
#test
{
    var seconds: f64
    Swag.assert(subtitleTimeSeconds("90", &seconds) and seconds == 90)
    Swag.assert(subtitleTimeSeconds("1:30", &seconds) and seconds == 90)
    Swag.assert(subtitleTimeSeconds("1:02:03.5", &seconds) and seconds == 3_723.5)
    Swag.assert(not subtitleTimeSeconds("", &seconds))
    Swag.assert(not subtitleTimeSeconds("1:", &seconds))
    Swag.assert(not subtitleTimeSeconds("1:2:3:4", &seconds))
    Swag.assert(not subtitleTimeSeconds("-1", &seconds))
    Swag.assert(not subtitleTimeSeconds("NaN", &seconds))
    Swag.assert(not subtitleTimeSeconds("Infinity", &seconds))
    Swag.assert(not subtitleTimeSeconds("1e308:00", &seconds))
    Swag.assert(not subtitleTimeSeconds("1:60", &seconds))
    Swag.assert(not subtitleTimeSeconds("1:99", &seconds))
    Swag.assert(not subtitleTimeSeconds("1.5:30", &seconds))
}

// The dedicated viewer presents a searchable timed transcript rather than raw subtitle syntax.
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    let fileName = subtitleViewerFixturePath()
    var result   = openTestViewer(subtitleViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.commands == null and result.info != null)
    Swag.assert(result.collectMatches != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)
    Swag.assert(result.details == "SubRip")

    let view = cast(*SubtitleViewer) result.view
    Swag.assert(view.track!.cueCount() == 2)
    Swag.assert(view.cueButton.text() == "2 cues" and (view.durationButton.text()).count)
    Swag.assert(view.transcript.indexOf("00:00:00.500") != Swag.U64.Max)
    Swag.assert(view.transcript.indexOf("A second caption\non two lines.") != Swag.U64.Max)

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, result.view, "second", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1)
    var revealed = result.revealMatch(result.view, matches[0], "second")
    Swag.assert(revealed)
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds(result.view, matches[0], &bounds) and not bounds.isEmpty())
    result.clearSearch(result.view)
    revealed = view.revealCue(1) and view.editor.selectedText() == "A second caption\non two lines."
    Swag.assert(revealed)

    let oldCount = String.from(view.cueButton.text())
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    let expectedCount = Format.toString(subtitleStrings().ui_Cues, 2)
    Swag.assert(view.cueButton.text() == expectedCount.toString() and view.cueButton.text() != oldCount.toString(),
                Format.toString("subtitle count: actual '%', expected '%', previous '%'", view.cueButton.text(), expectedCount, oldCount).toString())
    Swag.assert(view.cueButton.toolTip == subtitleStrings().ui_GoToCue)
    Swag.assert(view.durationButton.toolTip == subtitleStrings().ui_GoToTime)
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
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}
    let fileName = subtitleViewerFixturePath()
    var result   = openTestViewer(subtitleViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root, infoParent: infoBar)
    Swag.assert(result.view != null)
    infoBar.centerGroup    = result.info
    result.info!.dockStyle = .None
    result.view.dockStyle  = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.subtitle.document")
}

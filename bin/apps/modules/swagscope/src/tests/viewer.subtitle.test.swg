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
    Swag.assert(!subtitleTimeSeconds("", &seconds))
    Swag.assert(!subtitleTimeSeconds("1:", &seconds))
    Swag.assert(!subtitleTimeSeconds("1:2:3:4", &seconds))
    Swag.assert(!subtitleTimeSeconds("-1", &seconds))
    Swag.assert(!subtitleTimeSeconds("NaN", &seconds))
    Swag.assert(!subtitleTimeSeconds("Infinity", &seconds))
    Swag.assert(!subtitleTimeSeconds("1e308:00", &seconds))
    Swag.assert(!subtitleTimeSeconds("1:60", &seconds))
    Swag.assert(!subtitleTimeSeconds("1:99", &seconds))
    Swag.assert(!subtitleTimeSeconds("1.5:30", &seconds))
}

// The dedicated viewer presents a searchable timed transcript rather than raw subtitle syntax.
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer host.shutdown()

    let fileName = subtitleViewerFixturePath()
    var result   = openTestViewer(subtitleViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.commands == null and result.info != null)
    Swag.assert(result.collectMatches != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)
    Swag.assert(result.details == "SubRip")

    let view = cast(*SubtitleViewer) result.view!
    Swag.assert(view.track!.cueCount() == 2)
    Swag.assert(view.cueButton.text() == "2 cues" and (view.durationButton.text()).count)
    Swag.assert(view.transcript.indexOf("00:00:00.500") != Swag.U64.Max)
    Swag.assert(view.transcript.indexOf("A second caption\non two lines.") != Swag.U64.Max)

    var matches: Array'Viewer.SearchMatch
    result.collectMatches!(result.view!, "second", {}, &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1)
    Swag.assert(result.revealMatch!(result.view!, matches[0], "second"))
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)
    Swag.assert(view.revealCue(1) and view.editor.selectedText() == "A second caption\non two lines.")
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
    result.view!.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.subtitle.document")
}

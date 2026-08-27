#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func subtitleViewerFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/viewer.srt")
}

// The dedicated viewer presents a searchable timed transcript rather than raw subtitle syntax.
#test
{
    registerSubtitleStrings(&g_App)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer host.shutdown()

    let fileName = subtitleViewerFixturePath()
    let request  = ViewerRequest{&host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    createSubtitleViewer(&request, &result)
    @assert(result.view != null and result.commands == null)
    @assert(result.collectMatches != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)
    @assert(result.details.indexOf("SubRip") != Swag.U64.Max and result.details.indexOf("2 cues") != Swag.U64.Max)

    let view = cast(*SubtitleViewer) result.view!
    @assert(view.track!.cueCount() == 2)
    @assert(view.transcript.indexOf("00:00:00.500") != Swag.U64.Max)
    @assert(view.transcript.indexOf("A second caption\non two lines.") != Swag.U64.Max)

    var matches: Array'ViewerSearchMatch
    result.collectMatches!(result.view!, "second", {}, &matches)
    @assert(matches.count == 1 and matches[0].major == 1)
    @assert(result.revealMatch!(result.view!, matches[0], "second"))
    var bounds: Math.Rectangle
    @assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)
}

// The shipped palette renders the timestamped transcript as the primary document.
#test
{
    registerSubtitleStrings(&g_App)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let fileName = subtitleViewerFixturePath()
    let request  = ViewerRequest{&host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    createSubtitleViewer(&request, &result)
    @assert(result.view != null)
    result.view!.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.subtitle.document")
}

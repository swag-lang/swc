#global internal

using Core, Core.Errors, Pixel, Gui, Video

internal struct SubtitleViewerCue
{
    textOffset: u64
    textLength: u64
}

internal struct SubtitleViewer
{
    using wnd: Wnd

    #[Swag.Late]
    editor: *RichEditCtrl

    track:      #null *Subtitle.Track
    transcript: String
    cueText:    Array'SubtitleViewerCue
}

private func subtitleClockText(seconds: f64)->String
{
    let millis   = cast(u64) Math.max(Math.round(seconds * 1_000), 0.0)
    let hours    = millis / 3_600_000
    let minutes  = millis / 60_000 % 60
    let rest     = millis / 1_000 % 60
    let fraction = millis % 1_000
    return Format.toString("%{02}:%{02}:%{02}.%{03}", hours, minutes, rest, fraction)
}

private func subtitleFormatText(format: Subtitle.Format)->string
{
    switch format
    {
    case .SubRip:          return "SubRip"
    case .WebVtt:          return "WebVTT"
    case .SubStationAlpha: return "ASS/SSA"
    case .Lyric:           return "LRC"
    case .MicroDvd:        return "MicroDVD"
    case .MatroskaText:    return "Matroska text"
    }
}

private func subtitleCueCountText(count: u64)->String
{
    return count == 1 ? String.from(subtitleStrings().ui_OneCue) : Format.toString(subtitleStrings().ui_Cues, count)
}

private impl SubtitleViewer
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        if .track do
            Subtitle.Track.destroy(.track!)
        .track = null
    }

    mtd buildTranscript()
    {
        for index in .track!.cueCount()
        {
            if .transcript.length do
                .transcript += "\n\n"
            .transcript += subtitleClockText(.track!.cueStartTime(index))
            .transcript += "  →  "
            .transcript += subtitleClockText(.track!.cueEndTime(index))
            .transcript += "\n"
            let offset  = .transcript.length
            let content = videoSubtitleText(.track!.cueTextData(index), .track!.cueTextLength(index))
            .transcript += content
            .cueText.add({offset, @countof(content)})
        }
    }

    mtd collectMatches(text: string, options: ViewerSearchOptions, result: *Array'ViewerSearchMatch)
    {
        for index in .track!.cueCount()
        {
            let content = videoSubtitleText(.track!.cueTextData(index), .track!.cueTextLength(index))
            collectViewerTextMatches(content, text, options, index, 0, 0, result)
        }
    }

    mtd revealMatch(match: ViewerSearchMatch)->bool
    {
        if match.major >= .cueText.count do
            return false
        let cue = .cueText[match.major]
        highlightRichEditMatch(.editor, .transcript.toString(), cue.textOffset + match.offset, match.length)
        return true
    }

    func create(parent: *Wnd, fileName: string)->*SubtitleViewer fail
    {
        registerSubtitleStrings(parent.app())
        let result = Wnd.create'SubtitleViewer(parent, "scope.subtitle")
        result.backgroundStyle = .View
        result.track           = try Subtitle.Track.loadOwned(fileName)
        result.buildTranscript()

        result.editor             = RichEditCtrl.create(result)
        result.editor.dockStyle   = .Center
        result.editor.marginLeft  = 20
        result.editor.marginRight = 20
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.editor.setFlags(.ReadOnly | .WordWrap)
        result.editor.setText(result.transcript.toString())
        result.applyLayout()
        result.setInitialFocus(result.editor)
        return result
    }
}

private func loadSubtitleViewer(parent: *Wnd, fileName: string)->#null *SubtitleViewer fail => try SubtitleViewer.create(parent, fileName)

// Creates the integrated timed-subtitle document view.
func createSubtitleViewer(host: FileViewer.Host)
{
    let view = catch loadSubtitleViewer(host.contentParent(), host.fileName()) as createError
    if createError != null
    {
        host.reject(Errors.message(createError))
        return
    }

    let track    = view!.track!
    let cueCount = track.cueCount()
    let duration = track.durationInSeconds()
    host.attachView(view!)
    host.setDetails(Format.toString(subtitleStrings().ui_Details, subtitleFormatText(track.sourceFormat()), subtitleCueCountText(cueCount).toString(), mediaDurationText(duration)).toString())
    host.setSearch({
        collectMatches: func(wnd, text, options, matches) { (cast(*SubtitleViewer) wnd).collectMatches(text, options, matches) },
        revealMatch: func(wnd, match, text)->bool
    {
        discard text
        return (cast(*SubtitleViewer) wnd).revealMatch(match)
    },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return richEditSearchBounds((cast(*SubtitleViewer) wnd).editor, bounds)
    },
        clear: func(wnd) { clearRichEditSearch((cast(*SubtitleViewer) wnd).editor) }})
}

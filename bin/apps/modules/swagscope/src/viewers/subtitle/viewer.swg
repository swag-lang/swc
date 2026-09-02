#global internal

using Core, Core.Errors, Pixel, Gui, Video

// Describes the subtitle viewer to the host.
func subtitleViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "subtitle"
    result.staticName   = "Subtitles"
    result.attach       = &registerSubtitleStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Subtitle
    result.create       = &createSubtitleViewer
    result.smokeFixture = "viewer.srt"
    result.addSelectors(".srt;.vtt;.ass;.ssa;.lrc;.sub")
    return result
}

internal struct SubtitleViewerCue
{
    textOffset: u64
    textLength: u64
}

internal struct SubtitleViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        editor:         *RichEditCtrl
        cueButton:      *IconButton
        durationButton: *IconButton
    }

    track:      #null *Subtitle.Track
    transcript: String
    cueText:    Array'SubtitleViewerCue
    duration:   f64
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
            .cueText.add({offset, content.count})
        }
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for index in .track!.cueCount()
        {
            let content = videoSubtitleText(.track!.cueTextData(index), .track!.cueTextLength(index))
            Viewer.collectTextMatches(content, text, options, index, 0, 0, result)
        }
    }

    mtd revealMatch(match: Viewer.SearchMatch)->bool
    {
        if match.major >= .cueText.count do
            return false
        let cue = .cueText[match.major]
        Viewer.highlightRichEditMatch(.editor, .transcript.toString(), cue.textOffset + match.offset, match.length)
        return true
    }

    mtd revealCue(index: u64)->bool
    {
        if index >= .cueText.count do
            return false
        let cue = .cueText[index]
        Viewer.highlightRichEditMatch(.editor, .transcript.toString(), cue.textOffset, cue.textLength)
        .editor.setFocus()
        return true
    }

    mtd promptGoToCue()
    {
        if .cueText.isEmpty() do
            return
        var options: EditDlgOptions
        let message = Format.toString(subtitleStrings().ui_CueRange, .cueText.count)
        options.title   = subtitleStrings().ui_GoToCue
        options.message = message.toString()
        options.text    = "1"
        let dialog = EditDlg.createSingleLine(.surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let cue = catch StrConv.toU64(dialog.text().toString()) as parseError
        if parseError == null and cue and cue <= .cueText.count do
            discard .revealCue(cue - 1)
    }

    mtd promptGoToTime()
    {
        if .cueText.isEmpty() do
            return
        var options: EditDlgOptions
        options.title   = subtitleStrings().ui_GoToTime
        options.message = subtitleStrings().ui_TimeRange
        options.text    = "00:00:00.000"
        let dialog = EditDlg.createSingleLine(.surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var seconds: f64
        if !subtitleTimeSeconds(dialog.text().toString(), &seconds) do
            return
        for index in .track!.cueCount() where .track!.cueEndTime(index) >= seconds
        {
            discard .revealCue(index)
            return
        }

        discard .revealCue(.cueText.count - 1)
    }

    func create(host: Viewer.Host)->*SubtitleViewer fail
    {
        let result = Wnd.create'SubtitleViewer(host.contentParent(), "scope.subtitle")
        result.backgroundStyle = .View
        result.track           = try Subtitle.Track.loadOwned(host.fileName())
        result.duration        = result.track!.durationInSeconds()
        result.buildTranscript()

        let info = host.createInfoGroup(220)
        with result.durationButton = IconButton.create(info, {}, {0, 0, 104, 32}, "scope.subtitle.time", .CenterContent)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .setText(Viewer.durationText(result.duration))
            .setForm(.Rectangle)
            .toolTip    = subtitleStrings().ui_GoToTime
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.promptGoToTime()
            }
        }

        with result.cueButton = IconButton.create(info, {}, {0, 0, 108, 32}, "scope.subtitle.cue", .CenterContent)
        {
            .dockStyle = .Right
            .setText(subtitleCueCountText(result.track!.cueCount()).toString())
            .setForm(.Rectangle)
            .toolTip    = subtitleStrings().ui_GoToCue
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.promptGoToCue()
            }
        }

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

// Parses the three forms advertised by the go-to-time dialog.  Once a colon is present, every
// field after the first is a base-60 component rather than an unrestricted decimal number.
func subtitleTimeSeconds(text: string, result: *f64)->bool
{
    let parts = Tokenize.split(text, ':'u8, removeEmpty: false)
    if parts.isEmpty() or parts.count > 3 do
        return false

    var seconds = 0'f64
    for part, index in parts
    {
        if !part.count do
            return false
        let value = catch StrConv.toF64(part) as parseError
        if parseError != null or value < 0 or !Math.isFinite(value) do
            return false
        if index and value >= 60 do
            return false
        if index + 1 < parts.count and value != Math.floor(value) do
            return false
        seconds = seconds * 60 + value
        if !Math.isFinite(seconds) do
            return false
    }

    result[] = seconds
    return true
}

private func loadSubtitleViewer(host: Viewer.Host)->#null *SubtitleViewer fail => try SubtitleViewer.create(host)

// Creates the integrated timed-subtitle document view.
func createSubtitleViewer(host: Viewer.Host)
{
    let view = catch loadSubtitleViewer(host) as createError
    if createError != null
    {
        host.reject(Errors.message(createError))
        return
    }

    let track = view!.track!
    host.attachView(view!)
    host.setDetails(subtitleFormatText(track.sourceFormat()))
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
        return Viewer.richEditMatchBounds((cast(*SubtitleViewer) wnd).editor, bounds)
    },
        clear: func(wnd) { Viewer.clearRichEditMatch((cast(*SubtitleViewer) wnd).editor) }})
}

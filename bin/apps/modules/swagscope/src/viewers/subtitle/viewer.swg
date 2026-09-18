#global internal

using Core, Core.Errors, Pixel, Gui, Video

// Describes the subtitle viewer to the host.
func subtitleViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "subtitle"
        .staticName   = "Subtitles"
        .attach       = &registerSubtitleStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Subtitle
        .create       = &createSubtitleViewer
        .textual      = true
        .smokeFixture = "viewer.srt"
        .addSelectors(".srt;.vtt;.ass;.ssa;.lrc;.sub")
    }

    return result
}

// Locates the text of one cue inside the transcript.
struct SubtitleViewerCue
{
    textOffset: u64
    textLength: u64
}

// Presents a timed subtitle file as a searchable transcript of its cues.
struct SubtitleViewer
{
    using wnd: Wnd

    late
    {
        editor:         *RichEditCtrl
        cueButton:      *IconButton
        durationButton: *IconButton
    }

    track:      *Subtitle.Track?
    transcript: String
    cueText:    Array'SubtitleViewerCue
    duration:   f64
}

// Formats a cue time as HH:MM:SS.mmm, a form the go-to-time dialog also accepts.
private func subtitleClockText(seconds: f64)->String
{
    let millis   = cast(u64) Math.max(Math.round(seconds * 1_000), 0.0)
    let hours    = millis / 3_600_000
    let minutes  = millis / 60_000 % 60
    let rest     = millis / 1_000 % 60
    let fraction = millis % 1_000
    return Format.toString("%{02}:%{02}:%{02}.%{03}", hours, minutes, rest, fraction)
}

// Returns the established name of a subtitle syntax.
private func subtitleFormatText(format: Subtitle.Format)->string
{
    switch #complete format
    {
    case .SubRip:          return "SubRip"
    case .WebVtt:          return "WebVTT"
    case .SubStationAlpha: return "ASS/SSA"
    case .Lyric:           return "LRC"
    case .MicroDvd:        return "MicroDVD"
    case .MatroskaText:    return "Matroska text"
    }
}

// Returns the cue count with the noun that count calls for.
private func subtitleCueCountText(count: u64)->String => count == 1 ? String.from(subtitleStrings().ui_OneCue) : Format.toString(subtitleStrings().ui_Cues, count)

impl IWnd for SubtitleViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        if .track do
            Subtitle.Track.destroy(.track)
        .track = null
    }
}

private impl SubtitleViewer
{
    mtd retranslate()
    {
        .cueButton.setText(subtitleCueCountText(.track!.cueCount()).toString())
        .cueButton.toolTip      = subtitleStrings().ui_GoToCue
        .durationButton.toolTip = subtitleStrings().ui_GoToTime
    }

    mtd buildTranscript()
    {
        for index in .track!.cueCount()
        {
            if not .transcript.isEmpty() do
                .transcript += "\n\n"
            .transcript += subtitleClockText(.track.cueStartTime(index))
            .transcript += "  →  "
            .transcript += subtitleClockText(.track.cueEndTime(index))
            .transcript += "\n"
            let offset  = .transcript.length
            let content = .track.cueContent(index)
            .transcript += content
            .cueText.add({offset, content.count})
        }
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for index in .track!.cueCount() do
            Viewer.collectTextMatches(.track.cueContent(index), text, options, index, 0, 0, result)
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
        let message = Format.toString(subtitleStrings().ui_CueRange, .cueText.count)
        let dialog  = EditDlg.createSingleLine(.surface!, {title: subtitleStrings().ui_GoToCue, message: message.toString(), text: "1"})
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
        let dialog = EditDlg.createSingleLine(.surface!, {title: subtitleStrings().ui_GoToTime, message: subtitleStrings().ui_TimeRange, text: "00:00:00.000"})
        if dialog.doModal() != Dialog.BtnOk do
            return

        var seconds: f64
        if not subtitleTimeSeconds(dialog.text().toString(), &seconds) do
            return
        for index in .track!.cueCount() where .track.cueEndTime(index) >= seconds
        {
            discard .revealCue(index)
            return
        }

        discard .revealCue(.cueText.count - 1)
    }

    func create(host: Viewer.Host)->*SubtitleViewer fail
    {
        with let result = Wnd.create'SubtitleViewer(host.contentParent(), "scope.subtitle")
        {
            .backgroundStyle = .View
            .track           = try Subtitle.Track.loadOwned(host.fileName())
            .duration        = .track!.durationInSeconds()
            .buildTranscript()
        }

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

        with result.editor = RichEditCtrl.create(result)
        {
            .dockStyle   = .Center
            .marginLeft  = 20
            .marginRight = 20
            .style.setFont(result.theme().createDefaultFontFs(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setFlags(.ReadOnly | .WordWrap)
            .setText(result.transcript.toString())
        }

        result.applyLayout()
        result.setInitialFocus(result.editor)
        return result
    }
}

// Reports whether `text` is a time in one of the three forms the go-to-time dialog advertises, and stores its seconds in `result`.
//
// Once a colon is present, every field after the first is a base-60 component rather than an
// unrestricted decimal number. `result` is left untouched when `text` is rejected.
func subtitleTimeSeconds(text: string, result: *f64)->bool
{
    let parts = Tokenize.split(text, ':'u8, removeEmpty: false)
    if parts.isEmpty() or parts.count > 3 do
        return false

    var seconds = 0'f64
    for part, index in parts
    {
        if not part.count do
            return false
        let value = catch StrConv.toF64(part) as parseError
        if parseError != null or value < 0 or not Math.isFinite(value) do
            return false
        if index and value >= 60 do
            return false
        if index + 1 < parts.count and value != Math.floor(value) do
            return false
        seconds = seconds * 60 + value
        if not Math.isFinite(seconds) do
            return false
    }

    result[] = seconds
    return true
}

// Returns the created viewer as a nullable pointer, which gives `catch` a fallback value.
private func loadSubtitleViewer(host: Viewer.Host)->*SubtitleViewer? fail => try SubtitleViewer.create(host)

// Creates the integrated timed-subtitle document view and connects it to the host.
func createSubtitleViewer(host: Viewer.Host)
{
    let view = catch loadSubtitleViewer(host) as createError
    if createError != null
    {
        host.reject(Errors.message(createError))
        return
    }

    host.attachView(view!)
    host.setDetails(subtitleFormatText(view.track!.sourceFormat()))
    host.setSearch({
        collectMatches: func(wnd, text, options, progress, matches)->bool
    {
        discard progress
        (cast #assume (*SubtitleViewer) wnd).collectMatches(text, options, matches)
        return true
    },
        revealMatch: func(wnd, match, text)->bool
    {
        discard text
        return (cast #assume (*SubtitleViewer) wnd).revealMatch(match)
    },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return Viewer.richEditMatchBounds((cast #assume (*SubtitleViewer) wnd).editor, bounds)
    },
        clear: func(wnd) { Viewer.clearRichEditMatch((cast #assume (*SubtitleViewer) wnd).editor) }})
}

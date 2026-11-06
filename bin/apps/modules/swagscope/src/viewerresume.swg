#global internal

using Core, Gui

// Where the reader left a file of the history, so the home can offer to take it up again.
//
// It keeps the reading state a reload keeps, with what the home writes about it: how much of the
// file was read or played, and its length in the units of the file. A file read to its end, or
// left at its very start, has nothing to resume and keeps no point.
struct ViewerResumePoint
{
    file:     String
    reading:  ViewerReadingState
    progress: f32     // Share of the file already read or played, from 0 to 1.
    seconds:  f64     // Position of a recording; zero for anything else.
    length:   f64     // Seconds of a recording; zero for anything else.
    page:     u64     // Zero-based page of a paged document.
    pages:    u64     // Pages of a paged document; zero for anything else.
}

impl ViewerResumePoint
{
    // Below this share the reader barely started; above it the file was read through.
    const StartedShare  = 0.01'f32
    const FinishedShare = 0.97'f32

    // Measures how far into its file `session` stands, and reports whether there is something to
    // take up again.
    mtd measure(session: *ViewerSession)->bool
    {
        .progress, .seconds, .length = 0
        .page, .pages = 0
        switch session.view
        {
        case Viewers.Film.Panel as view:
            .length  = view.video.durationInSeconds()
            .seconds = Math.clamp(view.currentSeconds(), 0, .length)
            if .length > 0 do
                .progress = cast(f32, .seconds / .length)

        case Viewers.Sound.Panel as view:
            .length  = cast(f64, view.duration)
            .seconds = view.voice ? view.voice.playbackPositionSeconds() : cast(f64, view.elapsed)
            .seconds = Math.clamp(.seconds, 0, .length)
            if .length > 0 do
                .progress = cast(f32, .seconds / .length)

        case Viewers.PdfDocument.Panel as view:
            .pages = view.pdfView.pageCount()
            .page  = view.pdfView.pageIndex
            if .pages > 1 do
                .progress = cast(f32, .page) / cast(f32, .pages - 1)

        default:
            .progress = ViewerResumePoint.scrolledShare(unwrap session.view)
        }

        .progress = Math.clamp(.progress, 0, 1)
        return .progress >= StartedShare and .progress < FinishedShare
    }

    // Returns how far the first scrolled viewport of `wnd` is down its content, from 0 to 1.
    func scrolledShare(wnd: *Wnd)->f32
    {
        if wnd is ScrollWnd as scroll
        {
            let room = scroll.scrollSize.y - scroll.view.clientRect().height
            if room <= 1 do
                return 0
            return Math.clamp(scroll.scrollPosition().y / room, 0, 1)
        }

        for child in wnd.children
        {
            let share = ViewerResumePoint.scrolledShare(child[])
            if share > 0 do
                return share
        }

        return 0
    }

    // Writes where the file was left, as the home names it: the time in a recording, the page of
    // a document, or the share of anything else read.
    mtd const positionText()->String
    {
        let texts = appStrings()
        if .length > 0 do
            return Format.toString(texts.home_ResumeAt, Viewer.timeText(.seconds))
        if .pages > 0 do
            return Format.toString(texts.home_ResumePage, .page + 1, .pages)
        return Format.toString(texts.home_ResumeShare, cast(u32, Math.round(.progress * 100)))
    }

    // Writes the position the way a tile's facts line carries it, in mono and short.
    mtd const shortText()->String
    {
        if .length > 0 do
            return Format.toString("% / %", Viewer.timeText(.seconds), Viewer.durationText(.length))
        if .pages > 0 do
            return Format.toString(appStrings().home_PageShort, .page + 1, .pages)
        return Format.toString("% %%", cast(u32, Math.round(.progress * 100)))
    }
}

impl ViewerWindow
{
    // How many resume points are kept: one for each file of the history at most.
    const ResumeCount = RecentCount

    // Records where the reader stands in the open file, or forgets the point when the file was read
    // through. Only a file of the history keeps one: the home is the only place that offers it.
    mtd captureResume()
    {
        if .thumbnailMode or .currentFile.isEmpty() or .activeChoiceIndex >= .instances.count do
            return
        let session = &.instances[.activeChoiceIndex]
        if not session.view or not .recent.contains(.currentFile) do
            return

        var point: ViewerResumePoint
        let keep = point.measure(session)
        .forgetResume(.currentFile)
        if not keep do
            return

        point.file = .currentFile
        point.reading.capture(session, .choices[.activeChoiceIndex].key, "")
        point.reading.restoring = false
        .resumePoints.insertAt(0, #move point)
        while .resumePoints.count > ResumeCount do
            .resumePoints.removeBack()
    }

    // Returns where `fileName` was left, or null when there is nothing to take up again.
    mtd resumePoint(fileName: string)->const *ViewerResumePoint?
    {
        for &point in .resumePoints where Path.equals(point.file, fileName) do
            return point
        return null
    }

    // Drops the point of `fileName`, if it has one.
    mtd forgetResume(fileName: string)
    {
        for point, index in .resumePoints where Path.equals(point.file, fileName)
        {
            .resumePoints.removeAtOrdered(index)
            return
        }
    }

    // Keeps the points of the files still in the history, and only those.
    mtd pruneResume()
    {
        for i in reversed(.resumePoints.count) where not .recent.contains(.resumePoints[i].file) do
            .resumePoints.removeAtOrdered(i)
        while .resumePoints.count > ResumeCount do
            .resumePoints.removeBack()
    }

    // Opens `fileName` where the reader left it, or from its start when it has no point.
    //
    // A file of the history that went missing takes the ordinary path, which offers to forget it.
    mtd resumeFile(fileName: string, fromHistory = true)
    {
        let point = .resumePoint(fileName)
        if not point or not File.exists(fileName)
        {
            .queueFile(fileName, offerForgetMissing: fromHistory)
            return
        }

        .readingState = point.reading
        .queueFile(fileName, preserveReading: true, offerForgetMissing: fromHistory)
    }

    // Opens `fileName` from its start, forgetting where it was left.
    mtd restartFile(fileName: string)
    {
        .forgetResume(fileName)
        .queueFile(fileName, offerForgetMissing: true)
    }
}

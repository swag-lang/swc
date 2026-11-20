#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Pixel, Video

// Own a writable copy of the two-hour SCC/MP4 pair and open it through the native library.
struct LongVideoWorkspace
{
    using journey: CaptureJourney
    document:      String
    late capture:  *Capture
    late timeline: *TimelineBar
}

impl LongVideoWorkspace
{
    mtd setup(fixture: String)
    {
        .journey.setup()
        .document = Path.combine(.root, "twohours.scc")
        expect Capture.duplicateFiles(.document, fixture)
        g_Library.fill()
        .openLibrary(1)
        let main = .main
        main.libWnd.view.openItem(main.libWnd.view.items[0])
        .waitFor("two-hour video opened", func|main|()->bool
        {
            let capture = main.editWnd.getCapture()
            return not main.libraryMode and
                   capture and
                   capture.media == .Video and
                   not capture.mediaMissing and
                   main.timeline != null
        })
        .capture  = unwrap main.editWnd.getCapture()
        .timeline = unwrap main.timeline
        Swag.require(.capture.timeline.frameCount == 216_000 and .capture.timeline.duration == 7_200_000_000)
        .main.sendCommandEvent(ActionToolMode.Selection)
    }

    mtd showFrame(index: u64)
    {
        expect .capture.showFrame(index)
        .timeline.revealTime(.capture.playheadTime())
        .timeline.invalidate()
        .app.runFrame()
    }
}

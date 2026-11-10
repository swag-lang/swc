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
    openUs:        u64
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
        let main    = .main
        let started = Time.monotonicMicroseconds()
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
        .openUs   = Time.monotonicMicroseconds() - started
        .capture  = unwrap main.editWnd.getCapture()
        .timeline = unwrap main.timeline
        Swag.require(.capture.timeline.frameCount == 216_000 and .capture.timeline.duration == 7_200_000_000)
        .main.sendCommandEvent(ActionToolMode.Selection)
        Console.println("Two-hour workspace: open_us=", .openUs)
    }

    mtd showFrame(index: u64)->u64
    {
        let started = Time.monotonicMicroseconds()
        expect .capture.showFrame(index)
        .timeline.revealTime(.capture.playheadTime())
        .timeline.invalidate()
        .app.runFrame()
        return Time.monotonicMicroseconds() - started
    }

    mtd saveScreenshot(name: string)
    {
        #static if #os == Swag.TargetOs.Windows
        {
            let surface = .surface
            .waitFor("two-hour native presentation", func|surface|()->bool
                     => expect Gui.Testing.verifyNativePresentation(surface))
        }

        .app.renderer.setCurrentContext(.surface.renderingContext())
        let target  = &.surface.rt
        let picture = .app.renderer.readRenderTarget(target, 0, 0, target.colorBuffer.width, target.colorBuffer.height)
        expect picture.save(Path.combine(Env.sandboxRoot(), name))
    }
}

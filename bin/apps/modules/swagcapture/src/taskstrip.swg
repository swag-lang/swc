using Core, Gui

// The repeated capture and output gestures of the window, set in its top strip.
//
// Capture and the library stand after the command menu, where work comes in; the output of the
// picture stands before the window buttons, where it goes out, its copy as the one primary
// action of the editor. The title keeps the room between the two. Without a strip, as on a
// surface that has none, the same two groups stand in a band of the same height at the top of
// the window, and the work starts under it ([[TaskStrip.bandHeight]]).
struct TaskStrip
{
    using wnd: Wnd

    late
    {
        leading:       *StackLayoutCtrl     // Capture, its modes, and the library.
        trailing:      *StackLayoutCtrl     // Save and copy the picture, while the editor shows one.
        captureChoice: *IconButton          // The chevron that opens the capture modes.
        copyButton:    *PushButton          // Copy the finished picture: the primary action.
    }
}

impl IWnd for TaskStrip
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return

        let metrics = .themeMetrics()
        let strip   = parent.stripInset()
        let width   = parent.clientRect().width
        let height  = strip > 0 ? strip : metrics.wnd_StripHeight
        .setPosition(Math.Rectangle{0, 0, width, height})

        // In the strip, the groups take the room the window leaves between its leading actions and
        // its trailing ones; in a band of their own, the edges of the window less the floating inset.
        var start = metrics.floating_Inset
        var end   = width - metrics.floating_Inset
        let frame = .surfaceFrame()
        if strip > 0 and frame
        {
            let room = frame.captionRoomRect()
            let dx   = frame.surfaceRect().x - .surfaceRect().x
            start = room.x + dx
            end   = room.right() + dx
        }

        let leadingSize  = .leading.itf.measureContent({})
        let trailingSize = .trailing.isLocallyVisible() ? .trailing.itf.measureContent({}) : Math.Point{}
        .leading.setPosition(Math.Rectangle{start, Math.round((height - leadingSize.y) * 0.5), leadingSize.x, leadingSize.y})
        .trailing.setPosition(Math.Rectangle{end - trailingSize.x, Math.round((height - trailingSize.y) * 0.5), trailingSize.x, trailingSize.y})
        .leading.applyLayout()
        .trailing.applyLayout()

        // The title stays centred between the groups, with the air of a title margin on each side.
        if strip > 0 and frame
        {
            let air = metrics.wnd_CaptionMarginTitle
            frame.reserveCaptionRoom(leadingSize.x + air, trailingSize.x > 0 ? trailingSize.x + air : 0)
        }
    }
}

impl TaskStrip
{
    // Builds the two groups in `main`, posting their commands to it.
    func create(main: *MainWnd)->*TaskStrip
    {
        with let result = Wnd.create'TaskStrip(main)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Application
        }

        with result.leading = StackLayoutCtrl.create(result, .Left)
        {
            .backgroundStyle = .Transparent
            .spacing         = main.themeMetrics().wnd_CaptionActionGap
        }

        with let captureButton = IconButton.createQuiet(result.leading, ActionCapture.Repeat, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
        }

        // The chevron belongs to the capture control: it stands against its words, not one gap away.
        with result.captureChoice = IconButton.createQuiet(result.leading, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
            .margin.x    = -main.themeMetrics().wnd_CaptionActionGap
            .setIcon(.theme().icon(.ChevronDown))
            .sigPressed += func|main|(button) { main.showCaptureMenu(button) }
        }

        with let libraryButton = IconButton.createQuiet(result.leading, ActionGlobal.ShowLibrary, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
        }

        with result.trailing = StackLayoutCtrl.create(result, .Left)
        {
            .backgroundStyle = .Transparent
            .spacing         = main.themeMetrics().wnd_CaptionActionGap
        }

        with let saveButton = IconButton.createQuiet(result.trailing, ActionFile.SaveAsImage, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
        }

        with result.copyButton = PushButton.create(result.trailing, "", id: ActionCopyPaste.CopyAsImage, form: .Strong)
        {
            .owner       = main
            .focusPolicy = .None
            .wndFlags.remove(.ActivatesOnKey)
        }

        return result
    }

    // Shows the output of the picture, or leaves it out where there is no picture to send, as in
    // the library; the title takes the room back.
    mtd showOutput(shown: bool)
    {
        if .trailing.isLocallyVisible() == shown do
            return
        .trailing.show(shown)
        .itf.onLayout()
        .invalidate()
    }

    // Returns the height of the band the groups take at the top of `wnd` when its surface has no
    // strip to hold them, and zero when they stand in the strip.
    func bandHeight(wnd: *Wnd)->f32 => wnd.stripInset() > 0 ? 0 : wnd.themeMetrics().wnd_StripHeight

    private mtd surfaceFrame()->*SurfaceWnd?
    {
        let surface = .surface
        if not surface do
            return null
        return assume cast(*SurfaceWnd, surface.wnd)
    }
}

using Core, Gui

// The room the title keeps between the groups of the strip: the start of the window's name,
// as the minimum width leaves it with the shortest capture name.
const TaskStripTitleRoom = 48.0

// The repeated capture and output gestures of the window, set in its top strip.
//
// Image, video and the library stand after the command menu, where work comes in; the output of the
// picture stands before the window buttons, where it goes out, its copy as the one primary
// action of the editor. The title keeps the room between the two. Without a strip, as on a
// surface that has none, the same two groups stand in a band of the same height at the top of
// the window, and the work starts under it ([[TaskStrip.bandHeight]]).
struct TaskStrip
{
    using wnd: Wnd

    late main: *MainWnd

    late
    {
        leading:         *StackLayoutCtrl     // Capture, its modes, and the library.
        trailing:        *StackLayoutCtrl     // Save and copy the picture, while the editor shows one.
        captureChoice:   *IconButton          // The chevron that opens the capture modes.
        videoButton:     *IconButton          // Opens video area selection without the long command label.
        libraryButton:   *IconButton          // Swaps between the editor and the library.
        saveButton:      *IconButton          // Saves the picture under a chosen name.
        shortcutPanel:   *FloatingPanel       // Unavailable capture keys, anchored below Capture.
        shortcutWarning: *IconButton          // Opens the unavailable key names.
        frozenPanel:     *FloatingPanel       // Selection mode, anchored beside the inspector.
        frozenButton:    *IconButton          // Releases the selection mode.
        copyButton:      *PushButton          // Copy the finished picture: the primary action.
    }
}

impl IWnd for TaskStrip
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged:
            .videoButton.setQuietText(appStrings().ui_MediaVideo)
            .videoButton.toolTip = appStrings().act_RecordVideo
            .frozenButton.setQuietText(appStrings().ui_Frozen)
            .shortcutWarning.setQuietText(appStrings().ui_ShortcutsUnavailable)
            .itf.onLayout()

        case .ThemeChanged:
            .frozenButton.setIconColor(.themeColors().arc)
            .shortcutWarning.setIconColor(.themeColors().critical)
        }
    }

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
        var title = false
        var center: f32
        let frame = .surfaceFrame()
        if strip > 0 and frame
        {
            let room = frame.captionRoomRect()
            let dx   = frame.surfaceRect().x - .surfaceRect().x
            start  = room.x + dx
            end    = room.right() + dx
            center = frame.clientRect().horzCenter() + dx
            title  = true
        }

        // The words of both groups and a title share the strip while they fit; the title is
        // centred on the window, so each group leaves half of its room on its side. Past that,
        // Video and the library keep their glyphs and give up their words, which their tips still
        // say, then the save control does; Capture always names what it takes again, and Copy is
        // the primary action.
        var leadingSize, trailingSize: Math.Point
        for words in [2'u32, 1, 0]
        {
            .showWords(words)
            leadingSize  = .leading.itf.measureContent({})
            trailingSize = .trailing.isLocallyVisible() ? .trailing.itf.measureContent({}) : Math.Point{}

            var fits = leadingSize.x + trailingSize.x + metrics.wnd_CaptionActionGap <= end - start
            if title
            {
                let half = metrics.wnd_CaptionMarginTitle + TaskStripTitleRoom * 0.5
                fits = start + leadingSize.x + half <= center and end - trailingSize.x - half >= center
            }

            if fits do
                break
        }

        .leading.setPosition(Math.Rectangle{start, Math.round((height - leadingSize.y) * 0.5), leadingSize.x, leadingSize.y})
        .trailing.setPosition(Math.Rectangle{end - trailingSize.x, Math.round((height - trailingSize.y) * 0.5), trailingSize.x, trailingSize.y})
        .leading.applyLayout()
        .trailing.applyLayout()

        // Persistent states sit in small floating surfaces beside the work they affect. They
        // never compete with the caption, Capture, or the output commands for strip width.
        let pad = metrics.miniBar_Padding
        let y   = height + metrics.floating_Inset
        if .shortcutPanel.isLocallyVisible()
        {
            let button = .shortcutWarning
            .shortcutPanel.setPosition({.leading.position.x, y, button.position.width + 2 * pad, metrics.quiet_Height + 2 * pad})
            button.setPosition({pad, pad, button.position.width, metrics.quiet_Height})
        }

        if .frozenPanel.isLocallyVisible()
        {
            let button = .frozenButton
            let width  = button.position.width + 2 * pad
            var right  = .main.clientRect().right() - metrics.floating_Inset
            if .main.inspector.isLocallyVisible() and not .main.inspector.folded do
                right = .main.inspector.surfaceRect().x - .main.surfaceRect().x - metrics.floating_Inset
            .frozenPanel.setPosition({right - width, y, width, metrics.quiet_Height + 2 * pad})
            button.setPosition({pad, pad, button.position.width, metrics.quiet_Height})
        }

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
    // Writes the words of the secondary controls: all of them at 2, the save control alone at 1,
    // none at 0. A control without its words says them in its tip.
    mtd showWords(level: u32)
    {
        func show(button: *IconButton, shown: bool, tip: string)
        {
            if button.flags.has(.IconOnly) != shown do
                return
            if shown do
                button.updateFlags(remove: .IconOnly)
            else do
                button.updateFlags(add: .IconOnly)
            button.toolTip = tip

            // A control sized to its words is sized again; one that follows its command is
            // measured from its content by the group.
            if button.preferredSize.x > 0 do
                button.resize(Math.ceil(button.itf.measureContent({}).x), button.position.height)
        }

        show(.videoButton, level >= 2, appStrings().act_RecordVideo)
        show(.libraryButton, level >= 2, level >= 2 ? "" : appStrings().act_Library)
        show(.saveButton, level >= 1, level >= 1 ? "" : .saveButton.name.text)
    }

    // Builds the two groups in `main`, posting their commands to it.
    func create(main: *MainWnd)->*TaskStrip
    {
        with let result = Wnd.create'TaskStrip(main)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Application
            .main            = main
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

        with result.videoButton = IconButton.createQuiet(result.leading, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
            .toolTip     = appStrings().act_RecordVideo
            .setIcon(kindIcon(main, .theme(), .Video))
            .setQuietText(appStrings().ui_MediaVideo)
            .sigPressed += func|main|(_) { main.postCommandEvent(ActionCapture.RecordVideo) }
        }

        with result.libraryButton = IconButton.createQuiet(result.leading, ActionGlobal.ShowLibrary, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
        }

        with result.trailing = StackLayoutCtrl.create(result, .Left)
        {
            .backgroundStyle = .Transparent
            .spacing         = main.themeMetrics().wnd_CaptionActionGap
        }

        with result.saveButton = IconButton.createQuiet(result.trailing, ActionFile.SaveAsImage, menu: false)
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

        with result.shortcutPanel = FloatingPanel.create(main)
        {
            .dockStyle = .Float
            .hide()
        }

        with result.shortcutWarning = IconButton.createQuiet(result.shortcutPanel, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
            .setIcon(.theme().icon(.Warning))
            .setIconColor(.themeColors().critical)
            .setArrowPosition(.RightDownward)
            .setQuietText(appStrings().ui_ShortcutsUnavailable)
            .sigPressed += func|main|(button) { main.showUnavailableShortcuts(button) }
        }

        with result.frozenPanel = FloatingPanel.create(main)
        {
            .dockStyle = .Float
            .hide()
        }

        with result.frozenButton = IconButton.createQuiet(result.frozenPanel, menu: false)
        {
            .owner       = main
            .focusPolicy = .None
            .setIcon(.theme().icon(.Lock))
            .setIconColor(.themeColors().arc)
            .setQuietText(appStrings().ui_Frozen)
            .sigPressed += func|main|(_) { main.postCommandEvent(ActionSelection.Freeze) }
        }

        result.showUnavailableShortcuts(not main.takenHotKeys.isEmpty())

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

    // Keeps a persistent mode beside the inspector, with the same control to leave it.
    mtd showFrozen(frozen: bool)
    {
        if .frozenPanel.isLocallyVisible() == frozen do
            return
        .frozenPanel.show(frozen)
        .itf.onLayout()
    }

    // Keeps a global-key failure by the capture control until the next registration attempt.
    mtd showUnavailableShortcuts(unavailable: bool)
    {
        if .shortcutPanel.isLocallyVisible() == unavailable do
            return
        .shortcutPanel.show(unavailable)
        .itf.onLayout()
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

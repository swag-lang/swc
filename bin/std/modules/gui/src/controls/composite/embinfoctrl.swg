#global public

using Core, Pixel

// Selects the semantic presentation of an information bar.
//
// Each kind is a tinted ground of its tone and a dot in the tone, both answered by the palette,
// so the three notices of a surface are told apart before they are read.
enum InfoBarKind
{
    Critical        // Presents a critical error.
    Information     // Presents informational guidance.
    Message         // Presents a state the reader should know about, without reporting a failure.
}

// Configures information-bar placement and lifetime.
#[Swag.EnumFlags]
enum InfoBarFlags
{
    None = 0        // Docks at the top and remains until dismissed.
    Bottom          // Docks at the bottom instead of the top.
    AutoDismiss     // Dismisses automatically after the configured delay.
}

// Displays a themed inline message with a dismiss action.
struct InfoBar
{
    public
    {
        using frameWnd: FrameWnd     // Embedded framed-window behavior and presentation.

        sigDismissed: SigArray'func||(*Wnd)     // Emitted when user action or timeout dismisses the bar.

        readonly
        {
            kind:  InfoBarKind      // Current semantic presentation.
            flags: InfoBarFlags     // Current placement and lifetime options.
            autoDismissDelay: Time.Duration = 4's     // Delay used by [[Gui.InfoBarFlags.AutoDismiss]].

            late label:       *Label          // Message label owned by this bar.
            late closeButton: *IconButton     // Dismiss button owned by this bar.
        }
    }

    timer:      *Timer?     // Active auto-dismiss timer.
    ground:     Color       // Tinted ground of the current kind, painted on the control corner.
    dismissing: bool        // Whether the bar is leaving: its words fade, then its height closes.
}

impl IWnd for InfoBar
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let radius  = .themeMetrics().corner_Control
        painter.setParams(.Antialiased)
        painter.fillRoundRect(.clientRect(), radius, radius, .ground)
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .timer = null
        .dismiss()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        if .timer
        {
            .app().removeTimer(.timer)
            .timer = null
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged do
            .applyTheme()
    }
}

private impl InfoBar
{
    mtd applyTheme()
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()

        // A notice is a tinted ground on the control corner, a dot in its tone and body ink: no
        // border, no icon tile. The dot is what tells the three apart at a glance; the words carry
        // the rest.
        var ground: Color
        with me.label
        {
            .backgroundStyle = .Transparent
            .setIcon(theme.icon(.Dot, metrics.embInfo_DotSize))
            switch #complete me.kind
            {
            case .Critical:
                ground = colors.embInfo_CriticalBk
                .setTextColor(colors.embInfo_CriticalText)
                .setIconColor(colors.embInfo_CriticalMark)

            case .Information:
                ground = colors.embInfo_InformationBk
                .setTextColor(colors.embInfo_InformationText)
                .setIconColor(colors.embInfo_InformationMark)

            case .Message:
                ground = colors.embInfo_MessageBk
                .setTextColor(colors.embInfo_MessageText)
                .setIconColor(colors.embInfo_MessageMark)
            }
        }

        .ground = ground
        .invalidate()

        .closeButton.setIconColor(colors.label_TextFaint)
    }
}

impl InfoBar
{
    // Creates an information bar docked at the top of `parent` and lays the parent out again.
    //
    // [[Gui.InfoBarFlags.Bottom]] docks the bar at the bottom instead. `height` is in logical
    // units, and `autoDismissDelay` applies with [[Gui.InfoBarFlags.AutoDismiss]].
    #[Swag.Discardable]
    func create(parent: *Wnd, message: string?, kind: InfoBarKind, flags = InfoBarFlags.None, height: f32 = 40, autoDismissDelay: Time.Duration = 4's)->*InfoBar
    {
        Swag.assert(parent != null)
        Swag.assert(height > 0, "information bar height must be positive")
        Swag.assert(autoDismissDelay.seconds > 0, "auto-dismiss delay must be positive")

        let theme    = parent.theme()
        let metrics  = parent.themeMetrics()
        with let bar = Wnd.create'InfoBar(parent, Math.Rectangle{0, 0, 0, height})
        {
            .wndFlags.add(.NoScroll)
            .dockStyle        = flags.has(.Bottom) ? .Bottom : .Top
            .label            = Label.create(bar, message)
            .kind             = kind
            .flags            = flags
            .autoDismissDelay = autoDismissDelay
        }

        // The dismiss cross sits inside the label, docked to its right edge, so the text stops
        // before the band the button occupies; a message longer than that room is cut with an
        // ellipsis rather than run under the glyph.
        let closeSize = metrics.embInfo_CloseSize
        let textLeft  = metrics.embInfo_Padding + metrics.embInfo_DotSize + metrics.embInfo_DotGap
        let textRight = closeSize + 2 * metrics.embInfo_CloseMargin
        with bar.label
        {
            .updateFlags(add: .Ellipsis)
            .setTextHorizontalAlignment(.Left)
            .setIconHorizontalAlignment(.Left)
            .setIconPadding({metrics.embInfo_Padding, 0, 0, 0})
            .setTextPadding({textLeft, 0, textRight, 0})
            .dockStyle = .Center
        }

        with bar.closeButton = IconButton.create(bar.label, theme.icon(.WndClose, metrics.embInfo_CloseGlyph), {0, 0, closeSize, closeSize})
        {
            .margin     = metrics.embInfo_CloseMargin
            .dockStyle  = .Right
            .sigPressed += func|bar|(_) { bar.dismiss() }
        }

        if flags.has(.AutoDismiss) do
            bar.timer = bar.addTimer(autoDismissDelay)

        bar.applyTheme()
        parent.applyLayout()

        // A notice opens its own height, then its words fade in.
        if parent.surface and not parent.app().isReducedMotion()
        {
            let animator = &parent.app().animator
            bar.resize(bar.position.width, 0, false)
            bar.label.setPresentationOpacity(0)
            discard animator.animateLayoutHeight(bar, height)

            var options: AnimationOptions
            options.delay    = Time.Duration.fromSeconds(metrics.motion_PanelSeconds)
            options.duration = Time.Duration.fromSeconds(metrics.motion_QuickSeconds)
            options.easing   = .EaseOut
            discard animator.animateF32(bar.label, AnimationChannel.from("Gui.Notice.Words"), 0, 1, func(label, value) { label.setPresentationOpacity(value) }, options)
        }

        return bar
    }

    // Changes the displayed message.
    mtd setText(message: string?)
    {
        .label.setText(message)
    }

    // Changes semantic presentation and reapplies current theme colors.
    mtd setKind(kind: InfoBarKind)
    {
        if .kind == kind do
            return
        .kind = kind
        .applyTheme()
        .invalidate()
    }

    // Emits [[Gui.InfoBar.sigDismissed]] and destroys the bar.
    //
    // The bar leaves the way it came: its words fade out, then its height closes, so the content
    // under it rises instead of jumping; only then is it destroyed. A second dismissal while it
    // leaves does nothing.
    mtd dismiss()
    {
        if .dismissing do
            return
        .dismissing = true
        .sigDismissed.call(me)

        if .timer
        {
            .removeTimer(.timer)
            .timer = null
        }

        if not .surface or .app().isReducedMotion()
        {
            .destroy()
            return
        }

        let metrics  = .themeMetrics()
        let animator = &.app().animator
        animator.cancel(.label, AnimationChannel.from("Gui.Notice.Words"))
        animator.cancel(me, AnimationChannel.from("Gui.Layout.Height"))

        var words: AnimationOptions
        words.duration = Time.Duration.fromSeconds(metrics.motion_LeaveSeconds)
        words.easing   = .Linear

        var height: AnimationOptions
        height.delay    = words.duration
        height.duration = Time.Duration.fromSeconds(metrics.motion_PanelSeconds)
        height.easing   = .EaseInOut
        height.impact   = .Layout

        let bar = me
        discard animator.animateF32(.label, AnimationChannel.from("Gui.Notice.Words"), .label.presentationOpacity, 0, func(label, value) { label.setPresentationOpacity(value) }, words)
        discard animator.animateF32(me, AnimationChannel.from("Gui.Notice.Leave"), .position.height, 0, func(bar, value) { bar.resize(bar.position.width, value, false) }, height,
                                    func|bar|(_)
                                    {
                                        if not bar.isPendingDestroy do
                                            bar.destroy()
                                    })
    }
}

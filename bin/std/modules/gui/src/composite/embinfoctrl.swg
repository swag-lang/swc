#global public

using Core, Pixel

// Selects the semantic presentation of an information bar.
enum InfoBarKind
{
    Critical        // Presents a critical error.
    Information     // Presents informational guidance.
    Message         // Presents a neutral status message.
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
    using frameWnd: FrameWnd     // Embedded framed-window behavior and presentation.

    sigDismissed: SigArray'func||(*InfoBar)     // Emitted when user action or timeout dismisses the bar.

    readonly
    {
        kind:             InfoBarKind             // Current semantic presentation.
        flags:            InfoBarFlags            // Current placement and lifetime options.
        autoDismissDelay: Time.Duration = 4's     // Delay used by [[InfoBarFlags.AutoDismiss]].

        #[Swag.Late]
        label: *Label     // Message label owned by this bar.
        #[Swag.Late]
        closeButton: *IconButton     // Dismiss button owned by this bar.
    }

    internal timer: #null *Timer     // Active auto-dismiss timer.
}

impl IWnd for InfoBar
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        .timer = null
        .dismiss()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
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
        let theme  = .theme()
        let colors = .themeColors()

        with me.label
        {
            .style.clearStyleSheetColors()
            .backgroundStyle = .Window
            switch me.kind
            {
            case .Critical:
                .setIcon(theme.icon64(.Critical, 28))
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_CriticalBk.argb))
                .setTextColor(colors.embInfo_CriticalText)

            case .Information:
                .setIcon(theme.icon64(.Information, 28))
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_InformationBk.argb))
                .setTextColor(colors.embInfo_InformationText)

            case .Message:
                .setIcon(theme.icon64(.Information, 28))
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_MessageBk.argb))
                .setTextColor(colors.embInfo_MessageText)
            }

            .setIconColor(Argb.White)
        }

        .closeButton.setIconColor(.label.textColor)
    }
}

impl InfoBar
{
    // Creates and lays out an information bar.
    #[Swag.Discardable]
    func create(parent: *Wnd, message: #null string, kind: InfoBarKind, flags = InfoBarFlags.None, height: f32 = 40, autoDismissDelay: Time.Duration = 4's)->*InfoBar
    {
        Debug.assert(parent != null)
        Debug.assert(height > 0, "information bar height must be positive")
        Debug.assert(autoDismissDelay.seconds > 0, "auto-dismiss delay must be positive")

        let theme = parent.theme()
        with let bar = Wnd.create'InfoBar(parent, {0, 0, 0, height})
        {
            .wndFlags.add(.NoScroll)
            .dockStyle        = flags.has(.Bottom) ? .Bottom : .Top
            .label            = Label.create(bar, message)
            .kind             = kind
            .flags            = flags
            .autoDismissDelay = autoDismissDelay
        }

        with bar.label
        {
            .setTextHorizontalAlignment(.Left)
            .setIconHorizontalAlignment(.Left)
            .setIconPadding({10, 0, 0, 0})
            .setTextPadding({50, 4, 0, 0})
            .dockStyle = .Center
        }

        with bar.closeButton = IconButton.create(bar.label, theme.icon24(.WndClose, 18), {0, 0, 32, 32})
        {
            .margin     = 5
            .dockStyle  = .Right
            .sigPressed += func|bar|(btn) { bar.dismiss(); }
        }

        if flags.has(.AutoDismiss) do
            bar.timer = bar.addTimer(autoDismissDelay)

        bar.applyTheme()
        parent.applyLayout()
        return bar
    }

    // Changes the displayed message.
    mtd setText(message: #null string)
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

    // Emits [[sigDismissed]] and destroys the bar.
    mtd dismiss()
    {
        .sigDismissed.call(me)
        .destroy()
    }
}

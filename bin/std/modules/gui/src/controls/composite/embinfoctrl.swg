#global public

using Core, Pixel

// Selects the semantic presentation of an information bar.
//
// Each kind is one ground, one ink and one glyph, all three answered by the palette, so the
// three notices of a surface are told apart before they are read.
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

        sigDismissed: SigArray'func||(*InfoBar)     // Emitted when user action or timeout dismisses the bar.

        readonly
        {
            kind:             InfoBarKind             // Current semantic presentation.
            flags:            InfoBarFlags            // Current placement and lifetime options.
            autoDismissDelay: Time.Duration = 4's     // Delay used by [[InfoBarFlags.AutoDismiss]].

            late label:       *Label          // Message label owned by this bar.
            late closeButton: *IconButton     // Dismiss button owned by this bar.
        }
    }

    timer: *Timer?     // Active auto-dismiss timer.
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

// The bar is one line of text with a glyph in front of it, so the glyph is sized against the
// wording rather than against the band: blown up to fill the height it stopped being a sign and
// became a picture, and it took the air in front of the message with it.
private const IconSize = 20.0
private const IconLeft = 14.0
private const TextLeft = IconLeft + IconSize + 12.0

// The dismiss cross sits inside the label, docked to its right edge, so the text stops before
// the band the button occupies; a message longer than that room is cut with an ellipsis rather
// than run under the glyph.
private const CloseSize   = 32.0
private const CloseMargin = 5.0
private const TextRight   = CloseSize + 2 * CloseMargin

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
            switch #complete me.kind
            {
            case .Critical:
                .setIcon(theme.icon(.Critical, IconSize))
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_CriticalBk.argb))
                .setTextColor(colors.embInfo_CriticalText)

            case .Information:
                .setIcon(theme.icon(.Information, IconSize))
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_InformationBk.argb))
                .setTextColor(colors.embInfo_InformationText)

            case .Message:
                .setIcon(theme.icon(.Warning, IconSize))
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_MessageBk.argb))
                .setTextColor(colors.embInfo_MessageText)
            }

            // The glyph is the wording said in one shape, so it is written in the same ink. Left
            // white it was the one part of the bar the palette did not answer for: a hard disc
            // on the dark grounds, and all but invisible on the light pastels.
            .setIconColor(.textColor)
        }

        .closeButton.setIconColor(.label.textColor)
    }
}

impl InfoBar
{
    // Creates and lays out an information bar.
    #[Swag.Discardable]
    func create(parent: *Wnd, message: string?, kind: InfoBarKind, flags = InfoBarFlags.None, height: f32 = 40, autoDismissDelay: Time.Duration = 4's)->*InfoBar
    {
        Debug.assert(parent != null)
        Debug.assert(height > 0, "information bar height must be positive")
        Debug.assert(autoDismissDelay.seconds > 0, "auto-dismiss delay must be positive")

        let theme    = parent.theme()
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
            .updateFlags(add: .Ellipsis)
            .setTextHorizontalAlignment(.Left)
            .setIconHorizontalAlignment(.Left)
            .setIconPadding({IconLeft, 0, 0, 0})
            .setTextPadding({TextLeft, 0, TextRight, 0})
            .dockStyle = .Center
        }

        with bar.closeButton = IconButton.create(bar.label, theme.icon(.WndClose, 18), {0, 0, CloseSize, CloseSize})
        {
            .margin     = CloseMargin
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

    // Emits [[sigDismissed]] and destroys the bar.
    mtd dismiss()
    {
        .sigDismissed.call(me)
        .destroy()
    }
}

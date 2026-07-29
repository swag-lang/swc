#global public

using Core, Pixel

// Selects emb info ctrl kind.
enum EmbInfoCtrlKind
{
    Critical // Selects the critical kind.
    Information // Selects the information kind.
    Message // Selects the message kind.
}

// Selects emb info ctrl flags.
#[Swag.EnumFlags]
enum EmbInfoCtrlFlags
{
    Zero // No flags are enabled.
    Top // Enables top.
    Bottom // Enables bottom.
    AutoHide // Enables auto hide.
}

// Represents emb info ctrl.
struct EmbInfoCtrl
{
    using frameWnd: FrameWnd // Embedded frame wnd state.
    #[Swag.Late]
    label: *Label // Label associated with this value.
    #[Swag.Late]
    iconBtn:    *IconButton // Icon btn associated with this value.
    ctrlFlags:  EmbInfoCtrlFlags = .Zero // Ctrl flags associated with this value.
    sigOnClose: SigArray'func||(*EmbInfoCtrl) // Signal emitted when on close.
    timer:      #null *Timer // Timer associated with this value.
    kind:       EmbInfoCtrlKind // Kind associated with this value.
}

impl IWnd for EmbInfoCtrl
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        .timer = null
        .destroy()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .timer do
            .getApp().deleteTimer(.timer)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.ntfyKind == .ThemeChanged
        {
            .setColors()
        }
    }
}

impl EmbInfoCtrl
{
    // Sets colors.
    mtd setColors()
    {
        let theme  = .getTheme()
        let colors = .getThemeColors()

        with me.label
        {
            .style.clearStyleSheetColors()
            .backgroundStyle = .Window
            switch me.kind
            {
            case .Critical:
                .icon = theme.getIcon64(.Critical, 28)
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_CriticalBk.argb))
                .iconColor = Argb.White
                .textColor = colors.embInfo_CriticalText.argb

            case .Information:
                .icon = theme.getIcon64(.Information, 28)
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_InformationBk.argb))
                .iconColor = Argb.White
                .textColor = colors.embInfo_InformationText.argb

            case .Message:
                .icon = theme.getIcon64(.Information, 28)
                .style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", colors.embInfo_MessageBk.argb))
                .iconColor = Argb.White
                .textColor = colors.embInfo_MessageText.argb
            }
        }

        .iconBtn.iconColor = .label.textColor
    }

    // Create the popup list, but do not display it
    func create(parent: *Wnd, name: #null string, kind: EmbInfoCtrlKind, flags = EmbInfoCtrlFlags.Top, height = 40)->*EmbInfoCtrl
    {
        let theme = parent.getTheme()
        with let ctrl = Wnd.create'EmbInfoCtrl(parent, {0, 0, 0, height})
        {
            .wndFlags.add(.NoScroll)
            .dockStyle = flags.has(.Top) ? .Top : .Bottom
            .label     = Label.create(ctrl, name, {})
            .ctrlFlags = flags
            .kind      = kind
        }

        with ctrl.label
        {
            .horzAlignmentText = .Left
            .horzAlignmentIcon = .Left
            .paddingIcon.x     = 10
            .paddingText.x     = 50
            .paddingText.y     = 4
            .dockStyle         = .Center
        }

        with ctrl.iconBtn = IconButton.create(ctrl.label, theme.getIcon24(.WndClose, 18), {0, 0, 32, 32})
        {
            .margin     = 5
            .dockStyle  = .Right
            .sigPressed += func|ctrl|(btn)
            {
                ctrl.sigOnClose.call(ctrl)
                ctrl.destroy()
            }
        }

        if flags.has(.AutoHide) do
            ctrl.timer = ctrl.addTimer(4's)

        ctrl.setColors()

        parent.applyLayout()
        return ctrl
    }
}

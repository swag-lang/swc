#global public

using Core, Pixel

// A nonmodal notification beside an application's notification-area icon.
//
// The floating card contains a status dot, title, wrapped message, close button, and an
// optional “do not show again” check button. It leaves after `lifetime` unless dismissed
// sooner. The owning application keeps the returned pointer only until `sigDismissed` fires.
struct TrayNotice
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigOptionChanged: SigArray'func||(*TrayNotice, bool)     // Emits the checked state of the optional preference.
        sigDismissed:     SigArray'func||(*TrayNotice)           // Emitted when the notice's surface is destroyed.

        readonly
        {
            optionCheck: *CheckButton?     // Optional preference control, or `null` when no label was given.
            late closeButton: *IconButton  // Dismisses this notice without changing the preference.
        }
    }

    late dot: *Label
    timer: *Timer?
}

impl IWnd for TrayNotice
{
    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .close()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.timer)
        .sigDismissed.call(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged
        {
            .dot.setIconColor(.themeColors().arc)
            .closeButton.setIconColor(.themeColors().label_TextFaint)
        }
        evt.accepted = false
    }
}

impl TrayNotice
{
    // Opens a notice near `iconOwner`'s notification-area icon.
    //
    // `lifetime` must be positive. `dontShowAgainLabel` adds a real check button; toggling it
    // emits [[Gui.TrayNotice.sigOptionChanged]], and checking it dismisses the notice. The
    // returned notice is owned by its new surface and becomes invalid after `sigDismissed`.
    // On desktops without icon geometry, the notice stands near the pointer's screen edge.
    #[Swag.Discardable]
    func open(iconOwner: *Surface, title, message: string, dontShowAgainLabel: string? = null,
              lifetime: Time.Duration = 10's)->*TrayNotice?
    {
        Swag.assert(lifetime.seconds > 0, "a tray notice needs a positive lifetime")

        var icon: Math.Rectangle
        let hasIcon = iconOwner.trayIconBounds(&icon)
        let anchor  = hasIcon ? Math.Point{icon.horzCenter(), icon.vertCenter()} : Input.mousePosition()
        let work    = Env.monitorForPoint(anchor).physicalWorkArea
        let surface = catch iconOwner.app.createSurface(cast(s32, anchor.x), cast(s32, anchor.y),
                                                         420, 180, .ToolWindow | .TopMost)
        {
            return null
        }

        surface.minSize = {}
        let theme   = iconOwner.app.theme
        let metrics = &theme.metrics
        let scale   = surface.dpiScale
        let shadow  = surface.shadowMargin()
        let inset   = metrics.embInfo_Padding
        let gap     = metrics.embInfo_DotGap
        let width   = Math.min(metrics.trayNotice_Width,
                               Math.max(metrics.trayNotice_MinWidth, work.width / scale - 2 * inset))
        let content = width - 2 * inset

        with let result = Wnd.create'TrayNotice(surface.wnd)
        {
            .backgroundStyle = .Transparent
        }
        with let card = FloatingPanel.create(result)
        {
            .dockStyle = .Center
            .setShadow(false)
        }

        let dotSize   = metrics.embInfo_DotSize
        let closeSize = metrics.embInfo_CloseSize
        let titleX    = inset + dotSize + gap
        let titleWidth = content - dotSize - closeSize - 2 * gap
        with let titleLabel = Label.create(card, title, {titleX, inset, titleWidth, 0})
        {
            .style.setFont(theme.createDefaultFont(metrics.defaultFontSize, .Bold), .Regular)
            .setTextHorizontalAlignment(.Left)
        }
        let titleHeight = Math.max(titleLabel.itf.measureContent({titleWidth, 0}).y, closeSize)
        titleLabel.resize(titleWidth, titleHeight, false)
        with result.dot = Label.create(card, "", Math.Rectangle{x: inset, y: inset, width: dotSize, height: titleHeight})
        {
            .setIcon(theme.icon(.Dot, dotSize))
            .setIconColor(result.themeColors().arc)
        }
        with result.closeButton = IconButton.create(card, theme.icon(.WndClose, metrics.embInfo_CloseGlyph),
                                                     {width - inset - closeSize, inset, closeSize, closeSize}, flags: .Flat)
        {
            .setIconColor(result.themeColors().label_TextFaint)
            .sigPressed += func|notice = result|(_) { notice.dismissSoon() }
        }

        let bodyY = inset + titleHeight + gap
        with let body = Label.create(card, message, {inset, bodyY, content, 0}, flags: .WordWrap | .SecondaryText)
        {
            .setTextHorizontalAlignment(.Left)
            .setTextVerticalAlignment(.Top)
        }
        let bodyHeight = body.itf.measureContent({content, 0}).y
        body.resize(content, bodyHeight, false)

        var height = bodyY + bodyHeight + inset
        if let caption = dontShowAgainLabel
        {
            let choiceY = bodyY + bodyHeight + gap
            result.optionCheck = CheckButton.create(card, caption, {inset, choiceY, content, 0})
            let choice = result.optionCheck
            let choiceHeight = choice.itf.measureContent({content, 0}).y
            choice.resize(content, choiceHeight, false)
            choice.sigChanged += func|notice = result|(button)
            {
                let checked = button.isChecked()
                notice.sigOptionChanged.call(notice, checked)
                if checked do
                    notice.dismissSoon()
            }
            height = choiceY + choiceHeight + inset
        }

        surface.setView(result)
        // A native surface reserves the reach of its shadow inside its outer rectangle.
        let physicalWidth  = (width + 2 * shadow) * scale
        let physicalHeight = (height + 2 * shadow) * scale
        let margin         = inset * scale
        let x              = Math.clamp(anchor.x - physicalWidth * 0.5,
                                        work.x + margin, Math.max(work.right() - physicalWidth - margin, work.x + margin))
        var y              = hasIcon ? icon.y - physicalHeight - margin : work.bottom() - physicalHeight - margin
        if y < work.y + margin and hasIcon do
            y = icon.bottom() + margin
        y = Math.clamp(y, work.y + margin, Math.max(work.bottom() - physicalHeight - margin, work.y + margin))
        surface.setPosition({x, y, physicalWidth, physicalHeight})
        surface.show()
        result.timer = result.addTimer(lifetime)
        return result
    }

    // Dismisses this notice without changing its preference control.
    mtd close()
    {
        .stopTimer(&.timer)
        .surface?.destroy()
    }

    private mtd dismissSoon()
    {
        .stopTimer(&.timer)
        .timer = .addTimer(1'ms)
    }
}

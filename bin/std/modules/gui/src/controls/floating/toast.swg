#global public

using Core, Pixel

// The mark between the sentence of a toast and the name after it.
private const ToastDetailMark = "·"

// Keeps a line whole when its nominal width fits; only overlong text is elided at draw scale.
private func paintToastTextLine(painter: *Painter, x, centerY: f32, text: string, font: *Font, color: Color, maxWidth, deviceScale: f32)->f32
{
    if text.count == 0 do
        return 0
    let nominalWidth = Painter.measureString(text, font).width
    if nominalWidth <= maxWidth
    {
        painter.drawString(x, font.opticalLineTop(centerY), text, font, color)
        return nominalWidth
    }

    return paintTextLine(painter, x, centerY, text, font, color, maxWidth, deviceScale)
}

// Selects the dot a [[Gui.Toast]] leads with.
enum ToastTone
{
    None        // No dot: the sentence alone.
    Done        // An Arc dot: something was done.
    Failure     // A critical dot: something could not be done.
}

// Confirms briefly what the hand just did — copied, saved, removed — or reports a failure that needs no answer.
//
// One pill, centred above the foot of its parent: an optional dot in its tone, the sentence, a
// name or a path in faint mono, and at most one action in Arc link ink. It arrives and leaves
// like every floating surface, stays [[Gui.ThemeMetrics.toast_Seconds]] — longer with an action,
// and as long as the pointer is over it — and never takes the keyboard. A new message replaces
// the one on screen. Anything that needs an answer is a dialog, not a toast.
//
// ```swag
// let toast = Toast.create(view)
// toast.show("Copied to the clipboard")
// ```
struct Toast
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigAction: SigArray'func||(*Toast)     // Emitted when the action at the end of the pill is clicked.

        readonly
        {
            message: String        // The sentence.
            detail:  String        // A name or a path after it, in faint mono.
            action:  String        // The word of the action, or empty for none.
            tone:    ToastTone     // The dot it leads with.
        }
    }

    timer:      *Timer?            // Pending departure, removed while the pointer is over the pill.
    hovered:    bool               // Whether the pointer is over the pill.
    hotAction:  bool               // Whether the pointer is over the action.
    actionRect: Math.Rectangle     // Where the action stands, in local coordinates.
}

impl IWnd for Toast
{
    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        paintFloatingShadow(me, evt.paintContext.painter, .clientRect(), .themeMetrics().toast_Corner)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let body    = .clientRect()
        paintFloatingGround(me, painter, body, metrics.toast_Corner)

        let font    = .theme().createDefaultFont(metrics.defaultFontSize)
        let mono    = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)
        let centerY = body.vertCenter()
        let scale   = .deviceScale()
        var x       = metrics.toast_Padding

        if .tone != .None
        {
            let dot = metrics.toast_DotSize
            painter.setAntialiased(true)
            painter.fillCircle(x + dot * 0.5, centerY, dot * 0.5, .tone == .Failure ? colors.critical : colors.arc)
            x += dot + metrics.toast_Gap
        }

        let contentRight = .action.length ? .actionRect.x - metrics.toast_ActionGap : body.right() - metrics.toast_Padding
        let textRoom     = Math.max(contentRight - x, 0)
        let messageRoom  = .detail.length ? textRoom * 0.7 : textRoom
        x += paintToastTextLine(painter, x, centerY, .message.toString(), font, colors.text, messageRoom, scale)
        if .detail.length
        {
            let markWidth = Painter.measureString(ToastDetailMark, font).width
            if contentRight - x > 2 * metrics.toast_DetailGap + markWidth
            {
                x += metrics.toast_DetailGap
                x += paintToastTextLine(painter, x, centerY, ToastDetailMark, font, colors.faintText, markWidth, scale)
                x += metrics.toast_DetailGap
                x += paintToastTextLine(painter, x, centerY, .detail.toString(), mono, colors.faintText, Math.max(contentRight - x, 0), scale)
            }
        }

        if .action.length
        {
            let bold        = .theme().createDefaultFont(metrics.defaultFontSize, .Bold)
            let action      = .action.toString()
            let color       = .hotAction ? colors.text : colors.link
            let actionWidth = Painter.measureString(action, bold).width
            if actionWidth <= .actionRect.width do
                painter.drawString(.actionRect.x, bold.opticalLineTop(centerY), action, bold, color)
            else do
                discard paintToastTextLine(painter, .actionRect.x, centerY, action, bold, color, .actionRect.width, scale)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Move:

            // The pill stays as long as it is read.
            if not .hovered
            {
                .hovered = true
                .cancelTimer()
            }

            let hot = .action.length != 0 and .actionRect.contains(pos)
            if hot != .hotAction
            {
                .hotAction = hot
                if hot do
                    .cursor = Cursor.from(CursorShape.Hand)
                else do
                    .cursor.clear()
                .invalidate()
            }

        case .Leave:
            .hovered   = false
            .hotAction = false
            .cursor.clear()
            .invalidate()
            .startTimer()

        case .Pressed:
            if evt.button == .Left and .hotAction
            {
                .sigAction.call(me)
                .dismiss()
            }
        }
    }

    // A floating child is placed after its docked siblings, so the pill follows its parent's size.
    mtd impl onLayout()
    {
        if .isLocallyVisible() do
            .place()
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .timer = null
        .dismiss()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .cancelTimer()
    }
}

private impl Toast
{
    mtd cancelTimer()
    {
        if not .timer do
            return
        .app().removeTimer(.timer)
        .timer = null
    }

    mtd startTimer()
    {
        .cancelTimer()
        if not .isLocallyVisible() do
            return
        let metrics = .themeMetrics()
        .timer = .addTimer(Time.Duration.fromSeconds(.action.length ? metrics.toast_ActionSeconds : metrics.toast_Seconds))
    }

    // Measures the pill for what it says, and stands it centred above the foot of its parent.
    mtd place()
    {
        let parent  = unwrap .parent
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.defaultFontSize)
        let mono    = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)

        var width = 2 * metrics.toast_Padding
        if .tone != .None do
            width += metrics.toast_DotSize + metrics.toast_Gap
        width += Painter.measureString(.message.toString(), font).width
        if .detail.length do
            width += 2 * metrics.toast_DetailGap + Painter.measureString(ToastDetailMark, font).width + Painter.measureString(.detail.toString(), mono).width

        .actionRect = {}
        var actionNominalWidth = 0'f32
        var naturalActionX     = 0'f32
        if .action.length
        {
            let bold = .theme().createDefaultFont(metrics.defaultFontSize, .Bold)
            actionNominalWidth = Painter.measureString(.action.toString(), bold).width
            naturalActionX     = width - metrics.toast_Padding + metrics.toast_ActionGap
            width += metrics.toast_ActionGap + actionNominalWidth
        }

        let bounds       = parent.clientRect()
        let naturalWidth = Math.ceil(width)
        width = Math.max(Math.min(Math.ceil(width), bounds.width - 2 * metrics.floating_Inset), 0)
        if .action.length
        {
            let room    = Math.max(width - 2 * metrics.toast_Padding, 0)
            let clipped = Math.min(actionNominalWidth, Math.max(room - metrics.toast_ActionGap, 0))
            var actionX = width - metrics.toast_Padding - clipped
            if width >= naturalWidth and clipped == actionNominalWidth do
                actionX = naturalActionX
            actionX     = Math.max(actionX, 0)
            .actionRect = Math.Rectangle{actionX, 0, Math.min(clipped, width - actionX), metrics.toast_Height}
        }

        let x = Math.round(bounds.horzCenter() - width * 0.5)
        let y = bounds.bottom() - metrics.toast_Bottom - metrics.toast_Height
        .setPosition(Math.Rectangle{x, y, width, metrics.toast_Height})
    }
}

impl Toast
{
    // Creates a hidden toast over `parent`, which it stands centred above the foot of.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*Toast
    {
        with let result = Wnd.create'Toast(parent, null, {}, id)
        {
            .backgroundStyle = .Transparent
            .dockStyle       = .Float
            .focusPolicy     = .None
            .wndFlags.add(.Hidden)
        }

        liftFloating(result)
        return result
    }

    // Shows `message`, with `detail` after it in faint mono, led by the dot of `tone`, and `action` at its end when not empty.
    //
    // A toast already on screen takes the new message in place, without leaving first.
    mtd show(message: string, detail: string = "", tone = ToastTone.Done, action: string = "")
    {
        .message   = String.from(message)
        .detail    = String.from(detail)
        .action    = String.from(action)
        .tone      = tone
        .hotAction = false
        liftFloating(me)
        .place()
        .bringToFront()

        let travel = .themeMetrics().motion_EdgeTravel
        if not .isLocallyVisible() do
            discard .app().animator.arrive(me, {0, travel})
        .invalidate()
        if not .hovered do
            .startTimer()
    }

    // Takes the toast away now, with the floating departure.
    mtd dismiss()
    {
        .cancelTimer()
        .hovered = false
        discard .app().animator.leave(me)
    }
}

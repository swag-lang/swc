#global namespace ToolTip

internal
{
    struct ToolTipVal
    {
        owner:      *Wnd = undefined     // Window that requested the tooltip.
        surfacePos: Math.Point           // Anchor in surface coordinates.
        str:        String               // Text to display.
        delay:      f32                  // Remaining delay in seconds.
        startDelay: f32                  // Full delay restored after pointer movement.
    }

    var g_Pending:      #null *ToolTipVal
    var g_Current:      #null *FrameWnd
    var g_CurrentOwner: #null *Wnd
}

#drop
{
    ToolTip.hide()
}

func update(dt: f32)
{
    let pending = g_Pending
    if !pending do
        return

    pending.delay -= dt
    if pending.delay < 0
    {
        // Make a copy because g_Pending will be destroy by 'show'
        let copy = pending[]
        show(copy.owner, copy.surfacePos, copy.str, 0's)
    }
}

// Hides the current or pending tooltip.
public func hide()
{
    let current = g_Current
    if current do
        current.destroy()

    g_Current      = null
    g_CurrentOwner = null

    Memory.delete(g_Pending)
    g_Pending = null
}

// Hide the current tooltip, if visible
func hide(owner: *Wnd)
{
    let pending = g_Pending
    if pending and pending.owner == owner do
        ToolTip.hide()
    elif owner == g_CurrentOwner do
        ToolTip.hide()
}

// Reset timer
func resetTimer(mousePos: Math.Point)
{
    let pending = g_Pending
    if pending
    {
        pending.surfacePos = mousePos
        pending.delay      = pending.startDelay
    }
}

// Shows `str` near `surfacePos`, after `delay`, for `owner`.
public func show(owner: *Wnd, surfacePos: Math.Point, str: #null string, delay: Time.Duration = 500'ms)
{
    if str == null or @countof(str) == 0 do
        return

    if !g_Current and delay.seconds > 0
    {
        if !g_Pending do
            g_Pending = Memory.new'ToolTipVal()
        let pending = g_Pending!
        pending.owner      = owner
        pending.surfacePos = surfacePos
        pending.str        = str
        pending.startDelay = cast(f32) delay.seconds
        pending.delay      = cast(f32) delay.seconds
        return
    }

    let copy: String = str
    ToolTip.hide()

    let top = owner.surface!.wnd
    var pos = top.surfaceToLocal(surfacePos)
    pos.offset(12)

    // Frame container
    let cur = Wnd.create'FrameWnd(top, {pos.x, pos.y, 50, 100})
    g_Current = cur
    cur.setFrameForm(.Square)
    cur.wndFlags.add(.TopMost)
    cur.style.addStyleSheetColors("frameWnd_Bk     $toolTip_Bk")
    cur.style.addStyleSheetColors("frameWnd_Border $toolTip_Border")
    cur.padding    = 0
    g_CurrentOwner = owner

    // View
    let view = cur.createView'Wnd()
    view.backgroundStyle = .Transparent
    view.margin          = 0

    let colors  = top.themeColors()
    let metrics = top.themeMetrics()

    // Rich edit
    let edit = RichEditCtrl.create(view)
    edit.setFlags(.WordWrap)
    edit.setForm(.Edit)
    edit.styles[0].colFg = colors.toolTip_Text
    cur.sendResizeEvent()
    edit.setText(copy)
    edit.margin    = metrics.toolTip_Padding
    edit.dockStyle = .Center

    // Auto size
    var {w, h} = edit.evaluateSize()
    w += 2 * metrics.toolTip_Padding
    h += 2 * metrics.toolTip_Padding
    cur.setPosition(Math.Rectangle{pos.x, pos.y, w, h})
    cur.fitPosInParent()
    cur.bringToFront()
}

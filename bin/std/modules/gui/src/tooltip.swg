#global namespace ToolTip

internal
{
    struct ToolTipVal
    {
        owner:      *Wnd = undefined
        surfacePos: Math.Point
        str:        String
        delay:      f32
        startDelay: f32
    }

    var g_Pending:      #null *ToolTipVal
    var g_Current:      #null *FrameWnd
    var g_CurrentOwner: #null *Wnd
}

#drop
{
    hide()
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
        let copy = dref pending
        show(copy.owner, copy.surfacePos, copy.str, 0's)
    }
}

// Hide the current tooltip, if visible
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
        hide()
    elif owner == g_CurrentOwner do
        hide()
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

// Show a tooltip
public func show(owner: *Wnd, surfacePos: Math.Point, str: #null string, delay: Time.Duration = 500'ms)
{
    if str == null or @countof(str) == 0 do
        return

    if !g_Current and delay.timeInSeconds > 0
    {
        if !g_Pending do
            g_Pending = Memory.new'ToolTipVal()
        let pending = notnull g_Pending
        pending.owner      = owner
        pending.surfacePos = surfacePos
        pending.str        = str
        pending.startDelay = delay.timeInSeconds
        pending.delay      = delay.timeInSeconds
        return
    }

    let copy: String = str
    hide()

    let top = (notnull owner.surface).wnd
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

    let colors  = top.getThemeColors()
    let metrics = top.getThemeMetrics()

    // Rich edit
    let edit = RichEditCtrl.create(view)
    edit.setRichEdFlags(.WordWrap)
    edit.setForm(.Edit)
    edit.styles[0].colFg = colors.toolTip_Text
    cur.sendResizeEvent()
    edit.setText(copy)
    edit.margin    = metrics.toolTip_Padding
    edit.dockStyle = .Center

        // Auto size
        var (w, h) = edit.evaluateSize()
    w += 2 * metrics.toolTip_Padding
    h += 2 * metrics.toolTip_Padding
    cur.setPosition(Math.Rectangle{pos.x, pos.y, w, h})
    cur.fitPosInParent()
    cur.bringToTop()
}

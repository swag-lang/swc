#global namespace ToolTip

// One tool tip request, counting down toward the tip it will become.
//
// Public only because [[Gui.ToolTip.State]] holds one and a module API cannot export a type
// through a private field. Nothing outside builds or reads one.
#[Swag.Opaque, Swag.NoDoc]
public struct Request
{
    owner:      *Wnd = undefined     // Window that requested the tooltip.
    surfacePos: Math.Point           // Anchor in surface coordinates.
    str:        String               // Text to display.
    delay:      f32                  // Remaining delay in seconds.
    startDelay: f32                  // Full delay restored after pointer movement.
}

// The live tool tip of one application.
//
// [[Gui.Application]] owns one, for the same reason it owns the focus and the drag: a tip is one
// pointer's state over one window tree. Held per process instead, two applications in a process
// would share a single tip, and one left open at the end of a test would reach the next test and
// destroy a window whose surface has already gone.
public struct State
{
    public
    sigLinkActivated: SigArray'func||(*Wnd, string)     // Emitted when the reader activates a link inside the visible tip.

    internal
    {
        pending:       #null *Request      // Request still counting down.
        current:       #null *FrameWnd     // Tip on screen.
        currentOwner:  #null *Wnd          // Window the visible tip annotates.
        pointerInside: bool                // Whether the pointer is over the visible tip.
    }
}

impl State
{
    // Releases the request still waiting on its delay.
    //
    // The visible tip is a window of the application's own tree and is destroyed with it, so it is
    // deliberately not touched here: by the time an application drops, its surfaces are gone.
    mtd opDrop()
    {
        Memory.delete(.pending)
    }

    // Counts the pending request down, and turns it into a tip when its delay runs out.
    mtd update(dt: f32)
    {
        let pending = .pending
        if !pending do
            return

        pending.delay -= dt
        if pending.delay < 0
        {
            // Detach the request before `show` clears this state, and keep its text alive until the
            // tip has read it: `show` starts by hiding, which is what frees `pending`.
            .pending = null
            defer Memory.delete(pending)
            .show(pending.owner, pending.surfacePos, pending.str, 0's)
        }
    }

    // Hides the visible tip and drops any request waiting on its delay.
    public mtd hide()
    {
        let current = .current
        if current do
            current.destroy()

        .current       = null
        .currentOwner  = null
        .pointerInside = false

        Memory.delete(.pending)
        .pending = null
    }

    // Hides the tip if `owner` is the window it belongs to.
    mtd hideOwnedBy(owner: *Wnd)
    {
        let pending = .pending
        if pending and pending.owner == owner do
            .hide()
        elif owner == .currentOwner do
            .hide()
    }

    // Whether `wnd` is the visible tip or part of it.
    public mtd contains(wnd: #null *Wnd)->bool
    {
        let current = .current
        if !current or !wnd do
            return false
        return current == wnd or current.isAncestorOf(wnd)
    }

    // Whether the visible tip carries a link, and so has something to be reached for.
    private mtd isInteractive()->bool
    {
        let current = .current
        if !current or !@isset(current.view) do
            return false
        let label = cast(*Label) current.view
        return label.name.hasUrl
    }

    // Follows the pointer off `from` and `onto` another window, deciding whether the tip survives.
    //
    // A tip carrying a link is the only one the pointer may enter: it stays while the pointer is
    // over it, so the link can be reached, and goes as soon as the pointer leaves it. Every other
    // tip belongs to the window it annotates and goes when that window is left — which is what
    // stops a tip from following the pointer across the interface.
    //
    // `from` is only ever compared, never read: the window the pointer left may already be on its
    // way out by the time this runs.
    mtd pointerMoved(from: #null *Wnd, onto: #null *Wnd)
    {
        if .contains(onto)
        {
            if .isInteractive()
            {
                .pointerInside = true
                return
            }
        }
        elif .pointerInside
        {
            .hide()
            return
        }

        if from do
            .hideOwnedBy(from)
    }

    // Restarts the delay of the pending request from a new pointer position.
    mtd resetTimer(mousePos: Math.Point)
    {
        let pending = .pending
        if pending
        {
            pending.surfacePos = mousePos
            pending.delay      = pending.startDelay
        }
    }

    // Shows `str` near `surfacePos`, after `delay`, for `owner`.
    //
    // `str` is [[Pixel.RichString]] markup, so a tip is not limited to one flat sentence: it can
    // set bold, italic and underline, reach the three palette colors with `<pN>`, and carry
    // `<url>` spans the reader can click. A tip holding a link stays while the pointer is over it
    // and reports the activation through [[Gui.ToolTip.State.sigLinkActivated]]; one holding none is
    // passive and goes as soon as the pointer reaches it.
    //
    // The tip is exactly as large as the text it holds. Past [[Gui.ThemeMetrics.toolTip_MaxWidth]]
    // it wraps rather than grow, past [[Gui.ThemeMetrics.toolTip_MaxHeight]] it ends its last line
    // with an ellipsis rather than grow, and it never scrolls — so a caller can hand it any length
    // knowing the reader is shown a box, not a viewport onto something longer. Keep a tip to what
    // fits: text the height cap truncates is text nobody reads.
    public mtd show(owner: *Wnd, surfacePos: Math.Point, str: #null string, delay: Time.Duration = 500'ms)
    {
        if str == null or @countof(str) == 0 do
            return

        if !.current and delay.seconds > 0
        {
            if !.pending do
                .pending = Memory.new'Request()
            let pending = .pending!
            pending.owner      = owner
            pending.surfacePos = surfacePos
            pending.str        = str
            pending.startDelay = cast(f32) delay.seconds
            pending.delay      = cast(f32) delay.seconds
            return
        }

        let copy: String = str
        .hide()

        let top     = owner.surface!.wnd
        let metrics = top.themeMetrics()

        var pos = top.surfaceToLocal(surfacePos)
        pos.offset(metrics.toolTip_Offset)

        // The theme says how large a tip may grow; the window says how large one can be shown. A
        // tip wider or taller than what holds it would only be pushed back inside by
        // `fitPosInParent`, losing the edge it was placed against.
        let room = Math.Point{Math.min(metrics.toolTip_MaxWidth, top.position.width), Math.min(metrics.toolTip_MaxHeight, top.position.height)}

        // A tip is a passive annotation, so it is a frame and a label and nothing else: no editor,
        // no viewport, no scroll bar, and nothing the keyboard or the wheel can reach. The frame
        // opens at its cap and `fitToText` cuts it down before anything paints.
        let cur = Wnd.create'FrameWnd(top, {pos.x, pos.y, room.x, room.y})
        .current      = cur
        .currentOwner = owner
        cur.setFrameForm(.Square)
        cur.wndFlags.add(.TopMost)
        cur.style.addStyleSheetColors("frameWnd_Bk     $toolTip_Bk")
        cur.style.addStyleSheetColors("frameWnd_Border $toolTip_Border")
        cur.setAllPaddings(metrics.toolTip_Padding)

        let label = cur.createView'Label()
        label.updateFlags(.WordWrap | .Ellipsis)
        label.setTextAlignment(.Left, .Center)

        // The tip repaints the label's palette rather than flattening it to one ink: markup keeps
        // its colors and a link still looks like one, each answered against the tip's inverted
        // ground. An explicit `textColor` would collapse all six into the same value.
        label.style.addStyleSheetColors("label_Text  $toolTip_Text")
        label.style.addStyleSheetColors("url_Text    $toolTip_Link")
        label.style.addStyleSheetColors("url_HotText $toolTip_HotLink")
        label.style.addStyleSheetColors("richColor1  $toolTip_Rich1")
        label.style.addStyleSheetColors("richColor2  $toolTip_Rich2")
        label.style.addStyleSheetColors("richColor3  $toolTip_Rich3")

        // Resolve the sheet now rather than at the first paint: the tip is measured, sized and
        // placed before anything paints, and a caller reading its colors in between would read the
        // colors of the surface underneath.
        label.computeStyle()
        label.setText(copy.toString())

        // The label reports the link; the tip reports which annotation it came from, because the
        // owner is what a handler can act on and the label is gone a moment later.
        label.sigLinkActivated += func|state = me, owner|(lbl, link)
        {
            discard lbl
            state.sigLinkActivated.call(owner, link)
        }

        cur.setPosition(fitToText(label, pos, room, metrics.toolTip_Padding))
        cur.fitPosInParent()
        cur.bringToFront()
    }
}

// Shows a tip for `owner`, in the application `owner` belongs to.
//
// See [[Gui.ToolTip.State.show]] for what a tip may contain and how large it may become.
public func show(owner: *Wnd, surfacePos: Math.Point, str: #null string, delay: Time.Duration = 500'ms)
{
    owner.app().toolTip.show(owner, surfacePos, str, delay)
}

// Hides `owner`'s tip, if it is the one showing.
public func hide(owner: *Wnd)
{
    owner.app().toolTip.hideOwnedBy(owner)
}

// Returns the rectangle at `pos` that shows `label` whole, or as much of it as `room` allows.
//
// The text is measured against the width left inside `room`, so a long tip wraps instead of
// running off the screen. Past its height the label is given the line budget that height affords
// and ends its last line with an ellipsis, which is what replaces the scroll bar a tip must
// never show.
private func fitToText(label: *Label, pos, room: Math.Point, inset: Math.Vector4)->Math.Rectangle
{
    let roomX = Math.max(room.x - inset.x - inset.z, 1)
    let roomY = Math.max(room.y - inset.y - inset.w, 1)

    // Both axes are handed to the text: `Wnd.measure` asks a window for its content only on an
    // axis carrying no authored size, and creating the label authored both.
    label.preferredSize = {}

    var need = label.measure({roomX, 0}).preferred
    if need.y > roomY
    {
        let lineHeight = Math.max(label.font().regular!.height, 1)
        label.setMaxLines(cast(u32) Math.max(Math.floor(roomY / lineHeight), 1))
        need = label.measure({roomX, 0}).preferred
    }

    // Both axes round up. `Wnd.resize` rounds the size it is committed, and a dropped fraction is
    // a line the box no longer holds — which is exactly how the previous tip earned a scroll bar.
    var result: retval
    result.x      = pos.x
    result.y      = pos.y
    result.width  = Math.ceil(Math.min(need.x, roomX) + inset.x + inset.z)
    result.height = Math.ceil(Math.min(need.y, roomY) + inset.y + inset.w)
    return result
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A responsive view keeps its full width when a vertical bar appears or goes away.
struct ResponsiveScrollView
{
    using wnd:  Wnd
    resizing:   u32
    visits:     u32
    horizontal: bool
}

impl IWnd for ResponsiveScrollView
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        let scroll = assume cast(*ScrollWnd, unwrap .parent)
        if scroll.view == null do
            return
        .resizing += 1
        defer .resizing -= 1
        .visits += 1
        Swag.require(.resizing == 1 and .visits < 8)
        if .horizontal do
            scroll.setScrollSize(.position.height, 0)
        else do
            scroll.setScrollSize(0, .position.width)
    }
}

// A vertical bar overlays a stable viewport and cannot change the view's own extent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 300)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 196})
    scroll.updateFlags(.DisableHorizontal)
    let view = scroll.createView'ResponsiveScrollView()
    scroll.setScrollSize(0, 200)
    Swag.require(view.position.width == 200)
    Swag.require(scroll.scrollSize.y == view.position.width and scroll.showBarV)
    scroll.setScrollPos(0, 100)
    Swag.require(scroll.scrollPosition() == Math.Point{0, 4} and scroll.showBarV)

    view.visits = 0
    scroll.resize(200, 220)
    Swag.require(view.position.width == 200 and not scroll.showBarV)
    Swag.require(scroll.scrollSize.y == 200)
}

// A horizontal bar likewise leaves the view's height and extent alone.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 300)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 196, 200})
    let view   = scroll.createView'ResponsiveScrollView()
    view.horizontal = true
    scroll.setScrollSize(200, 0)
    Swag.require(view.position.height == 200)
    Swag.require(scroll.scrollSize.x == view.position.height and scroll.showBarH)
    scroll.setScrollPos(100, 0)
    Swag.require(scroll.scrollPosition() == Math.Point{4, 0} and scroll.showBarH)

    view.visits = 0
    scroll.resize(220, 200)
    Swag.require(view.position.height == 200 and not scroll.showBarH)
    Swag.require(scroll.scrollSize.x == 200)
}

// Neither axis can create overflow on the other; the bars leave the viewport unchanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    let view   = scroll.createView'Wnd()
    let room   = view.position

    scroll.setScrollSize(200, 300)
    Swag.require(scroll.showBarV and not scroll.showBarH and view.position == room)
    scroll.setScrollSize(300, 200)
    Swag.require(scroll.showBarH and not scroll.showBarV and view.position == room)
    scroll.setScrollSize(300, 300)
    Swag.require(scroll.showBarV and scroll.showBarH and view.position == room)
    scroll.setScrollSize(100, 100)
    Swag.require(not scroll.showBarV and not scroll.showBarH and view.position == room)
}

// The overlaid track remains draggable while the child owns the full viewport.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    let view   = scroll.createView'Wnd()
    scroll.setScrollSize(200, 1000)
    let edge = Math.Point{197, 100}
    Swag.require(host.mouseTargetAt(edge) == view)
    host.moveMouse(edge)
    host.finishAnimations()
    Swag.require(scroll.isHotBarV and scroll.barPresence > 0)
    host.mouseDown(edge)
    Swag.require(host.app.mouseCaptureWnd == scroll and scroll.scrollPosition().y > 0)
    host.mouseUp(edge)
    Swag.require(host.app.mouseCaptureWnd == null)

    scroll.setScrollSize(1000, 1000)
    let bottom = Math.Point{100, 197}
    Swag.require(host.mouseTargetAt(bottom) == view)
    host.moveMouse(bottom)
    Swag.require(scroll.isHotBarH)
    host.mouseDown(bottom)
    Swag.require(host.app.mouseCaptureWnd == scroll and scroll.scrollPosition().x > 0)
    host.mouseUp(bottom)
    Swag.require(view.position == Math.Rectangle{0, 0, 200, 200})
}

// A hover hint exposes existing scrollbars without moving content or changing its viewport.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.setScrollSize(100, 1000)
    let viewport = scroll.view.position
    let position = scroll.scrollPosition()
    scroll.revealScrollBars()
    Swag.require(scroll.barPresence == 1)
    Swag.require(scroll.view.position == viewport and scroll.scrollPosition() == position)
    host.fireTimers()
    host.finishAnimations()
    Swag.require(scroll.barPresence == 0)
}

// Repeated wheel destinations preserve speed instead of kicking a fresh ease-out each time.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    host.setReducedMotion(false)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.setScrollSize(100000, 100000)
    scroll.smoothScrollTo({10000, 10000})
    host.advanceAnimations(0.079)
    let before = scroll.scrollPosition()
    host.advanceAnimations(0.001)
    let current      = scroll.scrollPosition()
    let previousStep = current - before
    scroll.smoothScrollTo({20000, 20000})
    Swag.require(scroll.scrollPosition() == current)
    host.advanceAnimations(0.001)
    let nextStep = scroll.scrollPosition() - current
    Swag.require(Math.abs(nextStep.x - previousStep.x) <= 2)
    Swag.require(Math.abs(nextStep.y - previousStep.y) <= 2)
    let beforeGrowth = scroll.scrollPosition()
    scroll.setScrollSize(120000, 120000)
    Swag.require(scroll.scrollTarget() == Math.Point{20000, 20000})
    host.advanceAnimations(0.001)
    let growthStep = scroll.scrollPosition() - beforeGrowth
    Swag.require(Math.abs(growthStep.x - nextStep.x) <= 2)
    Swag.require(Math.abs(growthStep.y - nextStep.y) <= 2)
    host.finishAnimations()
    Swag.require(scroll.scrollPosition() == Math.Point{20000, 20000})

    // Reversal must not carry forward momentum past the point where the request changed.
    scroll.smoothScrollTo({30000, 30000})
    host.advanceAnimations(0.04)
    let reversal = scroll.scrollPosition()
    scroll.smoothScrollTo({0, 0})
    host.advanceAnimations(0.01)
    Swag.require(scroll.scrollPosition().x < reversal.x and scroll.scrollPosition().y < reversal.y)
    host.finishAnimations()
    Swag.require(scroll.scrollPosition() == Math.Point{0, 0})

    scroll.smoothScrollTo({10000, 10000})
    host.advanceAnimations(0.04)
    scroll.setScrollPos({123, 456})
    host.finishAnimations()
    Swag.require(scroll.scrollPosition() == Math.Point{123, 456})
    host.setReducedMotion(true)
    scroll.smoothScrollTo({789, 987})
    Swag.require(scroll.scrollPosition() == Math.Point{789, 987})
}

var ScrollHeadlessPosCount:  u32
var ScrollHeadlessSizeCount: u32

// Counts one scroll-position notification.
func scrollHeadlessPos(_: *ScrollWnd, _, _: Math.Point)
{
    ScrollHeadlessPosCount += 1
}

// Counts one scroll-size notification.
func scrollHeadlessSize(_: *ScrollWnd, _, _: Math.Point)
{
    ScrollHeadlessSizeCount += 1
}

// Scroll position is clamped to [0 .. scrollSize - visibleSize].
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    ScrollHeadlessPosCount  = 0
    ScrollHeadlessSizeCount = 0

    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.sigScrollPositionChanged += &scrollHeadlessPos
    scroll.sigScrollSizeChanged     += &scrollHeadlessSize

    scroll.setScrollSize(1000, 1000)
    Swag.require(ScrollHeadlessSizeCount == 1)
    Swag.require(scroll.scrollPosition() == Math.Point{0, 0})

    let vc = scroll.view.clientRect()

    // Negative clamps to zero (no change → no signal).
    scroll.setScrollPos(-100, -100)
    Swag.require(scroll.scrollPosition() == Math.Point{0, 0})

    // Beyond the end clamps to scrollSize - visible size.
    scroll.setScrollPos(99999, 99999)
    let sp = scroll.scrollPosition()
    Swag.require(sp.x == 1000 - vc.width)
    Swag.require(sp.y == 1000 - vc.height)
    Swag.require(ScrollHeadlessPosCount >= 1)
}

// Content smaller than the view cannot be scrolled.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.setScrollSize(50, 50)

    scroll.setScrollPos(100, 100)
    Swag.require(scroll.scrollPosition() == Math.Point{0, 0})
}

// Focus reveals a nested control through both viewports, and can return to the first control.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 260)
    let outer = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 300, 200})
    outer.createView'Wnd()
    outer.setScrollSize(900, 900)
    let first = PushButton.create(outer.view, "First", {0, 0, 80, 26})
    let inner = Wnd.create'ScrollWnd(outer.view, "", {500, 500, 200, 140})
    inner.createView'Wnd()
    inner.setScrollSize(800, 800)
    let last = PushButton.create(inner.view, "Last", {600, 600, 80, 26})
    host.pump()

    first.setFocus()
    Swag.require(outer.scrollPosition() == Math.Point{0, 0})
    last.setFocus()
    Swag.require(host.app.keyboardFocusWnd == last)
    Swag.require(inner.scrollPosition().x > 0 and inner.scrollPosition().y > 0)
    Swag.require(outer.scrollPosition().x > 0 and outer.scrollPosition().y > 0)
    Swag.require(inner.view.surfaceRect().contains(last.surfaceRect()))
    Swag.require(outer.view.surfaceRect().contains(last.surfaceRect()))

    let position = outer.scrollPosition()
    last.setFocus()
    Swag.require(outer.scrollPosition() == position)
    first.setFocus()
    Swag.require(outer.scrollPosition() == Math.Point{0, 0})
    Swag.require(outer.view.surfaceRect().contains(first.surfaceRect()))
}

// A viewport type built by composition over a `ScrollWnd`.
struct ScrollHeadlessViewport
{
    using scrollWnd: ScrollWnd
}

// A viewport type built by composition is still a scrolling viewport: focus reveals through it
// exactly as it does through a `ScrollWnd` created by its own type. The reveal walk names the
// ancestor by its runtime type, so an exact comparison would silently skip every derived
// viewport, which is what the standard applications and gui10 are made of.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 260)
    let outer = Wnd.create'ScrollHeadlessViewport(&host.root, "", {0, 0, 300, 200})
    outer.createView'Wnd()
    outer.setScrollSize(900, 900)
    let last = PushButton.create(outer.view, "Last", {600, 600, 80, 26})
    host.pump()

    last.setFocus()
    Swag.require(host.app.keyboardFocusWnd == last)
    Swag.require(outer.scrollPosition().x > 0 and outer.scrollPosition().y > 0)
    Swag.require(outer.view.surfaceRect().contains(last.surfaceRect()))
}

// The bars rest invisible: a scroll shows them, and they fade once the view has been still.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    host.setReducedMotion(false)
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.setScrollSize(1000, 1000)
    host.finishAnimations()
    Swag.require(scroll.barPresence == 0)

    scroll.setScrollPos({0, 100})
    host.finishAnimations()
    Swag.require(scroll.barPresence == 1)

    host.fireTimers()
    host.finishAnimations()
    Swag.require(scroll.barPresence == 0)
}

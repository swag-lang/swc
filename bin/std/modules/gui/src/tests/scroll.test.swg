#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Repeated wheel destinations preserve speed instead of kicking a fresh ease-out each time.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    defer host.shutdown()
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
    Swag.assert(scroll.scrollPosition() == current)
    host.advanceAnimations(0.001)
    let nextStep = scroll.scrollPosition() - current
    Swag.assert(Math.abs(nextStep.x - previousStep.x) <= 2)
    Swag.assert(Math.abs(nextStep.y - previousStep.y) <= 2)
    let beforeGrowth = scroll.scrollPosition()
    scroll.setScrollSize(120000, 120000)
    Swag.assert(scroll.scrollTarget() == Math.Point{20000, 20000})
    host.advanceAnimations(0.001)
    let growthStep = scroll.scrollPosition() - beforeGrowth
    Swag.assert(Math.abs(growthStep.x - nextStep.x) <= 2)
    Swag.assert(Math.abs(growthStep.y - nextStep.y) <= 2)
    host.finishAnimations()
    Swag.assert(scroll.scrollPosition() == Math.Point{20000, 20000})

    // Reversal must not carry forward momentum past the point where the request changed.
    scroll.smoothScrollTo({30000, 30000})
    host.advanceAnimations(0.04)
    let reversal = scroll.scrollPosition()
    scroll.smoothScrollTo({0, 0})
    host.advanceAnimations(0.01)
    Swag.assert(scroll.scrollPosition().x < reversal.x and scroll.scrollPosition().y < reversal.y)
    host.finishAnimations()
    Swag.assert(scroll.scrollPosition() == Math.Point{0, 0})

    scroll.smoothScrollTo({10000, 10000})
    host.advanceAnimations(0.04)
    scroll.setScrollPos({123, 456})
    host.finishAnimations()
    Swag.assert(scroll.scrollPosition() == Math.Point{123, 456})
    host.setReducedMotion(true)
    scroll.smoothScrollTo({789, 987})
    Swag.assert(scroll.scrollPosition() == Math.Point{789, 987})
}

var ScrollHeadlessPosCount:  u32
var ScrollHeadlessSizeCount: u32

func scrollHeadlessPos(s: *ScrollWnd, o, n: Math.Point)
{
    discard s
    discard o
    discard n
    ScrollHeadlessPosCount += 1
}

func scrollHeadlessSize(s: *ScrollWnd, o, n: Math.Point)
{
    discard s
    discard o
    discard n
    ScrollHeadlessSizeCount += 1
}

// Scroll position is clamped to [0 .. scrollSize - visibleSize].
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    defer host.shutdown()
    ScrollHeadlessPosCount  = 0
    ScrollHeadlessSizeCount = 0

    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.sigScrollPositionChanged += &scrollHeadlessPos
    scroll.sigScrollSizeChanged     += &scrollHeadlessSize

    scroll.setScrollSize(1000, 1000)
    Swag.assert(ScrollHeadlessSizeCount == 1)
    Swag.assert(scroll.scrollPosition() == Math.Point{0, 0})

    let vc = scroll.view.clientRect()

    // Negative clamps to zero (no change → no signal).
    scroll.setScrollPos(-100, -100)
    Swag.assert(scroll.scrollPosition() == Math.Point{0, 0})

    // Beyond the end clamps to scrollSize - visible size.
    scroll.setScrollPos(99999, 99999)
    let sp = scroll.scrollPosition()
    Swag.assert(sp.x == 1000 - vc.width)
    Swag.assert(sp.y == 1000 - vc.height)
    Swag.assert(ScrollHeadlessPosCount >= 1)
}

// Content smaller than the view cannot be scrolled.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    defer host.shutdown()
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.setScrollSize(50, 50)

    scroll.setScrollPos(100, 100)
    Swag.assert(scroll.scrollPosition() == Math.Point{0, 0})
}

// Focus reveals a nested control through both viewports, and can return to the first control.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 260)
    defer host.shutdown()
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
    Swag.assert(outer.scrollPosition() == Math.Point{0, 0})
    last.setFocus()
    Swag.assert(host.app.keyboardFocusWnd == last)
    Swag.assert(inner.scrollPosition().x > 0 and inner.scrollPosition().y > 0)
    Swag.assert(outer.scrollPosition().x > 0 and outer.scrollPosition().y > 0)
    Swag.assert(inner.view.surfaceRect().contains(last.surfaceRect()))
    Swag.assert(outer.view.surfaceRect().contains(last.surfaceRect()))

    let position = outer.scrollPosition()
    last.setFocus()
    Swag.assert(outer.scrollPosition() == position)
    first.setFocus()
    Swag.assert(outer.scrollPosition() == Math.Point{0, 0})
    Swag.assert(outer.view.surfaceRect().contains(first.surfaceRect()))
}

// A viewport type built by composition is still a scrolling viewport: focus reveals through it
// exactly as it does through a ScrollWnd created by its own type. The reveal walk names the
// ancestor by its runtime type, so an exact comparison would silently skip every derived
// viewport - which is what the standard applications and gui10 are made of.
struct ScrollHeadlessViewport
{
    using scrollWnd: ScrollWnd
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 260)
    defer host.shutdown()
    let outer = Wnd.create'ScrollHeadlessViewport(&host.root, "", {0, 0, 300, 200})
    outer.createView'Wnd()
    outer.setScrollSize(900, 900)
    let last = PushButton.create(outer.view, "Last", {600, 600, 80, 26})
    host.pump()

    last.setFocus()
    Swag.assert(host.app.keyboardFocusWnd == last)
    Swag.assert(outer.scrollPosition().x > 0 and outer.scrollPosition().y > 0)
    Swag.assert(outer.view.surfaceRect().contains(last.surfaceRect()))
}

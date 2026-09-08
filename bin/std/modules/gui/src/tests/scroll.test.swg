#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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

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

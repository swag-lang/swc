#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

var ScrollHeadlessPosCount:  u32
var ScrollHeadlessSizeCount: u32

func scrollHeadlessPos(s: #nonull *ScrollWnd, o, n: Math.Point)  { discard s; discard o; discard n; ScrollHeadlessPosCount += 1 }
func scrollHeadlessSize(s: #nonull *ScrollWnd, o, n: Math.Point) { discard s; discard o; discard n; ScrollHeadlessSizeCount += 1 }

// Scroll position is clamped to [0 .. scrollSize - visibleSize].
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 260)
    ScrollHeadlessPosCount  = 0
    ScrollHeadlessSizeCount = 0

    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 200, 200})
    scroll.createView'Wnd()
    scroll.sigScrollPosChanged += &scrollHeadlessPos
    scroll.sigScrollSizeChanged += &scrollHeadlessSize

    scroll.setScrollSize(1000, 1000)
    @assert(ScrollHeadlessSizeCount == 1)
    @assert(scroll.getScrollPos() == Math.Point{0, 0})

    let vc = scroll.view.getClientRect()

    // Negative clamps to zero (no change → no signal).
    scroll.setScrollPos(-100, -100)
    @assert(scroll.getScrollPos() == Math.Point{0, 0})

    // Beyond the end clamps to scrollSize - visible size.
    scroll.setScrollPos(99999, 99999)
    let sp = scroll.getScrollPos()
    @assert(sp.x == 1000 - vc.width)
    @assert(sp.y == 1000 - vc.height)
    @assert(ScrollHeadlessPosCount >= 1)

    host.shutdown()
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
    @assert(scroll.getScrollPos() == Math.Point{0, 0})

    host.shutdown()
}

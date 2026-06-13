#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

// StackLayoutCtrl Top stacks children vertically with spacing.
#test
{
    var host: GuiHeadlessHost
    host.setup(220, 320)

    let stack = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 200, 300})
    stack.spacing = 5
    let c0 = Wnd.create'Wnd(stack, null, {0, 0, 200, 40})
    let c1 = Wnd.create'Wnd(stack, null, {0, 0, 200, 40})
    let c2 = Wnd.create'Wnd(stack, null, {0, 0, 200, 40})
    stack.computeLayout()

    @assert(c0.position.y == 0)
    @assert(c1.position.y == 45)
    @assert(c2.position.y == 90)
    @assert(c0.position.width == 200)
    @assert(c0.position.height == 40)

    host.shutdown()
}

// StackLayoutCtrl Left stacks children horizontally with spacing.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 120)

    let stack = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 300, 100})
    stack.spacing = 5
    let c0 = Wnd.create'Wnd(stack, null, {0, 0, 30, 100})
    let c1 = Wnd.create'Wnd(stack, null, {0, 0, 30, 100})
    let c2 = Wnd.create'Wnd(stack, null, {0, 0, 30, 100})
    stack.computeLayout()

    @assert(c0.position.x == 0)
    @assert(c1.position.x == 35)
    @assert(c2.position.x == 70)
    @assert(c0.position.height == 100)
    @assert(c0.position.width == 30)

    host.shutdown()
}

// WrapLayoutCtrl flows fixed-size items left to right, wrapping to new rows.
#test
{
    var host: GuiHeadlessHost
    host.setup(180, 200)

    let wrap = WrapLayoutCtrl.create(&host.root, {0, 0, 150, 200})
    wrap.wrapWidth  = 64
    wrap.wrapHeight = 64
    wrap.spacing    = 5
    let c0 = Wnd.create'Wnd(wrap, null, {0, 0, 0, 0})
    let c1 = Wnd.create'Wnd(wrap, null, {0, 0, 0, 0})
    let c2 = Wnd.create'Wnd(wrap, null, {0, 0, 0, 0})
    wrap.computeLayout()

    @assert(c0.position == Math.Rectangle{0, 0, 64, 64})
    @assert(c1.position == Math.Rectangle{69, 0, 64, 64})
    // The third item no longer fits on the first row and wraps.
    @assert(c2.position == Math.Rectangle{0, 69, 64, 64})

    host.shutdown()
}

// GridLayoutCtrl places children in fixed columns/rows with spacing.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 120)

    let grid = GridLayoutCtrl.create(&host.root, 2, 2, {0, 0, 250, 100})
    grid.spacingHorz = 5
    grid.spacingVert = 5
    // Default colSizes = 100, rowSizes = 30.

    let c00 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    let c10 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    let c01 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    let c11 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})

    grid.setColRowChild(c00, 0, 0)
    grid.setColRowChild(c10, 1, 0)
    grid.setColRowChild(c01, 0, 1)
    grid.setColRowChild(c11, 1, 1)
    grid.computeLayout()

    @assert(c00.position == Math.Rectangle{0, 0, 100, 30})
    @assert(c10.position == Math.Rectangle{105, 0, 100, 30})
    @assert(c01.position == Math.Rectangle{0, 35, 100, 30})
    @assert(c11.position == Math.Rectangle{105, 35, 100, 30})

    host.shutdown()
}

// GridLayoutCtrl supports cells spanning multiple columns.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 120)

    let grid = GridLayoutCtrl.create(&host.root, 2, 2, {0, 0, 250, 100})
    grid.spacingHorz = 5
    grid.spacingVert = 5

    let wide = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    grid.setColRowChild(wide, 0, 0, 2, 1)
    grid.computeLayout()

    // Spanning two 100-wide columns plus the 5px gap between them.
    @assert(wide.position == Math.Rectangle{0, 0, 205, 30})

    host.shutdown()
}

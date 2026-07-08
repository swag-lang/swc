#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

// StackLayoutCtrl Top stacks children vertically with spacing.
#test
{
    var host: Testing.HeadlessHost
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
    var host: Testing.HeadlessHost
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

// StackLayoutCtrl HorzCenter centers children horizontally as a group.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 120)

    let stack = StackLayoutCtrl.create(&host.root, .HorzCenter, {0, 0, 200, 100})
    stack.spacing = 5
    let c0 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    let c1 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    let c2 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    stack.computeLayout()

    // total = 3*40 + 2*5 = 130; start x = 200/2 - 130/2 = 35.
    @assert(c0.position.x == 35)
    @assert(c1.position.x == 80)
    @assert(c2.position.x == 125)

    host.shutdown()
}

// StackLayoutCtrl VertCenter centers children vertically as a group.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 220)

    let stack = StackLayoutCtrl.create(&host.root, .VertCenter, {0, 0, 100, 200})
    stack.spacing = 5
    let c0 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    let c1 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    let c2 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    stack.computeLayout()

    // total = 3*30 + 2*5 = 100; start y = 200/2 - 100/2 = 50.
    @assert(c0.position.y == 50)
    @assert(c1.position.y == 85)
    @assert(c2.position.y == 120)

    host.shutdown()
}

// StackLayoutCtrl distributes remaining space only to expandable children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 240)

    let stack = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 200, 200})
    stack.spacing = 0
    let fixed = Wnd.create'Wnd(stack, null, {0, 0, 200, 40})
    let grow = Wnd.create'Wnd(stack, null, {0, 0, 200, 20})
    grow.layoutSpec.policyY = SizePolicy.Expand
    grow.layoutSpec.weightY = 1
    stack.computeLayout()

    @assert(fixed.position == Math.Rectangle{0, 0, 200, 40})
    @assert(grow.position == Math.Rectangle{0, 40, 200, 160})
    @assert(grow.managedByLayout)
    @assert(grow.layoutDebug.arrangedRect == grow.position)

    host.shutdown()
}

// StackLayoutCtrl honors minSize when available space is too small.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)

    let stack = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 100, 50})
    stack.spacing = 0
    let child = Wnd.create'Wnd(stack, null, {0, 0, 100, 10})
    child.minSize.y = 60
    stack.computeLayout()

    @assert(child.position.height == 60)
    @assert(child.layoutDebug.measuredMin.y == 60)

    host.shutdown()
}

// StackLayoutCtrl propagates layout to arranged children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)

    let stack = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 120, 120})
    stack.spacing = 0
    let line = Wnd.create'Wnd(stack, null, {0, 0, 120, 35})
    let fill = Wnd.create'Wnd(line, null, {0, 0, 0, 0})
    fill.dockStyle = .Center
    stack.computeLayout()

    @assert(fill.position == Math.Rectangle{0, 0, 120, 35})

    line.setPosition({0, 0, 120, 50})
    stack.applyLayout()

    @assert(line.position == Math.Rectangle{0, 0, 120, 50})
    @assert(fill.position == Math.Rectangle{0, 0, 120, 50})

    host.shutdown()
}

// WrapLayoutCtrl flows fixed-size items left to right, wrapping to new rows.
#test
{
    var host: Testing.HeadlessHost
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

// GridLayoutCtrl supports content and fractional tracks.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 120)

    let grid = GridLayoutCtrl.create(&host.root, 3, 1, {0, 0, 300, 80})
    grid.spacingHorz = 0
    grid.setColTrack(0, GridTrackKind.Content)
    grid.setColTrack(1, GridTrackKind.Fraction, 1)
    grid.setColTrack(2, GridTrackKind.Fraction, 2)

    let c0 = Wnd.create'Wnd(grid, null, {0, 0, 60, 30})
    let c1 = Wnd.create'Wnd(grid, null, {0, 0, 0, 30})
    let c2 = Wnd.create'Wnd(grid, null, {0, 0, 0, 30})
    grid.setColRowChild(c0, 0, 0)
    grid.setColRowChild(c1, 1, 0)
    grid.setColRowChild(c2, 2, 0)
    grid.computeLayout()

    @assert(c0.position.width == 60)
    @assert(c1.position.x == 60)
    @assert(Math.abs(c1.position.width - 80) <= 1)
    @assert(Math.abs(c2.position.width - 160) <= 1)

    host.shutdown()
}

// GridLayoutCtrl places children in fixed columns/rows with spacing.
#test
{
    var host: Testing.HeadlessHost
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
    var host: Testing.HeadlessHost
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

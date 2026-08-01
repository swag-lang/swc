#global if #command == Swag.CompilerCommand.Test
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

    let stack = StackLayoutCtrl.create(&host.root, .HorizontalCenter, {0, 0, 200, 100})
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

    let stack = StackLayoutCtrl.create(&host.root, .VerticalCenter, {0, 0, 100, 200})
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
    let grow  = Wnd.create'Wnd(stack, null, {0, 0, 200, 20})
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
    wrap.itemWidth  = 64
    wrap.itemHeight = 64
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
    grid.horizontalSpacing = 0
    grid.setColumnTrack(0, GridTrackKind.Content)
    grid.setColumnTrack(1, GridTrackKind.Fraction, 1)
    grid.setColumnTrack(2, GridTrackKind.Fraction, 2)

    let c0 = Wnd.create'Wnd(grid, null, {0, 0, 60, 30})
    let c1 = Wnd.create'Wnd(grid, null, {0, 0, 0, 30})
    let c2 = Wnd.create'Wnd(grid, null, {0, 0, 0, 30})
    grid.setCell(c0, 0, 0)
    grid.setCell(c1, 1, 0)
    grid.setCell(c2, 2, 0)
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
    grid.horizontalSpacing = 5
    grid.verticalSpacing   = 5

    // Default colSizes = 100, rowSizes = 30.

    let c00 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    let c10 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    let c01 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    let c11 = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})

    grid.setCell(c00, 0, 0)
    grid.setCell(c10, 1, 0)
    grid.setCell(c01, 0, 1)
    grid.setCell(c11, 1, 1)
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
    grid.horizontalSpacing = 5
    grid.verticalSpacing   = 5

    let wide = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    grid.setCell(wide, 0, 0, 2, 1)
    grid.computeLayout()

    // Spanning two 100-wide columns plus the 5px gap between them.
    @assert(wide.position == Math.Rectangle{0, 0, 205, 30})

    host.shutdown()
}

// Fractional tracks redistribute space left unused by a capped track.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 120)

    let grid = GridLayoutCtrl.create(&host.root, 2, 1, {0, 0, 300, 80})
    grid.horizontalSpacing = 0
    grid.setColumnTrack(0, .Fraction, 1, maximum: 50)
    grid.setColumnTrack(1, .Fraction, 1)
    let left  = Wnd.create'Wnd(grid)
    let right = Wnd.create'Wnd(grid)
    grid.setCell(left, 0, 0)
    grid.setCell(right, 1, 0)
    grid.computeLayout()

    @assert(Math.abs(left.position.width - 50) < 0.01)
    @assert(Math.abs(right.position.width - 250) < 0.01)

    host.shutdown()
}

// Reassigning a grid child clears its previous cells.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 100)

    let grid  = GridLayoutCtrl.create(&host.root, 2, 1, {0, 0, 205, 80})
    let child = Wnd.create'Wnd(grid)
    grid.setCell(child, 0, 0)
    grid.computeLayout()
    @assert(child.position.x == 0)

    grid.setCell(child, 1, 0)
    grid.computeLayout()
    @assert(child.position.x == 105)

    host.shutdown()
}

// A wrapping row advances by its tallest item rather than by the next item.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 180)

    let wrap = WrapLayoutCtrl.create(&host.root, {0, 0, 130, 160})
    wrap.spacing = 5
    discard Wnd.create'Wnd(wrap, {0, 0, 80, 20})
    discard Wnd.create'Wnd(wrap, {0, 0, 40, 60})
    let nextRow = Wnd.create'Wnd(wrap, {0, 0, 60, 10})
    wrap.computeLayout()

    @assert(nextRow.position.y == 65)
    @assert(wrap.contentHeight == 75)

    host.shutdown()
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// HorizontalFit keeps each child's minimum while redistributing the remaining space.
#test
{
    var host: Testing.HeadlessHost
    host.setup(140, 80)

    let stack = StackLayoutCtrl.create(&host.root, .HorizontalFit, {0, 0, 100, 40})
    stack.spacing = 0
    let first  = Wnd.create'Wnd(stack, null, {0, 0, 0, 20})
    let second = Wnd.create'Wnd(stack, null, {0, 0, 0, 20})
    first.minSize.x  = 80
    second.minSize.x = 20
    stack.computeLayout()

    Swag.require(first.position.width == 80)
    Swag.require(second.position.width == 20)
    Swag.require(second.position.right() == stack.clientRect().right())
}

// HorizontalFit redistributes space left by a child that reaches its maximum.
#test
{
    var host: Testing.HeadlessHost
    host.setup(140, 80)

    let stack = StackLayoutCtrl.create(&host.root, .HorizontalFit, {0, 0, 100, 40})
    stack.spacing = 0
    let capped = Wnd.create'Wnd(stack, null, {0, 0, 0, 20})
    let flex   = Wnd.create'Wnd(stack, null, {0, 0, 0, 20})
    capped.maxSize.x = 20
    stack.computeLayout()

    Swag.require(capped.position.width == 20)
    Swag.require(flex.position.width == 80)
    Swag.require(flex.position.right() == stack.clientRect().right())
}

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

    Swag.require(c0.position.y == 0)
    Swag.require(c1.position.y == 45)
    Swag.require(c2.position.y == 90)
    Swag.require(c0.position.width == 200)
    Swag.require(c0.position.height == 40)
}

// Relabelling an unsized child rearranges its container without changing the container's bounds.
#test
{
    var rootResizeCount: u32
    var host: Testing.HeadlessHost
    host.setup(520, 100)
    let stack = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 500, 80})
    stack.spacing = 8
    let label = Label.create(stack, "A")
    let next  = PushButton.create(stack, "Next")
    host.pump()
    let before = next.position.x
    let bounds = stack.position
    host.root.hookOnEvent = func|count = &rootResizeCount|(_, evt)
    {
        if evt is ResizeEvent do
            count[] += 1
        return false
    }

    label.setText("A much longer label in the same band")

    // An intervening size query must not consume the pending arrangement.
    discard stack.measure({500, 80})
    host.pump()
    Swag.require(stack.position == bounds)
    Swag.require(rootResizeCount == 0)
    Swag.require(next.position.x > before)
    Swag.require(next.position.x >= label.position.right() + stack.spacing)
    let after = next.position
    host.pump()
    Swag.require(rootResizeCount == 0)
    Swag.require(next.position == after)
}

// Command-supplied labels reflow an unsized button just like an explicitly changed label.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 100)
    let stack  = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 700, 80})
    let button = IconButton.createQuiet(stack, "test.label", menu: false)
    let next   = PushButton.create(stack, "Next")
    button.setText("Copy")
    host.pump()
    let before = next.position.x
    var state: CommandStateEvent
    state.id   = "test.label"
    state.updatedFields = .Name | .Icon
    state.name = "Copy Image to Clipboard"
    state.icon = host.theme.icon(.Copy, 16)
    button.itf.onApplyStateEvent(&state)
    host.pump()
    Swag.require(next.position.x > before)
    Swag.require(button.position.width >= Math.floor(button.itf.measureContent({}).x))
    Swag.require(next.position.x >= button.position.right() + stack.spacing)
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

    Swag.require(c0.position.x == 0)
    Swag.require(c1.position.x == 35)
    Swag.require(c2.position.x == 70)
    Swag.require(c0.position.height == 100)
    Swag.require(c0.position.width == 30)
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
    Swag.require(c0.position.x == 35)
    Swag.require(c1.position.x == 80)
    Swag.require(c2.position.x == 125)
}

// StackLayoutCtrl HorizontalEnd keeps source order and aligns the group to the trailing edge.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 120)
    let stack = StackLayoutCtrl.create(&host.root, .HorizontalEnd, {0, 0, 200, 100})
    stack.spacing = 5
    let c0 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    let c1 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    let c2 = Wnd.create'Wnd(stack, null, {0, 0, 40, 30})
    stack.computeLayout()

    Swag.require(c0.position.x == 70)
    Swag.require(c1.position.x == 115)
    Swag.require(c2.position.x == 160)
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
    Swag.require(c0.position.y == 50)
    Swag.require(c1.position.y == 85)
    Swag.require(c2.position.y == 120)

    // Vertically, and only vertically: the other axis keeps the stack's own edge, so children
    // of different widths read on one left edge instead of on as many as they have widths.
    Swag.require(c0.position.x == 0)
    Swag.require(c1.position.x == 0)
    Swag.require(c2.position.x == 0)

    // Explicit cross-axis expansion still fills the width of a vertically centered form.
    c1.layoutSpec.policyX = .Expand
    stack.computeLayout()
    Swag.require(c1.position.width == 100 and c1.position.y == 85)
    Swag.require(c0.position.width == 40 and c2.position.width == 40)
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

    Swag.require(fixed.position == {0, 0, 200, 40})
    Swag.require(grow.position == {0, 40, 200, 160})
    Swag.require(grow.managedByLayout)
    Swag.require(grow.layoutDebug.arrangedRect == grow.position)
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

    Swag.require(child.position.height == 60)
    Swag.require(child.layoutDebug.measuredMin.y == 60)
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

    Swag.require(fill.position == {0, 0, 120, 35})

    line.setPosition({0, 0, 120, 50})
    stack.applyLayout()

    Swag.require(line.position == {0, 0, 120, 50})
    Swag.require(fill.position == {0, 0, 120, 50})
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

    Swag.require(c0.position == {0, 0, 64, 64})
    Swag.require(c1.position == {69, 0, 64, 64})

    // The third item no longer fits on the first row and wraps.
    Swag.require(c2.position == {0, 69, 64, 64})
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

    Swag.require(c0.position.width == 60)
    Swag.require(c1.position.x == 60)
    Swag.require(Math.abs(c1.position.width - 80) <= 1)
    Swag.require(Math.abs(c2.position.width - 160) <= 1)
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

    Swag.require(c00.position == {0, 0, 100, 30})
    Swag.require(c10.position == {105, 0, 100, 30})
    Swag.require(c01.position == {0, 35, 100, 30})
    Swag.require(c11.position == {105, 35, 100, 30})
}

// Updating a grid track after arrangement repositions its assigned children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 120)
    let grid  = GridLayoutCtrl.create(&host.root, 2, 1, {0, 0, 250, 80})
    let left  = Wnd.create'Wnd(grid)
    let right = Wnd.create'Wnd(grid)
    grid.setCell(left, 0, 0)
    grid.setCell(right, 1, 0)
    host.pump()
    let originalRightX = right.position.x

    grid.setColumnSize(0, 150)
    host.pump()
    Swag.require(right.position.x > originalRightX,
                 Format.toString("Second grid column x after resizing first: expected >%, committed %", originalRightX, right.position.x).toString())
    Swag.require(right.position.x == left.position.right() + grid.horizontalSpacing)
}

// Updating each explicit grid track invalidates deferred arrangement.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 120)

    let columns = GridLayoutCtrl.create(&host.root, 2, 1, {0, 0, 250, 80})
    let left    = Wnd.create'Wnd(columns)
    let right   = Wnd.create'Wnd(columns)
    columns.setCell(left, 0, 0)
    columns.setCell(right, 1, 0)
    host.pump()
    let originalRightX = right.position.x
    columns.setColumnTrack(0, .Fixed, 150)
    host.pump()
    Swag.require(right.position.x > originalRightX)
    Swag.require(right.position.x == left.position.right() + columns.horizontalSpacing)

    let rows   = GridLayoutCtrl.create(&host.root, 1, 2, {0, 0, 250, 80})
    let top    = Wnd.create'Wnd(rows)
    let bottom = Wnd.create'Wnd(rows)
    rows.setCell(top, 0, 0)
    rows.setCell(bottom, 0, 1)
    host.pump()
    let originalBottomY = bottom.position.y
    rows.setRowTrack(0, .Fixed, 50)
    host.pump()
    Swag.require(bottom.position.y > originalBottomY)
    Swag.require(bottom.position.y == top.position.bottom() + rows.verticalSpacing)
}

// Reassigning a cell after arrangement moves the child to its new track.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 120)
    let grid  = GridLayoutCtrl.create(&host.root, 2, 1, {0, 0, 250, 80})
    let child = Wnd.create'Wnd(grid)
    grid.setCell(child, 0, 0)
    host.pump()
    Swag.require(child.position.x == 0)

    grid.setCell(child, 1, 0)
    host.pump()
    Swag.require(child.position.x == 105,
                 Format.toString("Grid child x after reassignment: expected 105, committed %", child.position.x).toString())
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
    Swag.require(wide.position == {0, 0, 205, 30})
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

    Swag.require(Math.abs(left.position.width - 50) < 0.01)
    Swag.require(Math.abs(right.position.width - 250) < 0.01)
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
    Swag.require(child.position.x == 0)

    grid.setCell(child, 1, 0)
    grid.computeLayout()
    Swag.require(child.position.x == 105)
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

    Swag.require(nextRow.position.y == 65)
    Swag.require(wrap.contentHeight == 75)
}

// FormLayoutCtrl arranges typed fields from row descriptions without fixed coordinates.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 320)

    var options: FormLayoutOptions
    options.labelPlacement = .Above
    let form = FormLayoutCtrl.create(&host.root, options, {0, 0, 480, 280})
    form.padding = {12, 10, 12, 10}

    let path   = EditBox.create(form, "")
    let browse = PushButton.create(form, "Browse", {0, 0, 92, 34})
    discard form.addField("CONTAINER FILE", path, browse, "Choose a destination path.")
    let password = PasswordEdit.create(form)
    discard form.addField("PASSWORD", password)
    form.computeLayout()

    Swag.require(form.rows.count == 2)
    Swag.require(form.rows[0].field == path)
    Swag.require(form.rows[0].action == browse)
    Swag.require(form.rows[0].help != null)
    Swag.require(path.position.width > browse.position.width)
    Swag.require(browse.position.x > path.position.x)
    Swag.require(password.position.y > path.position.y)
    Swag.require(form.contentHeight > password.position.y)
}

// FormLayoutCtrl can share one label column across compact dialog fields.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 220)

    var options: FormLayoutOptions
    options.labelPlacement = .Left
    options.labelWidth     = 96
    let form = FormLayoutCtrl.create(&host.root, options, {0, 0, 480, 180})
    let name = EditBox.create(form, "")
    let kind = ComboBox.create(form)
    discard form.addField("File Name", name)
    discard form.addField("Type", kind)
    form.computeLayout()

    Swag.require(name.position.x == 100)
    Swag.require(kind.position.x == name.position.x)
    Swag.require(kind.position.y > name.position.y)
    Swag.require(name.position.width == kind.position.width)
}

// FormLayoutCtrl builders create each field control and return it already typed.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 360)

    let form = FormLayoutCtrl.create(&host.root, position: {0, 0, 480, 320})
    let name = form.addTextField("NAME", "Ada", placeholder: "Display name")
    let pick = form.addRowAction("Choose")
    let size = form.addTextField("SIZE", "256", help: "Capacity of the new container.")
    let unit = form.addRowChoice()
    unit.addItem("MiB", "mib")
    unit.addItem("GiB", "gib")
    unit.setSelectedIndex(1, notify: false)
    let secret = form.addPasswordField("PASSWORD", placeholder: "Required password")
    form.computeLayout()

    Swag.require(form.rows.count == 3)
    Swag.require(name.text() == "Ada")
    Swag.require(unit.selectedIndex == 1)
    Swag.require(form.rows[0].action == pick)
    Swag.require(form.rows[1].action == unit)
    Swag.require(form.rows[1].help != null)
    Swag.require(form.rows[2].action == null)

    // Each builder registers exactly one row, so the fields keep their declaration order.
    Swag.require(size.position.y > name.position.y)
    Swag.require(secret.position.y > size.position.y)
    Swag.require(pick.position.x > name.position.x)
    Swag.require(form.contentHeight > 0)
}

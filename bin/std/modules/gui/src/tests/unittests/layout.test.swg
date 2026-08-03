#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// StackLayoutCtrl Top stacks children vertically with spacing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
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
}

// StackLayoutCtrl Left stacks children horizontally with spacing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    defer host.shutdown()
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
}

// StackLayoutCtrl HorzCenter centers children horizontally as a group.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 120)
    defer host.shutdown()
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
}

// StackLayoutCtrl VertCenter centers children vertically as a group.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 220)
    defer host.shutdown()
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
}

// StackLayoutCtrl distributes remaining space only to expandable children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 240)
    defer host.shutdown()
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
}

// StackLayoutCtrl honors minSize when available space is too small.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    let stack = StackLayoutCtrl.create(&host.root, .Top, {0, 0, 100, 50})
    stack.spacing = 0
    let child = Wnd.create'Wnd(stack, null, {0, 0, 100, 10})
    child.minSize.y = 60
    stack.computeLayout()

    @assert(child.position.height == 60)
    @assert(child.layoutDebug.measuredMin.y == 60)
}

// StackLayoutCtrl propagates layout to arranged children.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
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
}

// WrapLayoutCtrl flows fixed-size items left to right, wrapping to new rows.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 200)
    defer host.shutdown()
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
}

// GridLayoutCtrl supports content and fractional tracks.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 120)
    defer host.shutdown()
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
}

// GridLayoutCtrl places children in fixed columns/rows with spacing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 120)
    defer host.shutdown()
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
}

// GridLayoutCtrl supports cells spanning multiple columns.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 120)
    defer host.shutdown()
    let grid = GridLayoutCtrl.create(&host.root, 2, 2, {0, 0, 250, 100})
    grid.horizontalSpacing = 5
    grid.verticalSpacing   = 5

    let wide = Wnd.create'Wnd(grid, null, {0, 0, 0, 0})
    grid.setCell(wide, 0, 0, 2, 1)
    grid.computeLayout()

    // Spanning two 100-wide columns plus the 5px gap between them.
    @assert(wide.position == Math.Rectangle{0, 0, 205, 30})
}

// Fractional tracks redistribute space left unused by a capped track.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 120)
    defer host.shutdown()
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
}

// Reassigning a grid child clears its previous cells.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 100)
    defer host.shutdown()
    let grid  = GridLayoutCtrl.create(&host.root, 2, 1, {0, 0, 205, 80})
    let child = Wnd.create'Wnd(grid)
    grid.setCell(child, 0, 0)
    grid.computeLayout()
    @assert(child.position.x == 0)

    grid.setCell(child, 1, 0)
    grid.computeLayout()
    @assert(child.position.x == 105)
}

// A wrapping row advances by its tallest item rather than by the next item.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 180)
    defer host.shutdown()
    let wrap = WrapLayoutCtrl.create(&host.root, {0, 0, 130, 160})
    wrap.spacing = 5
    discard Wnd.create'Wnd(wrap, {0, 0, 80, 20})
    discard Wnd.create'Wnd(wrap, {0, 0, 40, 60})
    let nextRow = Wnd.create'Wnd(wrap, {0, 0, 60, 10})
    wrap.computeLayout()

    @assert(nextRow.position.y == 65)
    @assert(wrap.contentHeight == 75)
}

// FormLayoutCtrl arranges typed fields from row descriptions without fixed coordinates.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 320)
    defer host.shutdown()

    var options: FormLayoutOptions
    options.labelPlacement = .Above
    let form = FormLayoutCtrl.create(&host.root, options, {0, 0, 480, 280})
    form.padding = {12, 10, 12, 10}

    let path = EditBox.create(form, "")
    let browse = PushButton.create(form, "Browse", {0, 0, 92, 34})
    discard form.addField("CONTAINER FILE", path, browse, "Choose a destination path.")
    let password = PasswordEdit.create(form)
    discard form.addField("PASSWORD", password)
    form.computeLayout()

    @assert(form.rows.count == 2)
    @assert(form.rows[0].field == path)
    @assert(form.rows[0].action == browse)
    @assert(form.rows[0].help != null)
    @assert(path.position.width > browse.position.width)
    @assert(browse.position.x > path.position.x)
    @assert(password.position.y > path.position.y)
    @assert(form.contentHeight > password.position.y)
}

// FormLayoutCtrl can share one label column across compact dialog fields.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 220)
    defer host.shutdown()

    var options: FormLayoutOptions
    options.labelPlacement = .Left
    options.labelWidth     = 96
    let form = FormLayoutCtrl.create(&host.root, options, {0, 0, 480, 180})
    let name = EditBox.create(form, "")
    let kind = ComboBox.create(form)
    discard form.addField("File Name", name)
    discard form.addField("Type", kind)
    form.computeLayout()

    @assert(name.position.x == 100)
    @assert(kind.position.x == name.position.x)
    @assert(kind.position.y > name.position.y)
    @assert(name.position.width == kind.position.width)
}

// FormCtrl materializes typed fields and optional actions from descriptions.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 320)
    defer host.shutdown()

    var definitions: Array'FormFieldDefinition
    definitions.add({id: "name", label: "NAME", initialText: "Ada",
                     placeholder: "Display name", actionText: "Choose"})
    var size: FormFieldDefinition
    size.id    = "size"
    size.label = "SIZE"
    size.choices.add({"MiB", "mib"})
    size.choices.add({"GiB", "gib"})
    size.selectedIndex = 1
    definitions.add(#move size)
    definitions.add({id: "secret", label: "PASSWORD", kind: FormFieldKind.Password})
    var choice: FormFieldDefinition
    choice.id    = "unit"
    choice.label = "UNIT"
    choice.kind  = .Choice
    choice.choices.add({"MiB", "mib"})
    choice.choices.add({"GiB", "gib"})
    choice.selectedIndex = 1
    definitions.add(#move choice)

    @assert(definitions[1].kind == FormFieldKind.Text)
    @assert(definitions[1].choices.count == 2)
    @assert(@countof(definitions[1].actionText) == 0)

    let form = FormCtrl.create(&host.root, definitions.toSlice(), position: {0, 0, 480, 280})
    @assert(form.fields.count == 4)
    @assert((notnull form.textField("name")).text() == "Ada")
    @assert(form.passwordField("secret") != null)
    @assert((notnull form.choiceField("unit")).selectedIndex == 1)
    @assert(form.textField("unit") == null)
    @assert((notnull form.findField("name")).action != null)
    @assert((notnull (notnull form.findField("size")).accessoryChoice).selectedIndex == 1)
    @assert(form.contentHeight > 0)
}

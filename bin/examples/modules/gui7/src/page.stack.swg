using Core, Gui, Pixel

func addStackButton(parent: *Wnd, text: string, icon: ThemeIcons)
{
    let btn = PushButton.create(parent, text, {0, 0, 150, 32})
    btn.setIcon(app.theme.icon(icon, 16))
}

func createVerticalStack(parent: *Wnd, rect: Math.Rectangle)
{
    let panel = createPanel(parent, "Top stack", "Children keep their own height and are stacked with spacing.", rect)
    let stack = StackLayoutCtrl.create(panel, .Top, {18, 92, rect.width - 36, rect.height - 112})
    stack.spacing = 10
    stack.padding = 4

    addStackButton(stack, "Open workspace", .OpenFile)
    addStackButton(stack, "Save layout", .Save)
    addStackButton(stack, "Duplicate pane", .Duplicate)
    let check = CheckButton.create(stack, "Preserve sidebars", {0, 0, 210, 32})
    check.setState(.Checked)

    stack.computeLayout()
}

func createFitStack(parent: *Wnd, rect: Math.Rectangle)
{
    let panel = createPanel(parent, "Horizontal fit", "HorzFit divides the available width between visible children.", rect)
    let stack = StackLayoutCtrl.create(panel, .HorizontalFit, {18, 96, rect.width - 36, 52})
    stack.spacing = 10
    stack.padding = 2

    addStackButton(stack, "Left", .SendBackward)
    addStackButton(stack, "Center", .BringForward)
    addStackButton(stack, "Right", .BringToFront)
    stack.computeLayout()

    let centered = StackLayoutCtrl.create(panel, .Center, {18, 176, rect.width - 36, 74})
    centered.spacing = 12
    discard createChip(centered, "Undo", .Undo)
    discard createChip(centered, "Redo", .Redo)
    discard createChip(centered, "Export", .Export)
    centered.computeLayout()
}

func createSliderStack(parent: *Wnd, rect: Math.Rectangle)
{
    let panel = createPanel(parent, "Form rows", "A vertical stack hosting composite controls with fixed row heights.", rect)
    let stack = StackLayoutCtrl.create(panel, .Top, {18, 94, rect.width - 36, rect.height - 114})
    stack.spacing = 12

    let width = Math.max(rect.width - 36, 280.0)
    let row1  = SliderCtrl.create(stack, "Left", {0, 0, width, 32})
    row1.setFloatBounds(120, 360)
    row1.setValueWithoutGesture(220)
    let row2 = SliderCtrl.create(stack, "Center", {0, 0, width, 32})
    row2.setFloatBounds(240, 720)
    row2.setValueWithoutGesture(480)
    let row3 = SliderCtrl.create(stack, "Right", {0, 0, width, 32})
    row3.setFloatBounds(160, 420)
    row3.setValueWithoutGesture(260)

    stack.computeLayout()
}

func createStackPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)
    createVerticalStack(parent, layout.left)
    createFitStack(parent, layout.right)
    createSliderStack(parent, layout.bottom)
}

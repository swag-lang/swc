using Core, Gui, Pixel

func createDockLabel(parent: *Wnd, title, text: string, dock: DockStyle, size: Math.Point, margin: Math.Vector4 = {})->*Label
{
    let label = Label.create(parent, Format.toString("<b>%</b>\n%", title, text), {0, 0, size.x, size.y}, null, .WordWrap)
    label.backgroundStyle = .Window
    label.dockStyle = dock
    label.margin = margin
    label.paddingText = {12, 8, 12, 8}
    label.horzAlignmentText = .Left
    label.vertAlignmentText = .Top
    return label
}

func createConstraintsPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)
    let page = createPanel(parent, "Docking and constraints", "Docked children consume the client rectangle in order; center fills the remaining space while min/max sizes clamp panes.", layout.full)

    let host = Wnd.create'Wnd(page, {18, 92, layout.full.width - 36, layout.full.height - 114})
    host.padding = 8

    let topStack = StackLayoutCtrl.create(host, .Left, {0, 0, 0, 56})
    topStack.backgroundStyle = .DialogBar
    topStack.dockStyle = .Top
    topStack.margin = {0, 0, 0, 10}
    topStack.padding = {12, 12, 12, 12}
    topStack.spacing = 8
    discard createChip(topStack, "New", .Plus)
    discard createChip(topStack, "Open", .OpenFile)
    discard createChip(topStack, "Save", .Save)
    topStack.computeLayout()

    discard createDockLabel(host, "Status", "Bottom dock keeps its height; center is recomputed after it.", .Bottom, {0, 52}, {0, 10, 0, 0})

    let left = createDockLabel(host, "Nav", "Left dock with min/max width.", .Left, {170, 0}, {0, 0, 10, 0})
    left.minSize.x = 130
    left.maxSize.x = 210

    let right = createDockLabel(host, "Inspector", "Right dock with clamped width.", .Right, {240, 0}, {10, 0, 0, 0})
    right.minSize.x = 180
    right.maxSize.x = 280

    let center = Wnd.create'Wnd(host, {0, 0, 260, 160})
    center.backgroundStyle = .View
    center.dockStyle = .Center
    center.margin = 0

    host.sendResizeEvent()

    discard createText(center, "Anchored center", {14, 12, Math.max(center.position.width - 28, 120.0), 24})
    discard createHelpText(center, "The center pane fills the remaining rectangle. The action button keeps its distance to the bottom-right corner.", {14, 42, Math.max(center.position.width - 28, 120.0), 46})

    let actionX = Math.max(center.position.width - 190, 14.0)
    let actionY = Math.max(center.position.height - 54, 96.0)
    let action = PushButton.create(center, "Anchored action", {actionX, actionY, 170, 34})
    action.icon = app.theme.getIcon24(.Link, 18)
    action.anchorStyle = .X | .Y

    let stretch = Label.create(center, "Anchored width + height", {14, 100, Math.max(center.position.width - 220, 160.0), Math.max(center.position.height - 168, 40.0)}, null, .WordWrap | .LightText)
    stretch.anchorStyle = .Width | .Height
    stretch.setText("This label grows with the center pane and keeps its top-left origin.")

    center.sendResizeEvent()
}

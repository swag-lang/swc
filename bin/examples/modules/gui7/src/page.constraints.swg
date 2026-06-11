using Core, Gui, Pixel

func createDockPane(parent: *Wnd, title, text: string, dock: DockStyle, size: Math.Point, margin: Math.Vector4 = {})->*FrameWnd
{
    let pane = createPane(parent, title, text)
    pane.dockStyle = dock
    pane.position.width = size.x
    pane.position.height = size.y
    pane.margin = margin
    return pane
}

func createConstraintsPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)
    let page = createPanel(parent, "Docking and constraints", "Docked children consume the client rectangle in order; center fills the remaining space while min/max sizes clamp panes.", layout.full)

    let host = Wnd.create'Wnd(page, {18, 92, layout.full.width - 36, layout.full.height - 114})
    host.padding = 8

    let top = createDockPane(host, "Toolbar", "Top dock keeps its height.", .Top, {0, 52}, {0, 0, 0, 10})
    top.maxSize.x = 720
    let topStack = StackLayoutCtrl.create(top.view, .Left, {12, 10, 520, 32})
    topStack.spacing = 8
    discard createChip(topStack, "New", .Plus)
    discard createChip(topStack, "Open", .OpenFile)
    discard createChip(topStack, "Save", .Save)
    topStack.computeLayout()

    let bottom = createDockPane(host, "Status", "Bottom dock consumes the last strip.", .Bottom, {0, 44}, {0, 10, 0, 0})
    discard createHelpText(bottom.view, "bottom dock keeps its height; center view is recomputed after it.", {12, 28, 520, 20})

    let left = createDockPane(host, "Nav", "Left dock with min/max width.", .Left, {170, 0}, {0, 0, 10, 0})
    left.minSize.x = 130
    left.maxSize.x = 210

    let right = createDockPane(host, "Inspector", "Right dock with clamped width.", .Right, {240, 0}, {10, 0, 0, 0})
    right.minSize.x = 180
    right.maxSize.x = 280

    let center = createPane(host, "Anchored center", "The center pane fills the remaining rectangle. The action button keeps its distance to the bottom-right corner.")
    center.dockStyle = .Center
    let action = PushButton.create(center.view, "Anchored action", {260, 150, 170, 34})
    action.icon = app.theme.getIcon24(.Link, 18)
    action.anchorStyle = .X | .Y

    let stretch = Label.create(center.view, "Anchored width + height", {14, 98, 260, 40}, null, .WordWrap | .LightText)
    stretch.anchorStyle = .Width | .Height
    stretch.setText("This label grows with the center pane and keeps its top-left origin.")

    host.sendResizeEvent()
}

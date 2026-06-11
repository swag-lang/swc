using Core, Gui, Pixel

func createSplitterPane(parent: *Wnd, title, text: string)->*FrameWnd
{
    let pane = createPane(parent, title, text)
    let view = pane.view
    let focus = createChip(view, "Focus", .Search)
    focus.setPosition({12, 96, 94, 30})
    let pin = createChip(view, "Pin", .Link)
    pin.setPosition({112, 96, 82, 30})
    return pane
}

func createSplitterPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)
    let page = createPanel(parent, "Nested splitters", "Drag the vertical and horizontal bars; side panes keep useful minimum sizes while the editor area absorbs most resize changes.", layout.full)

    let splitRect = Math.Rectangle{18, 90, layout.full.width - 36, layout.full.height - 112}
    let rootSplit = SplitterCtrl.create(page, splitRect)

    let nav = createSplitterPane(rootSplit, "Navigator", "Preserved side pane. min 170, max 280.")
    let navItem = rootSplit.addPane(nav, 230)
    navItem.minSize = 170
    navItem.maxSize = 280
    navItem.tryPreserveSize = true

    let work = Wnd.create'Wnd(rootSplit, {})
    let workItem = rootSplit.addPane(work, 520)
    workItem.minSize = 320

    let inspector = createSplitterPane(rootSplit, "Inspector", "Right pane tries to preserve its width.")
    let inspectorItem = rootSplit.addPane(inspector, 250)
    inspectorItem.minSize = 190
    inspectorItem.maxSize = 340
    inspectorItem.tryPreserveSize = true

    let vertical = SplitterCtrl.create(work, {}, vertical: true)
    vertical.dockStyle = .Center

    let editor = createSplitterPane(vertical, "Document", "Center region nested inside a vertical splitter.")
    let editorItem = vertical.addPane(editor, 330)
    editorItem.minSize = 190

    let console = createSplitterPane(vertical, "Output", "Bottom pane has a compact min size.")
    let consoleItem = vertical.addPane(console, 150)
    consoleItem.minSize = 92
    consoleItem.tryPreserveSize = true

    rootSplit.sendResizeEvent()
    vertical.sendResizeEvent()
}

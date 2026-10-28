using Core, Gui, Pixel

func createSplitterPane(parent: *Wnd, title, text: string)->*Wnd
{
    let pane  = createPane(parent, title, text)
    let focus = createChip(pane, "Focus", .Search)
    focus.setPosition({12, 96, 94, 30})
    let pin = createChip(pane, "Pin", .Link)
    pin.setPosition({112, 96, 82, 30})
    return pane
}

func createSplitterPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)
    let page   = createPanel(parent,
                             "Nested splitters",
                             "Drag the bars: the side panes keep their minimum sizes while the middle takes most of a resize.",
                             layout.full)

    let splitRect = Math.Rectangle{SectionInset, 88, layout.full.width - 2 * SectionInset, layout.full.height - 88}
    let rootSplit = SplitterCtrl.create(page, splitRect)

    let nav     = createSplitterPane(rootSplit, "Navigator", "Keeps its width, between 170 and 280.")
    let navItem = rootSplit.addPane(nav, 230)
    navItem.minimumSize  = 170
    navItem.maximumSize  = 280
    navItem.preserveSize = true

    let work     = Wnd.create'Wnd(rootSplit, {})
    let workItem = rootSplit.addPane(work, 520)
    workItem.minimumSize = 320

    let inspector = createSplitterPane(rootSplit, "Inspector", "Right pane tries to preserve its width.")
    with let inspectorItem = rootSplit.addPane(inspector, 250)
    {
        .minimumSize  = 190
        .maximumSize  = 340
        .preserveSize = true
    }

    let vertical = SplitterCtrl.create(work, {}, vertical: true)
    vertical.dockStyle = .Center

    let editor     = createSplitterPane(vertical, "Document", "Center region nested inside a vertical splitter.")
    let editorItem = vertical.addPane(editor, 330)
    editorItem.minimumSize = 190

    let console     = createSplitterPane(vertical, "Output", "Bottom pane has a compact min size.")
    let consoleItem = vertical.addPane(console, 150)
    consoleItem.minimumSize  = 92
    consoleItem.preserveSize = true

    rootSplit.sendResizeEvent()
    vertical.sendResizeEvent()
}

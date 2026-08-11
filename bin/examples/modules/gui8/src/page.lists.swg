using Core, Gui, Pixel

func createListsPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left   = createPanel(parent, "Simple ListCtrl", "Single-column rows with icons, hot tracking and multi-selection.", layout.left)
    let simple = ListCtrl.createSimple(left, {18, 92, layout.left.width - 36, layout.left.height - 112})
    simple.setFrameForm(.Round)
    simple.frameFlags.add(.FocusBorder)
    simple.updateFlags(.HotTrack)
    simple.setSelectionMode(.Multi)
    simple.setIconSize(16)
    for i in 24 do
        discard simple.createLine(Format.toString("Inbox item %", i + 1), sampleIcon(i))
    simple.computeLayout()

    let right       = createPanel(parent, "Virtual list", "A million logical rows filled on demand by onFillVirtualLine.", layout.right)
    let virtualList = ListCtrl.createSimple(right, {18, 92, layout.right.width - 36, layout.right.height - 112})
    virtualList.setFrameForm(.Round)
    virtualList.setSelectionMode(.Single)
    virtualList.setIconSize(16)
    virtualList.setHorizontalExtent(620)
    virtualList.onFillVirtualLine = func(list, line, idx)
    {
        if line == null do
            return
        line.setItem(0, Format.toString("virtual result %     cache line %", idx, idx % 64), sampleIcon(cast(s32) idx))
    }
    virtualList.setVirtualCount(1_000_000)

    let bottom = createPanel(parent, "Checkable rows", "Rows can carry independent check state while preserving list navigation.", layout.bottom)
    let checks = ListCtrl.createSimple(bottom, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
    checks.setFrameForm(.Square)
    checks.setSelectionMode(.Multi)
    checks.setIconSize(16)
    addListFlags(checks)
    for i in 14
    {
        let line = checks.createLine(Format.toString("pipeline step %", i + 1), sampleIcon(i + 2))
        line.canCheck = true
        if i == 1 or i == 5 or i == 9 do
            checks.setLineChecked(line, notify: false)
    }

    checks.computeLayout()
}

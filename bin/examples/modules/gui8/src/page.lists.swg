using Core, Gui, Pixel

func createListsPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left = createPanel(parent,
                           "Simple ListCtrl",
                           "Single-column rows with icons, hot tracking and multi-selection.",
                           layout.left)
    with let simple = ListCtrl.createSimple(left,
                                            Math.Rectangle{SectionInset, 88, layout.left.width - 2 * SectionInset, layout.left.height - 88})
    {
        .setFrameForm(.Round)
        .frameFlags.add(.FocusBorder)
        .updateFlags(.HotTrack)
        .setSelectionMode(.Multi)
        .setIconSize(16)
    }

    for i in 24 do
        discard simple.createLine(Format.toString("Inbox item %", i + 1), sampleIcon(i))
    simple.computeLayout()

    let right = createPanel(parent,
                            "Virtual list",
                            "A million logical rows filled on demand by onFillVirtualLine.",
                            layout.right)
    let virtualList = ListCtrl.createSimple(right,
                                            Math.Rectangle{SectionInset, 88, layout.right.width - 2 * SectionInset, layout.right.height - 88})
    virtualList.setFrameForm(.Round)
    virtualList.setSelectionMode(.Single)
    virtualList.setIconSize(16)
    virtualList.setHorizontalExtent(620)
    virtualList.onFillVirtualLine = func(_, line, idx)
    {
        if line == null do
            return
        line.setItem(0,
                     Format.toString("virtual result %     cache line %", idx, idx % 64),
                     sampleIcon(cast(s32, idx)))
    }

    virtualList.setVirtualCount(1_000_000)

    let bottom = createPanel(parent,
                             "Checkable rows",
                             "Rows can carry independent check state while preserving list navigation.",
                             layout.bottom)
    let checks = ListCtrl.createSimple(bottom,
                                       Math.Rectangle{SectionInset, 88, layout.bottom.width - 2 * SectionInset, layout.bottom.height - 88})
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

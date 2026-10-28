using Core, Gui, Pixel

func createContextMenuModel(parent: *Wnd)
{
    let ctxMenu = createTrackedPopup(parent)
    g_ContextMenu = ctxMenu
    ctxMenu.addItem("Inspect", MenuCmd.ContextInspect, app.theme.icon(.Search, 16))
    ctxMenu.addItem("Rename", MenuCmd.ContextRename, app.theme.icon(.Edit, 16))
    ctxMenu.addItem("Pin Item", MenuCmd.ContextPin, app.theme.icon(.Link, 16))
    ctxMenu.addSeparator()

    with let alignMenu = createTrackedPopup(parent)
    {
        .addItem("Align Left", MenuCmd.AlignLeft)
        .addItem("Align Center", MenuCmd.AlignCenter)
        .addItem("Align Right", MenuCmd.AlignRight)
    }

    ctxMenu.addPopup("Align", alignMenu)

    ctxMenu.addSeparator()
    ctxMenu.addItem("Archive", MenuCmd.ContextArchive, app.theme.icon(.Download, 16))
    ctxMenu.addItem("Delete", MenuCmd.ContextDelete, app.theme.icon(.Remove, 16))
}

func showContextMenuAt(pt: Math.Point)
{
    let menu = g_ContextMenu
    if not menu do
        return

    discard menu.doModal(pt)
}

func onContextCanvasEvent(view: *Wnd, evt: IEvent)->bool
{
    if evt is MouseEvent as mouse where mouse.kind == .Accept
    {
        mouse.accepted = true
        return true
    }
    elif evt is MouseEvent as mouse where mouse.kind == .Released and mouse.button == .Right
    {
        showContextMenuAt(mouse.surfacePos)
        return true
    }
    elif evt is PaintEvent as paintEvt
    {
        let painter   = paintEvt.paintContext.painter
        let rect      = view.clientRect()
        let colors    = view.themeColors()
        let font      = view.theme().createDefaultFont(15)
        let titleFont = view.theme().createDefaultFont(20, .Bold)

        // The target is the raised ground a right click lands on; nothing else marks it.
        let corner = view.themeMetrics().corner_Control
        let card   = rect
        painter.fillRoundRect(card, corner, corner, colors.raised)
        painter.drawString(card.x + 28, card.y + 28, "Right-Click Here", titleFont, colors.text)
        drawWrappedText(painter,
                        Math.Rectangle{card.x + 28, card.y + 72, card.width - 56, 56},
                        "A right click here, or one of the buttons, opens the same context menu at different anchors.",
                        font,
                        colors.softText,
                        2)
        drawStatePill(painter,
                      Math.Rectangle{card.x + 28, card.y + 130, 132, 34},
                      g_ContextPinned ? "pinned" : "unpinned",
                      g_ContextPinned,
                      font,
                      colors)
        drawStatePill(painter,
                      Math.Rectangle{card.x + 176, card.y + 130, 132, 34},
                      Format.toString("delete %", boolWord(not g_ContextPinned)),
                      not g_ContextPinned,
                      font,
                      colors)
    }

    return false
}

func createContextMenuPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    createContextMenuModel(parent)

    let left   = createPanel(parent, "Context surface", "The menu is reusable and can be opened from the canvas or command buttons.", layout.left)
    let canvas = Wnd.create'Wnd(left, Math.Rectangle{SectionInset, 88, layout.left.width - 2 * SectionInset, layout.left.height - 88})
    canvas.hookOnEvent = &onContextCanvasEvent

    let right = createPanel(parent,
                            "Launch points",
                            "The same menu can be shown at raw mouse coordinates or anchored near controls.",
                            layout.right)
    let openBtn = PushButton.create(right, "Open at Button", {24, 88, 220})
    openBtn.setIcon(app.theme.icon(.More, 16))
    openBtn.sigPressed += func(btn)
    {
        let pos = btn.surfaceRect()
        showContextMenuAt(Math.Point{pos.x, pos.bottom() + 6})
    }

    let inspectBtn = PushButton.create(right, "Open Centered", {24, 136, 220})
    inspectBtn.setIcon(app.theme.icon(.Search, 16))
    inspectBtn.sigPressed += func(btn)
    {
        let pos = btn.surfaceRect()
        showContextMenuAt(Math.Point{pos.horzCenter(), pos.vertCenter()})
    }

    discard createActionButton(right, "Toggle Pin State", {24, 196, 220}, MenuCmd.ContextPin, .Link)
    discard createActionButton(right, "Try Delete Command", {24, 244, 220}, MenuCmd.ContextDelete, .Remove)

    createStatusPanel(parent, layout.bottom)
}

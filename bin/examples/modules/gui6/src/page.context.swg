using Core, Gui, Pixel

func createContextMenuModel(parent: *Wnd)
{
    let ctxMenu = createTrackedPopup(parent)
    g_ContextMenu = ctxMenu
    ctxMenu.addItem("Inspect", MenuCmd.ContextInspect, app.theme.icon(.Search, 18))
    ctxMenu.addItem("Rename", MenuCmd.ContextRename, app.theme.icon(.Edit, 18))
    ctxMenu.addItem("Pin item", MenuCmd.ContextPin, app.theme.icon(.Link, 18))
    ctxMenu.addSeparator()

    with let alignMenu = createTrackedPopup(parent)
    {
        .addItem("Align left", MenuCmd.AlignLeft)
        .addItem("Align center", MenuCmd.AlignCenter)
        .addItem("Align right", MenuCmd.AlignRight)
    }

    ctxMenu.addPopup("Align", alignMenu)

    ctxMenu.addSeparator()
    ctxMenu.addItem("Archive", MenuCmd.ContextArchive, app.theme.icon(.Download, 18))
    ctxMenu.addItem("Delete", MenuCmd.ContextDelete, app.theme.icon(.Remove, 18))
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

        painter.fillRoundRect(rect, 8, 8, colors.ground)
        let card = Math.Rectangle{20, 16, rect.width - 40, rect.height - 32}
        painter.drawString(card.x, card.y + 4, "Right-click target", titleFont, colors.text)
        drawWrappedText(painter,
                        Math.Rectangle{card.x, card.y + 42, card.width, 56},
                        "Right-click this panel or use the buttons to open the same context menu at different anchors.",
                        font,
                        colors.softText,
                        2)
        drawStatePill(painter,
                      Math.Rectangle{card.x, card.y + 106, 132, 32},
                      g_ContextPinned ? "Pinned" : "Unpinned",
                      g_ContextPinned,
                      font,
                      colors)
        drawStatePill(painter,
                      Math.Rectangle{card.x + 144, card.y + 106, 132, 32},
                      Format.toString("Delete %", boolWord(not g_ContextPinned)),
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
    let canvas = Wnd.create'Wnd(left, Math.Rectangle{18, 86, layout.left.width - 36, layout.left.height - 104})
    canvas.hookOnEvent = &onContextCanvasEvent

    let right = createPanel(parent,
                            "Launch points",
                            "The same menu can be shown at raw mouse coordinates or anchored near controls.",
                            layout.right)
    let openBtn = PushButton.create(right, "Open at button", {24, 100, 220})
    openBtn.setIcon(app.theme.icon(.More, 18))
    openBtn.sigPressed += func(btn)
    {
        let pos = btn.surfaceRect()
        showContextMenuAt(Math.Point{pos.x, pos.bottom() + 6})
    }

    let inspectBtn = PushButton.create(right, "Open centered", {24, 154, 220})
    inspectBtn.setIcon(app.theme.icon(.Search, 18))
    inspectBtn.sigPressed += func(btn)
    {
        let pos = btn.surfaceRect()
        showContextMenuAt(Math.Point{pos.horzCenter(), pos.vertCenter()})
    }

    discard createActionButton(right, "Toggle pin state", {24, 224, 220}, MenuCmd.ContextPin, .Link)
    discard createActionButton(right, "Try delete command", {24, 278, 220}, MenuCmd.ContextDelete, .Remove)

    createStatusPanel(parent, layout.bottom)
}

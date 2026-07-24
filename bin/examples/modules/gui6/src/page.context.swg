using Core, Gui, Pixel

func createContextMenuModel(parent: *Wnd)
{
    let ctxMenu = createTrackedPopup(parent)
    g_ContextMenu = ctxMenu
    ctxMenu.addItem("Inspect", MenuCmd.ContextInspect, app.theme.getIcon24(.Search, 18))
    ctxMenu.addItem("Rename", MenuCmd.ContextRename, app.theme.getIcon24(.Edit, 18))
    ctxMenu.addItem("Pin item", MenuCmd.ContextPin, app.theme.getIcon24(.Link, 18))
    ctxMenu.addSeparator()

    let alignMenu = createTrackedPopup(parent)
    alignMenu.addItem("Align left", MenuCmd.AlignLeft)
    alignMenu.addItem("Align center", MenuCmd.AlignCenter)
    alignMenu.addItem("Align right", MenuCmd.AlignRight)
    ctxMenu.addPopup("Align", alignMenu)

    ctxMenu.addSeparator()
    ctxMenu.addItem("Archive", MenuCmd.ContextArchive, app.theme.getIcon24(.Download, 18))
    ctxMenu.addItem("Delete", MenuCmd.ContextDelete, app.theme.getIcon24(.Remove, 18))
}

func showContextMenuAt(pt: Math.Point)
{
    let menu = g_ContextMenu
    if !menu do
        return

    discard menu.doModal(pt)
}

func onContextCanvasEvent(view: *Wnd, evt: IEvent)->bool
{
    if let mouse = evt as MouseEvent where mouse.kind == .MouseAccept
    {
        mouse.accepted = true
        return true
    }
    elif let mouse = evt as MouseEvent where mouse.kind == .MouseReleased and mouse.button == .Right
    {
        showContextMenuAt(mouse.surfacePos)
        return true
    }
    elif let paintEvt = evt as PaintEvent
    {
        let painter = paintEvt.bc.painter
        let rect = view.getClientRect()
        let colors = view.getThemeColors()
        let font = view.getTheme().createDefaultFont(15)
        let titleFont = view.getTheme().createDefaultFont(20, .Bold)

        painter.fillRect(rect, colors.view_Bk)
        let card = Math.Rectangle{24, 24, Math.max(rect.width - 48, 1.0), Math.max(rect.height - 48, 1.0)}
        painter.fillRoundRect(card, 22, 22, Color.fromArgb(255, 246, 248, 250))
        painter.drawRoundRect(card, 22, 22, Color.fromArgb(70'u8, Argb.Black), 1)
        painter.drawString(card.x + 28, card.y + 28, "Right-click target", titleFont, Argb.DarkSlateGray)
        drawWrappedText(painter, {card.x + 28, card.y + 72, card.width - 56, 56}, "Right-click this panel or use the buttons to open the same context menu at different anchors.", font, Argb.DimGray, 2)
        drawStatePill(painter, {card.x + 28, card.y + 130, 132, 34}, g_ContextPinned ? "pinned" : "unpinned", g_ContextPinned, font, colors)
        drawStatePill(painter, {card.x + 176, card.y + 130, 132, 34}, Format.toString("delete %", boolWord(!g_ContextPinned)), !g_ContextPinned, font, colors)
    }

    return false
}

func createContextMenuPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    createContextMenuModel(parent)

    let left = createPanel(parent, "Context surface", "The menu is reusable and can be opened from the canvas or command buttons.", layout.left)
    let canvas = Wnd.create'Wnd(left, {18, 86, layout.left.width - 36, layout.left.height - 104})
    canvas.hookOnEvent = &onContextCanvasEvent

    let right = createPanel(parent, "Launch points", "The same menu can be shown at raw mouse coordinates or anchored near controls.", layout.right)
    let openBtn = PushButton.create(right, "Open at button", {24, 100, 220})
    openBtn.icon       = app.theme.getIcon24(.More, 18)
    openBtn.sigPressed += func(btn)
    {
        let pos = btn.getSurfaceRect()
        showContextMenuAt({pos.x, pos.bottom() + 6})
    }

    let inspectBtn = PushButton.create(right, "Open centered", {24, 154, 220})
    inspectBtn.icon       = app.theme.getIcon24(.Search, 18)
    inspectBtn.sigPressed += func(btn)
    {
        let pos = btn.getSurfaceRect()
        showContextMenuAt({pos.horzCenter(), pos.vertCenter()})
    }

    discard createActionButton(right, "Toggle pin state", {24, 224, 220}, MenuCmd.ContextPin, .Link)
    discard createActionButton(right, "Try delete command", {24, 278, 220}, MenuCmd.ContextDelete, .Remove)

    createStatusPanel(parent, layout.bottom)
}

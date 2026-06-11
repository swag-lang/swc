using Core, Gui, Pixel

func createTransientAnchorMenu(parent: *Wnd)->*MenuCtrl
{
    let menu = MenuCtrl.createPopup(parent, owner: g_View)
    menu.menuCtrlFlags |= .NoKeyShortcuts
    menu.addItem("Compact cards", MenuCmd.ModeCompact)
    menu.addItem("Detailed cards", MenuCmd.ModeDetailed)
    menu.addItem("Column layout", MenuCmd.ModeColumns)
    menu.addSeparator()
    menu.addItem("Light theme", MenuCmd.ThemeLight)
    menu.addItem("Dark theme", MenuCmd.ThemeDark)
    return menu
}

func showAnchorMenu(btn: *Button, pos: PopupPos)
{
    let menu = createTransientAnchorMenu(btn)
    let rect = btn.getSurfaceRect()
    var pt: Math.Point
    switch pos
    {
    case AnchorTopCenter:
        pt = {rect.horzCenter(), rect.bottom()}
    case AnchorBottomCenter:
        pt = {rect.horzCenter(), rect.y}
    default:
        pt = {rect.x, rect.bottom()}
    }

    discard menu.doModal(pt, pos, autoDestroy: true)
}

func createAnchoredPopupPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent, "Toolbar anchors", "AnchorTopCenter and AnchorBottomCenter make compact menus feel attached to toolbar buttons.", layout.left)
    let topBtn = PushButton.create(left, "Open below", {24, 112, 200})
    topBtn.form = .Default
    topBtn.icon = app.theme.getIcon24(.BottomPopupArrow, 18)
    topBtn.sigPressed += func(btn) { showAnchorMenu(btn, .AnchorTopCenter); }

    let bottomBtn = PushButton.create(left, "Open above", {246, 112, 200})
    bottomBtn.icon = app.theme.getIcon24(.SortArrowUp, 18)
    bottomBtn.sigPressed += func(btn) { showAnchorMenu(btn, .AnchorBottomCenter); }

    let plainBtn = PushButton.create(left, "Plain popup", {24, 178, 200})
    plainBtn.icon = app.theme.getIcon24(.More, 18)
    plainBtn.sigPressed += func(btn) { showAnchorMenu(btn, .TopLeft); }

    discard createActionButton(left, "Switch to columns", {246, 178, 200}, MenuCmd.ModeColumns, .Sort)

    let right = createPanel(parent, "Current selection", "Anchored popups reuse the same commands as the menu bar and state page.", layout.right)
    g_Preview = createPreview(right, {18, 86, layout.right.width - 36, layout.right.height - 104})

    createStatusPanel(parent, layout.bottom)
}

using Core, Gui, Pixel

func createTransientAnchorMenu(parent: *Wnd)->*MenuCtrl
{
    let menu = MenuCtrl.createPopup(parent, owner: g_View)
    menu.updateFlags(.HideShortcuts)
    menu.addItem("Compact Cards", MenuCmd.ModeCompact)
    menu.addItem("Detailed Cards", MenuCmd.ModeDetailed)
    menu.addItem("Column Layout", MenuCmd.ModeColumns)
    menu.addSeparator()
    menu.addItem("Light Theme", MenuCmd.ThemeLight)
    menu.addItem("Dark Theme", MenuCmd.ThemeDark)
    return menu
}

func showAnchorMenu(btn: *Button, pos: PopupPosition)
{
    let menu = createTransientAnchorMenu(btn)
    let rect = btn.surfaceRect()
    var pt: Math.Point
    switch pos
    {
    case .AnchorTopCenter:    pt = Math.Point{rect.horzCenter(), rect.bottom()}
    case .AnchorBottomCenter: pt = Math.Point{rect.horzCenter(), rect.y}
    default: pt = Math.Point{rect.x, rect.bottom()}
    }

    discard menu.doModal(pt, pos, autoDestroy: true)
}

func createAnchoredPopupPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent,
                           "Button anchors",
                           "AnchorTopCenter and AnchorBottomCenter keep a small menu joined to the button it leaves.",
                           layout.left)
    let topBtn = PushButton.create(left, "Open Below", {24, 88, 200})
    topBtn.setForm(.Default)
    topBtn.setIcon(app.theme.icon(.ChevronDown, 16))
    topBtn.sigPressed += func(btn) { showAnchorMenu(btn, .AnchorTopCenter); }

    let bottomBtn = PushButton.create(left, "Open Above", {250, 88, 200})
    bottomBtn.setIcon(app.theme.icon(.ChevronUp, 16))
    bottomBtn.sigPressed += func(btn) { showAnchorMenu(btn, .AnchorBottomCenter); }

    let plainBtn = PushButton.create(left, "Plain Popup", {24, 144, 200})
    plainBtn.setIcon(app.theme.icon(.More, 16))
    plainBtn.sigPressed += func(btn) { showAnchorMenu(btn, .TopLeft); }

    discard createActionButton(left, "Switch to Columns", {250, 144, 200}, MenuCmd.ModeColumns, .Sort)

    let right = createPanel(parent,
                            "Current selection",
                            "Anchored popups reuse the same commands as the menu bar and state page.",
                            layout.right)
    g_Preview = createPreview(right)

    createStatusPanel(parent, layout.bottom)
}

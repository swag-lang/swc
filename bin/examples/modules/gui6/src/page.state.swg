using Core, Gui, Pixel

func createStateMenuModel(parent: *Wnd)
{
    let stateMenu = createTrackedPopup(parent)
    g_StateMenu = stateMenu
    addViewItems(stateMenu)
    stateMenu.addSeparator()
    addThemeItems(stateMenu)
    stateMenu.addSeparator()
    addDocumentItems(stateMenu)
}

func showStateMenuFrom(btn: *Button)
{
    let stateMenu = g_StateMenu
    if not stateMenu do
        return

    let pos = btn.surfaceRect()
    discard stateMenu.doModal(Math.Point{pos.horzCenter(), pos.bottom() + 8}, .AnchorTopCenter)
}

func createCommandStatePage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    createStateMenuModel(parent)

    let left = createPanel(parent,
                           "Computed rows",
                           "Open the menu to inspect check marks, radio groups and disabled save/undo/redo rows.",
                           layout.left)
    let stateBtn = PushButton.create(left, "Open State Menu", {24, 88, 230})
    stateBtn.setForm(.Default)
    stateBtn.setIcon(app.theme.icon(.Options, 16))
    stateBtn.sigPressed += &showStateMenuFrom

    discard createActionButton(left, "Toggle Grid", {24, 144, 230}, MenuCmd.ToggleGrid, .Options)
    discard createActionButton(left, "Toggle Guides", {24, 192, 230}, MenuCmd.ToggleGuides, .Options)
    discard createActionButton(left, "Save", {24, 240, 230}, MenuCmd.SaveFile, .Save)

    let right = createPanel(parent,
                            "State preview",
                            "Buttons and menus listen to the same command state source, so disabled and checked states stay consistent.",
                            layout.right)
    g_Preview = createPreview(right)

    createStatusPanel(parent, layout.bottom)
}

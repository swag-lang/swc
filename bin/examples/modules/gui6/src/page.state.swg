using Core, Gui, Pixel

func createStateMenuModel(parent: *Wnd)
{
    g_StateMenu = createTrackedPopup(parent)
    addViewItems(notnull g_StateMenu)
    g_StateMenu.addSeparator()
    addThemeItems(notnull g_StateMenu)
    g_StateMenu.addSeparator()
    addDocumentItems(notnull g_StateMenu)
}

func showStateMenuFrom(btn: *Button)
{
    if !g_StateMenu do
        return

    let pos = btn.getSurfaceRect()
    discard g_StateMenu.doModal({pos.horzCenter(), pos.bottom() + 8}, .AnchorTopCenter)
}

func createCommandStatePage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    createStateMenuModel(parent)

    let left = createPanel(parent, "Computed rows", "Open the menu to inspect check marks, radio groups and disabled save/undo/redo rows.", layout.left)
    let stateBtn = PushButton.create(left, "Open state menu", {24, 104, 230})
    stateBtn.form = .Default
    stateBtn.icon = app.theme.getIcon24(.Options, 18)
    stateBtn.sigPressed += &showStateMenuFrom

    discard createActionButton(left, "Toggle grid", {24, 166, 230}, MenuCmd.ToggleGrid, .Options)
    discard createActionButton(left, "Toggle guides", {24, 220, 230}, MenuCmd.ToggleGuides, .Options)
    discard createActionButton(left, "Save", {24, 274, 230}, MenuCmd.SaveFile, .Save)

    let right = createPanel(parent, "State preview", "Buttons and menus listen to the same command state source, so disabled and checked states stay consistent.", layout.right)
    g_Preview = createPreview(right, {18, 86, layout.right.width - 36, layout.right.height - 104})

    createStatusPanel(parent, layout.bottom)
}

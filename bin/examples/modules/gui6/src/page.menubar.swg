using Core, Gui, Pixel

func createMenuBarPage(parent: #nonull *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent, "Desktop menu bar", "Open File, Edit, View or Options to see grouped rows, nested submenus, shortcuts and icons.", layout.left)
    discard createMainMenuBar(left, {20, 94, layout.left.width - 40, 32})

    discard createActionButton(left, "Mark document dirty", {20, 152, 210}, MenuCmd.NewFile, .Edit)
    discard createActionButton(left, "Save through command", {246, 152, 210}, MenuCmd.SaveFile, .Save)
    discard createActionButton(left, "Toggle grid", {20, 204, 210}, MenuCmd.ToggleGrid, .Options)
    discard createActionButton(left, "Detailed mode", {246, 204, 210}, MenuCmd.ModeDetailed, .More)

    let right = createPanel(parent, "Live menu state", "Checked and disabled menu rows are computed at open time from this shared workspace state.", layout.right)
    g_Preview = createPreview(right, {18, 86, layout.right.width - 36, layout.right.height - 104})

    createStatusPanel(parent, layout.bottom)
}

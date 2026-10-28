using Core, Gui, Pixel

func createMenuBarPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent,
                           "Menu bar",
                           "Open File, Edit, View or Options for grouped rows, nested submenus, shortcuts and glyphs.",
                           layout.left)
    discard createMainMenuBar(left, Math.Rectangle{SectionInset, 88, layout.left.width - 2 * SectionInset, 32})

    discard createActionButton(left, "Mark Document Dirty", {24, 144, 210}, MenuCmd.NewFile, .Edit)
    discard createActionButton(left, "Save Through Command", {250, 144, 210}, MenuCmd.SaveFile, .Save)
    discard createActionButton(left, "Toggle Grid", {24, 192, 210}, MenuCmd.ToggleGrid, .Options)
    discard createActionButton(left, "Detailed Mode", {250, 192, 210}, MenuCmd.ModeDetailed, .More)

    let right = createPanel(parent,
                            "Live menu state",
                            "Checked and disabled menu rows are computed at open time from this shared workspace state.",
                            layout.right)
    g_Preview = createPreview(right)

    createStatusPanel(parent, layout.bottom)
}

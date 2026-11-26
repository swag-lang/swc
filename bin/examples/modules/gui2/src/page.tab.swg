using Core, Gui, Pixel

func addTabSample(tab: *Tab)
{
    const Names = ["One", "Two", "Three"]
    for name, index in Names
    {
        let view = Wnd.create'Wnd(tab)
        discard createText(view, Format.toString("View %", index + 1), {14, 12, 120, 24})
        tab.addItem(name, app.theme.icon(ThemeIcons.Search, 14), view)
    }
}

func createTabPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "Flat",
                             "Classic tabs with real child views and a framed selected page.",
                             layout.left)
    scope
    {
        let tab = Tab.create(left, {22, 88, layout.left.width - 44, 122})
        tab.setForm(.Flat)
        addTabSample(tab)
    }

    let right = createPanel(parent,
                            "Round",
                            "Fixed-width round tabs keep the selected page visible.",
                            layout.right)
    scope
    {
        let tab = Tab.create(right, {22, 88, layout.right.width - 44, 124})
        tab.setForm(.Round)
        tab.setLayout(.Fixed)
        addTabSample(tab)
        tab.setSelectedIndex(1)
    }

    let bottom = createPanel(parent,
                             "Button forms",
                             "Button and push-button tabs are compact alternatives for tool surfaces.",
                             layout.bottom)
    let tabWidth = (layout.bottom.width - 72) * 0.5
    scope
    {
        var tab = Tab.create(bottom, {24, 92, tabWidth, 120})
        tab.setForm(.Button)
        addTabSample(tab)
        tab.setSelectedIndex(2)

        tab = Tab.create(bottom, {48 + tabWidth, 92, tabWidth, 120})
        tab.setForm(.PushButton)
        addTabSample(tab)
        tab.setSelectedIndex(1)
    }
}

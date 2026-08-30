using Core, Gui, Pixel

func addTabSample(tab: *Tab, prefix: string)
{
    for 4
    {
        let view = Wnd.create'Wnd(tab)
        let name = Format.toString("%%", prefix, Swag.index + 1)
        discard createText(view, Format.toString("View %", Swag.index + 1), {14, 12, 120, 24})
        tab.addItem(name, app.theme.icon(ThemeIcons.Search, 14), view)
    }
}

func createTabPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent, "Flat", "Classic tabs with real child views and a framed selected page.", layout.left)
    {
        let tab = Tab.create(left, {22, 88, 430, 122})
        tab.setForm(.Flat)
        addTabSample(tab, "Flat ")
    }

    let right = createPanel(parent, "Round", "Fixed-width round tabs keep the selected page visible.", layout.right)
    {
        let tab = Tab.create(right, {22, 88, 420, 124})
        tab.setForm(.Round)
        tab.setLayout(.Fixed)
        addTabSample(tab, "Round ")
        tab.setSelectedIndex(1)
    }

    let bottom = createPanel(parent, "Button forms", "Button and push-button tabs are compact alternatives for tool surfaces.", layout.bottom)
    {
        var tab = Tab.create(bottom, {24, 92, 440, 120})
        tab.setForm(.Button)
        addTabSample(tab, "Button ")
        tab.setSelectedIndex(2)

        tab = Tab.create(bottom, {520, 92, 440, 120})
        tab.setForm(.PushButton)
        addTabSample(tab, "Push ")
        tab.setSelectedIndex(1)
    }
}

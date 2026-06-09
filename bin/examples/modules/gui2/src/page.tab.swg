using Core, Gui, Pixel

func addTabSample(tab: *Tab, prefix: string)
{
    for 4
    {
        let view = Wnd.create'Wnd(tab)
        let name = Format.toString("%%", prefix, @index + 1)
        discard createText(view, Format.toString("View %", @index + 1), {14, 12, 120, 24})
        tab.addItem(name, app.theme.getIcon24(ThemeIcons24.Search, 14), view)
    }
}

func createTabPage(parent: *Wnd)
{
    let left = createPanel(parent, "Flat", "Classic tabs with real child views and a framed selected page.", {0, 0, 500, 250})
    {
        let tab = Tab.create(left, {22, 88, 430, 122})
        tab.setForm(.Flat)
        addTabSample(tab, "Flat ")
    }

    let right = createPanel(parent, "Round", "Fixed-width round tabs keep the selected page visible.", {528, 0, 496, 250})
    {
        let tab = Tab.create(right, {22, 88, 420, 124})
        tab.setForm(.Round)
        tab.barLayout = .Fixed
        addTabSample(tab, "Round ")
        tab.select(1)
    }

    let bottom = createPanel(parent, "Button forms", "Button and push-button tabs are compact alternatives for tool surfaces.", {0, 276, 1024, 248})
    {
        var tab = Tab.create(bottom, {24, 92, 440, 120})
        tab.setForm(.Button)
        addTabSample(tab, "Button ")
        tab.select(2)

        tab = Tab.create(bottom, {520, 92, 440, 120})
        tab.setForm(.PushButton)
        addTabSample(tab, "Push ")
        tab.select(1)
    }
}

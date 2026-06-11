using Core, Gui, Pixel
using Properties

func createListPage(parent: *Wnd)
{
    with let filter = EditBox.create(parent, "")
    {
        .icon      = parent.getTheme().getIcon24(ThemeIcons24.Search, 18)
        .dockStyle = .Top
        .setNote("Search")
        .margin    = {16, 16, 16, 4}
        .editBoxFlags.add(.ClearButton)
        .sigChanged += func(fil) { if g_ListProps do g_ListProps.setStringFilter(fil.text); }
    }

    g_ListProps = Properties.create(parent, {}, .List)
    g_ListProps.dockStyle = .Center
    g_ListProps.margin.x = 16
    g_ListProps.margin.y = 8
    g_ListProps.margin.z = 16
    g_ListProps.margin.w = 16
    addDemoStructs(g_ListProps)
}

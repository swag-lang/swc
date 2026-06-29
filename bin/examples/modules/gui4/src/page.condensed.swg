using Core, Gui, Pixel
using Properties

func createCondensedPage(parent: *Wnd)
{
    g_Inspector = PropertiesCtrl.create(parent, {0, 0, InspectorWidth, 10}, .Condensed, .SectionFilter | .SectionPane | .FindBar)
    g_Inspector.dockStyle  = .Left
    g_Inspector.margin.z   = SplitGap
    addDemoStructs(g_Inspector)
    g_Inspector.splitter.setPaneSize(0, 160)
    g_Inspector.splitter.items[0].tryPreserveSize = true

    let frame = createPanel(parent, "Live preview", "The same reflected data in the dense, classic property grid: thin rows and compact inline editors.", {})
    frame.dockStyle = .Center
    g_Preview = frame.view
    g_Preview.hookOnEvent = &onPreviewEvent
}

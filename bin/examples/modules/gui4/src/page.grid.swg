using Core, Gui, Pixel
using Properties

func createGridPage(parent: *Wnd)
{
    g_Inspector = PropertiesCtrl.create(parent, {0, 0, InspectorWidth, 10}, .Grid, .SectionFilter | .SectionPane | .FindBar)
    g_Inspector.dockStyle  = .Left
    g_Inspector.margin.z   = SplitGap
    addDemoStructs(g_Inspector)
    g_Inspector.splitter.setPaneSize(0, 160)
    g_Inspector.splitter.items[0].tryPreserveSize = true

    let frame = createPanel(parent, "Live preview", "Every value comes from the property editor, including colors, numbers, enum flags and arrays.", {})
    frame.dockStyle = .Center
    g_Preview = frame.view
    g_Preview.hookOnEvent = &onPreviewEvent
}

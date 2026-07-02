using Core, Gui, Pixel
using Properties

// (Re)create the grid inspector inside the host at the current density. Comfortable is the roomy
// grid, Compact the dense classic grid — a density toggle instead of two near-identical pages.
func rebuildGridInspector()
{
    if !g_GridHost do
        return

    if g_Inspector do
        g_Inspector.destroy()

    let kind = g_GridCondensed ? PropertiesKind.Condensed : PropertiesKind.Grid
    g_Inspector = PropertiesCtrl.create(g_GridHost, {}, kind, .SectionFilter | .SectionPane | .FindBar)
    g_Inspector.dockStyle = .Center
    addDemoStructs(g_Inspector)
    g_Inspector.splitter.setPaneSize(0, 160)
    g_Inspector.splitter.items[0].tryPreserveSize = true
    g_GridHost.applyLayout()
}

func setGridDensity(condensed: bool)
{
    if g_GridCondensed == condensed do
        return
    g_GridCondensed = condensed
    rebuildGridInspector()
}

func createGridPage(parent: *Wnd)
{
    // Left column: a density toggle on top, the grid inspector below.
    g_GridHost           = Wnd.create'Wnd(parent, {0, 0, InspectorWidth, 10})
    g_GridHost.dockStyle = .Left
    g_GridHost.margin.z  = SplitGap

    let toggleRow        = Wnd.create'Wnd(g_GridHost, {0, 0, 0, 40})
    toggleRow.dockStyle  = .Top
    toggleRow.margin.w   = 10

    discard createText(toggleRow, "Density:", {0, 0, 72, 40})

    // Same group id -> the toolkit keeps the pair mutually exclusive automatically.
    with let rbComfort = RadioButton.create(toggleRow, "Comfortable", {80, 0, 140, 40})
    {
        .group = "density"
        .setChecked(!g_GridCondensed)
        .sigChanged += func(_rb) { setGridDensity(false); }
    }
    with let rbCompact = RadioButton.create(toggleRow, "Compact", {224, 0, 120, 40})
    {
        .group = "density"
        .setChecked(g_GridCondensed)
        .sigChanged += func(_rb) { setGridDensity(true); }
    }

    rebuildGridInspector()

    let frame = createPanel(parent, "Live preview", "Every value comes from the property editor, including colors, numbers, enum flags and arrays.", {})
    frame.dockStyle = .Center
    g_Preview = frame.view
    g_Preview.hookOnEvent = &onPreviewEvent
}

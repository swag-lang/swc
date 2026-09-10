#global internal

using Gui

private const IconsSvg = #include("../datas/icons.svg")
private var g_PrismIcons:       IconAtlas
private var g_PrismIconsParsed: bool

// Shares the toolbar glyphs' vector document and rasters across application windows.
func prismIcons()->*IconAtlas
{
    if not g_PrismIconsParsed
    {
        expect g_PrismIcons.setup(cast(string) IconsSvg)
        g_PrismIconsParsed = true
    }

    return &g_PrismIcons
}

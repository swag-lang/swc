#global internal

using Gui

private const IconsSvg = #include("../datas/icons.svg")
private var g_PrismIcons:       IconAtlas
private var g_PrismIconsParsed: bool

// Glyphs of the application atlas, in the order `icons.svg` lays them out.
enum PrismIcon
{
    Layout     // Two viewer panels side by side.
    Format     // Indented source lines behind a leading arrow.
}

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

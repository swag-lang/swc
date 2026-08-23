using Core, Gui

// Identifies a glyph of the application icon set (`datas/icons.svg`), in the grid order of the
// document. The set is rasterized on demand per size and scale through [[Gui.IconSet]], so every
// glyph stays sharp at any display density.
//
// Viewer glyphs lead the atlas in registry order. The application actions that follow use the
// same grid and weight, so global and viewer-specific command bars remain one visual family.
enum ViewerIcons
{
    Html               // Markup document viewer.
    Code               // Source-code viewer.
    Markdown           // Markdown document viewer.
    Image              // Picture viewer.
    Video              // Movie player.
    Pdf                // PDF document viewer.
    Sound              // Waveform player.
    Font               // Type-specimen viewer.
    Binary             // Executable and archive inspector.
    Hex                // Raw byte viewer.
    Text               // Plain text viewer.
    FullScreen         // Enter-full-screen action.
    ExitFullScreen     // Leave-full-screen action.
}

private const IconsSvg = #include("../datas/icons.svg")

// The application icon document and the frames rasterized from it, shared by every window and by
// the headless test fixtures; parsed and rasterized once per process.
private var g_ViewerIcons: IconAtlas
private var g_ViewerIconsParsed: bool

// Returns the parsed application icon document, parsing it on first use.
func viewerIcons()->*IconAtlas
{
    if !g_ViewerIconsParsed
    {
        expect g_ViewerIcons.setup(cast(string) IconsSvg)
        g_ViewerIconsParsed = true
    }

    return &g_ViewerIcons
}

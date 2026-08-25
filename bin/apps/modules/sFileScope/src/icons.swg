using Core, Gui

// Identifies a glyph of the application icon set (`datas/icons.svg`), in the grid order of the
// document. The set is rasterized on demand per size and scale through [[Gui.IconSet]], so every
// glyph stays sharp at any display density.
//
// Viewer glyphs follow registry order. Generic action glyphs come from [[Gui.ThemeIcons]], so an
// action keeps the same mark in every application.
enum ViewerIcons
{
    Html         // Markup document viewer.
    Code         // Source-code viewer.
    Markdown     // Markdown document viewer.
    Image        // Picture viewer.
    Video        // Movie player.
    Pdf          // PDF document viewer.
    Sound        // Waveform player.
    Font         // Type-specimen viewer.
    Binary       // Executable and archive inspector.
    Hex          // Raw byte viewer.
    Text         // Plain text viewer.
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

// Gives every viewer toolbar the same type and dimensions.
struct ViewerCommandBar
{
    using wnd: Wnd
}

impl ViewerCommandBar
{
    func create(parent: *Wnd, width: f32)->*ViewerCommandBar
    {
        let result = Wnd.create'ViewerCommandBar(parent, {0, 0, width, 36})
        result.backgroundStyle = .Window
        return result
    }
}

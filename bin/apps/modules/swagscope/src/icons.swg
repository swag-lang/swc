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
    Table        // Delimited-text table viewer.
    Midi         // Piano-roll viewer.
    Subtitle     // Timed subtitle viewer.
    Archive      // Compressed-archive browser.
    Indesign     // Native InDesign saved-preview viewer.
}

private const IconsSvg = #include("../datas/icons.svg")

// The application icon document and the frames rasterized from it, shared by every window and by
// the headless test fixtures; parsed and rasterized once per process.
private var g_ViewerIcons:       IconAtlas
private var g_ViewerIconsParsed: bool

// Returns the parsed application icon document, parsing it on first use.
//
// Every built-in viewer names its glyph in this one document, the way a separately built plugin
// would name a cell of the document it embeds itself.
func viewerIcons()->*IconAtlas
{
    if !g_ViewerIconsParsed
    {
        expect g_ViewerIcons.setup(cast(string) IconsSvg)
        g_ViewerIconsParsed = true
    }

    return &g_ViewerIcons
}

// One vector document a plugin named, and the frame textures the window uploaded it into.
//
// The document itself belongs to whoever embedded it. Only the textures belong here, and they are
// released with the window that created the renderer holding them.
struct ViewerPluginIcons
{
    atlas: #null *IconAtlas
    icons: IconSet
}

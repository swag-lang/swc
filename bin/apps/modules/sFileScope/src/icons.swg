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
    SeekBackward       // Media seek toward an earlier position.
    SeekForward        // Media seek toward a later position.
    Volume             // Audible media volume.
    VolumeMute         // Muted media volume.
    FitView            // Fit the complete document inside its viewport.
    ActualSize         // Show one source pixel or point at its native scale.
    Wrap               // Fold long text lines into the viewport.
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

// Owns the application glyph textures used by one viewer toolbar.
//
// The vector rasterizations stay shared in [[viewerIcons]]; only the renderer textures belong to
// the toolbar and are released with it.
struct ViewerCommandBar
{
    using wnd: Wnd
    icons:     IconSet
}

impl IWnd for ViewerCommandBar
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        .icons.free()
    }
}

impl ViewerCommandBar
{
    func create(parent: *Wnd, width: f32)->*ViewerCommandBar
    {
        let result = Wnd.create'ViewerCommandBar(parent, {0, 0, width, 36})
        result.backgroundStyle = .Window
        result.icons.setup(parent.app().renderer, viewerIcons())
        return result
    }

    mtd icon(index: ViewerIcons, size = 20'f32)->Icon
    {
        return .icons.icon(cast(s32) index, size, .theme().res.atlasScale)
    }
}

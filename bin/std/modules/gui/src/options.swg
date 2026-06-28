#global public
using Core, Serialization, Properties

struct ApplicationOptions
{
    #[Category("Debug"), Name("Show Clip Rect"), Description("Display an overlay of the current drawing clipping rectangle")]
    showClipRect: bool

    #[Category("Debug"), Name("Show Layout Rects"), Description("Display layout rectangles computed by layout controls")]
    showLayoutRects: bool

    #[Category("Debug"), Name("Dump Layout Tree"), Description("Enable layout tree dumps from debug tooling")]
    dumpLayoutTree: bool
}

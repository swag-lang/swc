#global public

using Core, Serialization, Properties

// Represents application options.
struct ApplicationOptions
{
    #[Category("Debug"), Name("Show Clip Rect"), Description("Display an overlay of the current drawing clipping rectangle")]
    showClipRect: bool // Show clip rect associated with this value.

    #[Category("Debug"), Name("Show Layout Rects"), Description("Display layout rectangles computed by layout controls")]
    showLayoutRects: bool // Show layout rects associated with this value.

    #[Category("Debug"), Name("Dump Layout Tree"), Description("Enable layout tree dumps from debug tooling")]
    dumpLayoutTree: bool // Dump layout tree associated with this value.
}

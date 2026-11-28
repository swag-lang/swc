#global public

using Core, Serialization, Properties

// Development diagnostics available to a GUI application.
struct ApplicationOptions
{
    public
    {
        #[Category("Debug"), Name("Show Clip Rect"), Description("Display an overlay of the current drawing clipping rectangle")]
        showClipRect: bool     // Overlays the repaint clipping rectangle with a translucent color.

        #[Category("Debug"), Name("Show Layout Rects"), Description("Display layout rectangles computed by layout controls")]
        showLayoutRects: bool     // Draws the rectangles produced by layout controls.

        #[Category("Debug"), Name("Show Focus Rings"), Description("Draw the keyboard-focus ring on every control that can take the keyboard")]
        showFocusRings: bool     // Draws the focus ring on every traversal stop, not only on the one holding the keyboard.

        #[Category("Debug"), Name("Dump Layout Tree"), Description("Enable layout tree dumps from debug tooling")]
        dumpLayoutTree: bool     // Enables layout-tree dumps from diagnostic tooling.
    }
}

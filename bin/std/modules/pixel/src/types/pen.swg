#global public

using Core

// Selects the geometry placed at the beginning or end of a stroked path.
enum LineCapStyle
{
    None             // End at the path endpoint without an added cap.
    Triangle         // Add a triangular cap.
    Round            // Add a semicircular cap.
    Square           // Extend by a square half-width.
    ArrowAnchor      // Add the primary arrowhead shape.
    ArrowAnchor2     // Add the alternate arrowhead shape.
    SquareAnchor     // Add a centered square anchor.
    RoundAnchor      // Add a centered circular anchor.
}

// Selects the cap applied to each dash segment.
enum DashCapStyle
{
    None         // Use unextended dash ends.
    Triangle     // Add triangular dash ends.
    Round        // Add semicircular dash ends.
    Square       // Add square dash ends.
}

// Selects how consecutive stroke segments meet.
enum JoinStyle
{
    None           // Do not add explicit join geometry.
    Bevel          // Cut the outer corner with a straight edge.
    Round          // Join with a circular arc.
    Miter          // Extend edges to their intersection, subject to the miter limit.
    MiterBevel     // Use a miter when allowed and a bevel otherwise.
}

// Selects a built-in or custom stroke-dash sequence.
enum DashStyle
{
    None        // Draw a continuous stroke.
    Pattern     // Use the values stored in `Pen.pattern`.
    Dot         // Use the built-in dotted sequence.
    Dash        // Use the built-in dashed sequence.
    DashDot     // Alternate built-in dash and dot segments.
}

// Selects how a stroke is positioned relative to a closed contour.
enum BorderPos
{
    None       // Center the stroke on the contour.
    Inside     // Keep the stroke inside the contour.
}

// Describes how a path is stroked.
//
// Lengths and scale factors are expressed in path-space pixels. Use the factory
// functions for common solid, dashed, and hatched pens.
struct Pen
{
    size:  f32 = 1     // Stroke width, in pixels.
    brush: Brush       // Paint source applied to the stroke.

    pattern:         Array'f32               // Alternating on/off lengths for `.Pattern`.
    dashBegCapStyle: DashCapStyle = None     // Cap at the beginning of each visible dash.
    dashEndCapStyle: DashCapStyle = None     // Cap at the end of each visible dash.
    borderPos:       BorderPos    = None     // Stroke placement for closed paths.

    capBegScaleX: f32 = 2     // Horizontal scale of the path-begin cap.
    capBegScaleY: f32 = 2     // Vertical scale of the path-begin cap.
    capEndScaleX: f32 = 2     // Horizontal scale of the path-end cap.
    capEndScaleY: f32 = 2     // Vertical scale of the path-end cap.

    joinMiterLimit: f32 = 3     // Maximum miter length relative to stroke width.
    plotOffset:     f32         // Offset into the dash sequence, in pixels.

    dashStyle:      DashStyle    = None      // Active dash sequence.
    dashBlankScale: f32          = 1.0       // Multiplier applied to blank dash lengths.
    begCapStyle:    LineCapStyle = Round     // Cap at the beginning of the path.
    endCapStyle:    LineCapStyle = Round     // Cap at the end of the path.
    joinStyle:      JoinStyle    = Miter     // Join between consecutive segments.
}

impl Pen
{
    // Creates a continuous solid-color pen.
    func createSolid(color: Color, size: f32 = 1)->Pen
    {
        var result: retval
        result.brush.color = color
        result.brush.type  = .SolidColor
        result.size        = size
        return result
    }

    // Creates a solid-color pen with a built-in dash style.
    func createDash(style: DashStyle, color: Color, size: f32 = 1)->Pen
    {
        var result: retval
        result.brush.color = color
        result.brush.type  = .SolidColor
        result.dashStyle   = style
        result.size        = size
        return result
    }

    // Creates a continuous pen painted with a repeating hatch.
    func createHatch(type: HatchStyle, color: Color, size: f32 = 1)->Pen
    {
        var result: retval
        result.brush.color  = color
        result.brush.type   = .Hatch
        result.brush.hatch  = type
        result.size         = size
        result.brush.uvMode = .Tile
        return result
    }
}

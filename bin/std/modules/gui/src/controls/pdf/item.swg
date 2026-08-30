#global public
#global namespace Pdf

using Core, Core.Math, Pixel

// Identifies one page item in paint order.
enum ItemKind
{
    Text      // A UTF-8 text run.
    Path      // One filled and/or stroked vector path.
    Image     // One decoded raster image.
}

// Selects the shape at the open ends of a stroked PDF path and its dash segments.
enum StrokeCap
{
    Butt       // End exactly at the path endpoint.
    Round      // Add a semicircular cap.
    Square     // Extend by half the stroke width with a square cap.
}

// Selects how consecutive segments of a stroked PDF path meet.
enum StrokeJoin
{
    Miter     // Extend the outer edges until the miter limit, then bevel the corner.
    Round     // Join the segments with a circular arc.
    Bevel     // Cut the outer corner with a straight edge.
}

// Describes the geometry of a PDF path stroke.
struct PathStrokeStyle
{
    public
    {
        cap:         StrokeCap  = .Butt      // Shape at open path ends and dash ends.
        join:        StrokeJoin = .Miter     // Shape between consecutive segments.
        miterLimit:  f32        = 10         // Maximum miter length relative to the stroke width; at least one.
        dashPattern: Array'f32               // Alternating painted and blank lengths in PDF points; empty means solid.
        dashPhase:   f32                     // Signed distance into the repeated dash pattern in PDF points.
    }
}

// Describes one page item in Pixel's top-left coordinate system.
//
// Use the matching [[Gui.Pdf.Page.addText]], [[Gui.Pdf.Page.addPath]], or
// [[Gui.Pdf.Page.addImage]] operation to construct an item. Fields unrelated to
// `kind` retain their defaults.
struct Item
{
    public readonly kind: ItemKind     // Active item representation.

    internal
    {
        text:         String
        textCodes:    Array'u32
        textAdvances: Array'f32
        path:         LinePathList
        image:        Image
        transform:    Transform2 = Transform2.Identity

        fillColor:    Color        = Color.fromArgb(Argb.Black)
        strokeColor:  Color        = Color.fromArgb(Argb.Black)
        fontSize:     f32
        strokeWidth:  f32          = 1
        strokeStyle:  PathStrokeStyle
        hasFill:      bool
        hasStroke:    bool
        evenOddFill:  bool
        fontIndex:    u32          = Swag.U32.Max
        standardFont: StandardFont = StandardFont.Helvetica

        // Region this item is confined to, in page coordinates, when the content stream
        // established one. Marks outside it belong to the page's construction, not to what
        // it means to show.
        clip:    Math.Rectangle
        hasClip: bool

        // Page-space box this item's marks cannot leave, and whether it is known at all. It is
        // computed when the item joins a page and refreshed by every operation that moves or
        // widens its marks, because a frame asks for it once per item and a path answers it in
        // one pass over its segments.
        paintBox:      Math.Rectangle
        paintBoxKnown: bool
    }
}

internal impl Item
{
    // Returns the page-space box this item's marks cannot leave.
    //
    // Text is the one kind that cannot answer: a run's extent needs the resolved face, which the
    // page does not hold, so it reports the whole plane and is treated as unbounded.
    mtd const paintBounds()->Math.Rectangle
    {
        if !.paintBoxKnown do
            return {-Swag.F32.Max * 0.5, -Swag.F32.Max * 0.5, Swag.F32.Max, Swag.F32.Max}
        return .paintBox
    }

    // Recomputes the box, after the item is built or after something moved or widened its marks.
    mtd refreshPaintBounds()
    {
        var local: Math.Rectangle
        switch .kind
        {
        case .Path:  local = .path.controlBounds()
        case .Image: local = {0, 0, 1, 1}

        case .Text: .paintBox = {}
            .paintBoxKnown = false
            return
        }

        // A stroke is laid on the path rather than inside it, and a miter reaches past the join
        // by as much as the limit allows, so the marks of a stroked path leave the path's own box.
        if .kind == .Path and .hasStroke
        {
            let reach = .strokeWidth * 0.5 * Math.max(.strokeStyle.miterLimit, 1)
            local.applyPadding({-reach, -reach, -reach, -reach})
        }

        let corners: [4] Vector2 = [
            .transform.transformPoint({local.x, local.y}),
            .transform.transformPoint({local.right(), local.y}),
            .transform.transformPoint({local.right(), local.bottom()}),
            .transform.transformPoint({local.x, local.bottom()})]

        var min = corners[0]
        var max = corners[0]
        for corner in corners
        {
            min.x = Math.min(min.x, corner.x)
            min.y = Math.min(min.y, corner.y)
            max.x = Math.max(max.x, corner.x)
            max.y = Math.max(max.y, corner.y)
        }

        .paintBox      = {min.x, min.y, max.x - min.x, max.y - min.y}
        .paintBoxKnown = true
    }
}

impl Item
{
    // Returns the text carried by a text item, or an empty string for another kind.
    mtd const textValue()->string => .kind == .Text ? .text.toString() : ""

    // Returns the transform applied when this item is rendered.
    mtd const itemTransform()->Transform2 => .transform

    // Returns the page-space region this item is confined to, or the whole page when the
    // content stream established no clip for it.
    mtd const itemClip()->{ rect: Math.Rectangle, clipped: bool } => {.clip, .hasClip}

    // Returns the fill color of text and filled paths.
    mtd const itemFillColor()->Color => .fillColor

    // Returns the stroke color of a stroked path.
    mtd const itemStrokeColor()->Color => .strokeColor

    // Returns the text size in PDF points, or zero for another kind.
    mtd const textSize()->f32 => .kind == .Text ? .fontSize : 0

    // Returns the standard face this text is written with.
    //
    // A decoded page reports the standard face closest to the font the file names, which is
    // the face the writer would use again.
    mtd const textFont()->StandardFont => .standardFont

    // Returns the stroke width in PDF points, or zero for a hairline or an item with no stroke.
    mtd const pathStrokeWidth()->f32 => .kind == .Path and .hasStroke ? .strokeWidth : 0

    // Returns whether a filled path uses the alternating rule rather than the winding count.
    mtd const pathUsesEvenOddFill()->bool => .kind == .Path and .evenOddFill

    // Returns the stroke geometry of a path item, or the default solid style for another kind.
    mtd const pathStrokeStyle()->PathStrokeStyle => .kind == .Path ? .strokeStyle : PathStrokeStyle{}

    // Returns a borrowed path list for a path item.
    //
    // The pointer remains valid until the owning page or its item array is mutated.
    mtd const pathValue()->#null const *LinePathList => .kind == .Path ? &.path : null

    // Returns a borrowed image for an image item.
    //
    // The pointer remains valid until the owning page or its item array is mutated.
    mtd const imageValue()->#null const *Image => .kind == .Image ? &.image : null
}

internal impl Item
{
    func createText()->Item
    {
        var result: retval
        result.kind = .Text
        return result
    }

    func createPath()->Item
    {
        var result: retval
        result.kind = .Path
        return result
    }

    func createImage()->Item
    {
        var result: retval
        result.kind = .Image
        return result
    }
}

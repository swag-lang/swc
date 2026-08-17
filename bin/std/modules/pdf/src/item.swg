#global public

using Core, Core.Math, Pixel

// Identifies one page item in paint order.
enum ItemKind
{
    Text      // A UTF-8 text run.
    Path      // One filled and/or stroked vector path.
    Image     // One decoded raster image.
}

// Describes one page item in Pixel's top-left coordinate system.
//
// Use the matching [[Pdf.Page.addText]], [[Pdf.Page.addPath]], or
// [[Pdf.Page.addImage]] operation to construct an item. Fields unrelated to
// `kind` retain their defaults.
struct Item
{
    public readonly kind: ItemKind     // Active item representation.

    internal
    {
        text:      String
        path:      LinePathList
        image:     Image
        transform: Transform2 = Transform2.Identity

        fillColor:    Color        = Color.fromArgb(Argb.Black)
        strokeColor:  Color        = Color.fromArgb(Argb.Black)
        fontSize:     f32
        strokeWidth:  f32          = 1
        hasFill:      bool
        hasStroke:    bool
        fontIndex:    u32          = Swag.U32.Max
        standardFont: StandardFont = StandardFont.Helvetica
    }
}

public impl Item
{
    // Returns the text carried by a text item, or an empty string for another kind.
    mtd const textValue()->string => .kind == .Text ? .text.toString() : ""

    // Returns the transform applied when this item is rendered.
    mtd const itemTransform()->Transform2 => .transform

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

    // Returns the stroke width in PDF points, or zero when the item has no stroke.
    mtd const pathStrokeWidth()->f32 => .kind == .Path and .hasStroke ? .strokeWidth : 0

    // Returns a borrowed path list for a path item.
    //
    // The pointer remains valid until the owning page or its item array is mutated.
    mtd const pathValue()->#null const *LinePathList => .kind == .Path ? &.path : null

    // Returns a borrowed image for an image item.
    //
    // The pointer remains valid until the owning page or its item array is mutated.
    mtd const imageValue()->#null const *Image => .kind == .Image ? &.image : null
}

impl Item
{
    internal func createText()->Item
    {
        var result: retval
        result.kind = .Text
        return result
    }

    internal func createPath()->Item
    {
        var result: retval
        result.kind = .Path
        return result
    }

    internal func createImage()->Item
    {
        var result: retval
        result.kind = .Image
        return result
    }
}

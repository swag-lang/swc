#global public

using Core, Core.Math, Pixel

private func isFiniteTransform(transform: Transform2)->bool
{
    return Math.isFinite(transform.m11) and Math.isFinite(transform.m12) and Math.isFinite(transform.m21) and Math.isFinite(transform.m22) and Math.isFinite(transform.tx) and Math.isFinite(transform.ty)
}

private func isValidStrokeStyle(style: const *PathStrokeStyle)->bool
{
    if style.miterLimit < 1 or !Math.isFinite(style.miterLimit) or !Math.isFinite(style.dashPhase) do
        return false

    var hasPositiveLength = false
    for length in style.dashPattern
    {
        if length < 0 or !Math.isFinite(length) do
            return false
        hasPositiveLength = hasPositiveLength or length > 0
    }

    return !style.dashPattern.count or hasPositiveLength
}

// PDF repeats an odd dash array before alternating painted and blank intervals.
private func normalizedStrokeStyle(style: PathStrokeStyle)->PathStrokeStyle
{
    var result: retval = style
    if result.dashPattern.count & 1
    {
        let count = result.dashPattern.count
        for i in count do
            result.dashPattern.add(result.dashPattern[i])
    }

    return result
}

// Stores one editable PDF page.
//
// Dimensions and item coordinates are expressed in PDF points, with an origin at
// the top-left. Items are painted in array order.
struct Page
{
    public
    {
        width:  f32     // Page width in PDF points.
        height: f32     // Page height in PDF points.

        readonly items: Array'Item     // Page content in paint order.
    }

    internal fonts: Array'FontResource
}

public impl Page
{
    // Creates an empty page with positive dimensions in PDF points.
    func create(width, height: f32)->Page
    {
        Debug.assert(width > 0 and height > 0 and Math.isFinite(width) and Math.isFinite(height), "invalid page dimensions")
        var result: retval
        result.width  = width
        result.height = height
        return result
    }

    // Appends one UTF-8 text run.
    //
    // `(x, y)` is the top-left of the text line box. `font` selects one of the standard
    // faces every reader provides; the writer accepts the characters Windows-1252 can
    // represent. Use [[Pdf.StandardFont.textWidth]] to measure the run before placing it.
    mtd addText(text: string, x, y, size: f32, color = Color.fromArgb(Argb.Black), font = StandardFont.Helvetica)
    {
        Debug.assert(size > 0 and Math.isFinite(size) and Math.isFinite(x) and Math.isFinite(y), "invalid text placement")
        var item = Item.createText()
        item.text         = text
        item.fontSize     = size
        item.fillColor    = color
        item.standardFont = font
        item.transform    = Transform2.createTranslation(x, y)
        .items.add(#move item)
    }

    // Appends one vector path.
    //
    // `fill` and `stroke` independently select the two paint operations. At least
    // one must be enabled. `strokeStyle` selects the cap, join, miter, and dash
    // geometry when stroking. Path coordinates and dash data are copied into the page.
    mtd addPath(path: LinePathList, fill = true, fillColor = Color.fromArgb(Argb.Black), stroke = false, strokeColor = Color.fromArgb(Argb.Black), strokeWidth = 1.0, strokeStyle: PathStrokeStyle = {})
    {
        Debug.assert(fill or stroke, "path has no paint operation")
        Debug.assert(!stroke or (strokeWidth >= 0 and Math.isFinite(strokeWidth)), "invalid stroke width")
        Debug.assert(!stroke or isValidStrokeStyle(&strokeStyle), "invalid path stroke style")
        var item = Item.createPath()
        item.path        = path
        item.hasFill     = fill
        item.fillColor   = fillColor
        item.hasStroke   = stroke
        item.strokeColor = strokeColor
        item.strokeWidth = strokeWidth
        item.strokeStyle = normalizedStrokeStyle(strokeStyle)
        .items.add(#move item)
    }

    // Appends one raster image in the requested page rectangle.
    //
    // The image pixels are copied. `width` and `height` are expressed in PDF
    // points and must be positive.
    mtd addImage(image: Image, x, y, width, height: f32)
    {
        Debug.assert(image.isValid(), "invalid image")
        Debug.assert(width > 0 and height > 0 and Math.isFinite(width) and Math.isFinite(height) and Math.isFinite(x) and Math.isFinite(y), "invalid image placement")
        var item = Item.createImage()
        item.image     = image
        item.transform = Transform2{width, 0, 0, height, x, y}
        .items.add(#move item)
    }

    // Removes the item at `index` and preserves the paint order of the rest.
    mtd removeItem(index: u64)
    {
        Debug.assert(index < .items.count, "item index out of range")
        .items.removeAt(index)
    }

    // Replaces the UTF-8 content of a text item.
    mtd setText(index: u64, text: string)
    {
        Debug.assert(index < .items.count and .items[index].kind == .Text, "item is not text")
        .items[index].text = text
        .items[index].textCodes.clear()
        .items[index].textAdvances.clear()
    }

    // Replaces the point size of a text item.
    mtd setTextSize(index: u64, size: f32)
    {
        Debug.assert(index < .items.count and .items[index].kind == .Text, "item is not text")
        Debug.assert(size > 0 and Math.isFinite(size), "invalid text size")
        .items[index].fontSize = size
        .items[index].textCodes.clear()
        .items[index].textAdvances.clear()
    }

    // Replaces the standard face a text item is written with.
    mtd setTextFont(index: u64, font: StandardFont)
    {
        Debug.assert(index < .items.count and .items[index].kind == .Text, "item is not text")
        .items[index].standardFont = font
        .items[index].textCodes.clear()
        .items[index].textAdvances.clear()
    }

    // Replaces the transform applied to an item during rendering and writing.
    mtd setItemTransform(index: u64, transform: Transform2)
    {
        Debug.assert(index < .items.count, "item index out of range")
        Debug.assert(isFiniteTransform(transform), "invalid item transform")
        .items[index].transform = transform
    }

    // Replaces the fill color of a text or path item.
    mtd setItemFillColor(index: u64, color: Color)
    {
        Debug.assert(index < .items.count and .items[index].kind != .Image, "item has no fill color")
        .items[index].fillColor = color
    }

    // Replaces the stroke color of a path item.
    mtd setPathStrokeColor(index: u64, color: Color)
    {
        Debug.assert(index < .items.count and .items[index].kind == .Path, "item is not a path")
        .items[index].strokeColor = color
        .items[index].hasStroke   = true
    }

    // Replaces the non-negative stroke width of a path item and enables its stroke.
    //
    // A zero width is rendered as a device-pixel hairline.
    mtd setPathStrokeWidth(index: u64, width: f32)
    {
        Debug.assert(index < .items.count and .items[index].kind == .Path, "item is not a path")
        Debug.assert(width >= 0 and Math.isFinite(width), "invalid stroke width")
        .items[index].strokeWidth = width
        .items[index].hasStroke   = true
    }

    // Replaces the cap, join, miter, and dash geometry of a path stroke.
    //
    // Dash lengths and phase are expressed in PDF points; the phase may be negative. An odd-length pattern is repeated once, as required by PDF, before its painted and blank intervals alternate.
    mtd setPathStrokeStyle(index: u64, style: PathStrokeStyle)
    {
        Debug.assert(index < .items.count and .items[index].kind == .Path, "item is not a path")
        Debug.assert(isValidStrokeStyle(&style), "invalid path stroke style")
        .items[index].strokeStyle = normalizedStrokeStyle(style)
        .items[index].hasStroke   = true
    }

    // Removes every page item while preserving the page dimensions.
    mtd clear()
    {
        .items.clear()
        .fonts.clear()
    }

    // Renders the complete page to an owned Pixel image.
    mtd const render(options: RenderOptions = {})->Image fail
    {
        return try renderPage(me, options)
    }
}

impl Page
{
    internal mtd appendItem(item: #move Item)
    {
        .items.add(#move item)
    }
}

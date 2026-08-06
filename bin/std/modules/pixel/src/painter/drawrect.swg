#global public

using Core

impl Painter
{
    // Draw an empty rectangle
    mtd drawRect(left, top, width, height: f32, color: Color, penSize: f32 = 1)
    {
        if width == 0 or height == 0 or .isInvisible(color) or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawRect(left, top, width, height, pen)
    }

    mtd drawRect(rect: Math.Rectangle, color: Color, penSize: f32 = 1)
    {
        .drawRect(rect.x, rect.y, rect.width, rect.height, color, penSize)
    }

    // Returns the stroke-path inset for a pen along a device-snapped edge.
    //
    // The stroke band spans half the pen on each side of the path, so the inset is what
    // decides which device pixels the band covers. `Inside` puts the whole band inside the
    // edge. `None` centers it on the edge, biased half a device pixel inward when the pen
    // covers an odd number of device pixels, so the band still fills whole pixels instead
    // of straddling two rows at half strength.
    private mtd const strokeInset(pen: Pen)->f32
    {
        let k = .curContentScale
        switch #complete pen.borderPos
        {
        case .None:
            let devSize = cast(s32) Math.round(pen.size * k)
            return devSize & 1 ? 0.5 / k : 0.0

        case .Inside:
            return pen.size * 0.5
        }

        return 0
    }

    mtd drawRect(left, top, width, height: f32, pen: Pen)
    {
        if width == 0 or height == 0 or .isInvisible(pen.brush) or pen.size == 0 do
            return

        // Snap the edges to the device grid rather than the origin and the extent apart;
        // see drawRoundRect.
        let l = .snapToDeviceX(left)
        let t = .snapToDeviceY(top)
        let w = .snapToDeviceX(left + width) - l
        let h = .snapToDeviceY(top + height) - t

        let o = .strokeInset(pen)
        .sharedLinePath.setRectRaw(l + o, t + o, w - 2 * o, h - 2 * o)
        .drawPath(&.sharedLinePath, pen)
    }

    mtd drawRect(rect: Math.Rectangle, pen: Pen)
    {
        .drawRect(rect.x, rect.y, rect.width, rect.height, pen)
    }

    // Emit a pixel-snapped, axis-aligned rectangle as two triangles, with no
    // antialiasing fringe. The caller must guarantee the rect is already rounded
    // and the current transform is a pure translation, so the edges land on pixel
    // boundaries and need no fringe.
    private mtd fillRectRaw(l, t, w, h: f32, brush: Brush)
    {
        .setTexture0({l, t}, {l + w, t + h}, brush)
        .resetTextureFont()

        let v0 = Math.Vector2{l, t}
        let v1 = Math.Vector2{l + w, t}
        let v2 = Math.Vector2{l + w, t + h}
        let v3 = Math.Vector2{l, t + h}
        discard .pushTriangle(v0, v1, v2, brush.color)
        discard .pushTriangle(v0, v2, v3, brush.color)
    }

    // Draw a filled rectangle
    mtd fillRect(left, top, width, height: f32, brush: Brush)
    {
        if width == 0 or height == 0 or .isInvisible(brush) do
            return

        // Snap the edges to the device-pixel grid, not to whole path units: at a fractional
        // content scale a whole logical coordinate can land between two device pixels, and
        // which side wins then depends on the rasterizer's tie rule — the same window reads
        // crisp or soft depending on its size parity. Snapping the transformed edge makes the
        // result exact at every scale and position.
        let l = .snapToDeviceX(left)
        let t = .snapToDeviceY(top)
        let w = .snapToDeviceX(left + width) - l
        let h = .snapToDeviceY(top + height) - t

        // Fast path: an axis-aligned, device-snapped rectangle under a pure-translation
        // transform already has its edges on pixel boundaries, so the antialiasing
        // fringe is pure overhead (and can darken seams between adjacent fills). Emit
        // the two interior triangles directly, skipping path construction, flattening
        // and tessellation. This is the dominant GUI primitive (widget backgrounds).
        if .curState.transform.isTranslationOnly()
        {
            .fillRectRaw(l, t, w, h, brush)
            return
        }

        .sharedLinePath.setRectRaw(l, t, w, h)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillRect(rect: Math.Rectangle, brush: Brush)
    {
        .fillRect(rect.x, rect.y, rect.width, rect.height, brush)
    }

    mtd fillRect(left, top, width, height: f32, color: Color)
    {
        if width == 0 or height == 0 or .isInvisible(color) do
            return

        let brush = Brush.createSolid(color)
        .fillRect(left, top, width, height, brush)
    }

    mtd fillRect(rect: Math.Rectangle, color: Color)
    {
        .fillRect(rect.x, rect.y, rect.width, rect.height, color)
    }

    // Draw an empty round rectangle
    mtd drawRoundRect(left, top, width, height: f32, radiusX, radiusY: f32, color: Color, penSize: f32 = 1)
    {
        if width == 0 or height == 0 or .isInvisible(color) or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawRoundRect(left, top, width, height, radiusX, radiusY, pen)
    }

    mtd drawRoundRect(left, top, width, height: f32, radiusX, radiusY: f32, pen: Pen)
    {
        if width == 0 or height == 0 or .isInvisible(pen.brush) or pen.size == 0 do
            return

        // Snap the four edges to the device grid, not the position and the extent apart.
        // Rounded on its own, a width lands the far edge a whole unit off whenever the two
        // round in opposite directions, and the stroke stops tracing the shape it was
        // measured from. The path is then built raw: re-snapping it to whole path units
        // would throw the device alignment away again at any fractional content scale.
        let l = .snapToDeviceX(left)
        let t = .snapToDeviceY(top)
        let w = .snapToDeviceX(left + width) - l
        let h = .snapToDeviceY(top + height) - t

        // Move the corner radii with the inset. A corner is a quarter circle whose centre sits
        // one radius in from each edge, so insetting the rectangle alone keeps the original
        // radius around a centre that has moved: the stroke then pulls away from the outline it
        // traces by the inset times root two at forty-five degrees, and every rounded window
        // showed a ring of its own body colour outside its border.
        let o  = .strokeInset(pen)
        let rx = Math.max(0, radiusX - o)
        let ry = Math.max(0, radiusY - o)
        .sharedLinePath.setRoundRectRaw(l + o, t + o, w - 2 * o, h - 2 * o, rx, ry)
        .drawPath(&.sharedLinePath, pen)
    }

    mtd drawRoundRect(rect: Math.Rectangle, radiusX, radiusY: f32, pen: Pen)
    {
        .drawRoundRect(rect.x, rect.y, rect.width, rect.height, radiusX, radiusY, pen)
    }

    mtd drawRoundRect(rect: Math.Rectangle, radiusX, radiusY: f32, color: Color, penSize: f32 = 1)
    {
        let pen = Pen.createSolid(color, penSize)
        .drawRoundRect(rect.x, rect.y, rect.width, rect.height, radiusX, radiusY, pen)
    }

    // Draw a filled round rectangle
    mtd fillRoundRect(left, top, width, height: f32, radiusX, radiusY: f32, brush: Brush)
    {
        if width == 0 or height == 0 or .isInvisible(brush) do
            return

        // Snap the straight edges to the device grid; see fillRect. The radii stay as
        // given — the arcs are antialiased whatever their placement, but a straight edge
        // between two device pixels reads as a half-covered column.
        let l = .snapToDeviceX(left)
        let t = .snapToDeviceY(top)
        let w = .snapToDeviceX(left + width) - l
        let h = .snapToDeviceY(top + height) - t
        .sharedLinePath.setRoundRectRaw(l, t, w, h, radiusX, radiusY)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillRoundRect(rect: Math.Rectangle, radiusX, radiusY: f32, brush: Brush)
    {
        .fillRoundRect(rect.x, rect.y, rect.width, rect.height, radiusX, radiusY, brush)
    }

    mtd fillRoundRect(left, top, width, height: f32, radiusX, radiusY: f32, color: Color)
    {
        if width == 0 or height == 0 or .isInvisible(color) do
            return

        let brush = Brush.createSolid(color)
        .fillRoundRect(left, top, width, height, radiusX, radiusY, brush)
    }

    mtd fillRoundRect(rect: Math.Rectangle, radiusX, radiusY: f32, color: Color)
    {
        .fillRoundRect(rect.x, rect.y, rect.width, rect.height, radiusX, radiusY, color)
    }
}

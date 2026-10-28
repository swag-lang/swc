#global public

using Core

impl Painter
{
    // Strokes the outline of a rectangle.
    //
    // The edges are snapped to the device-pixel grid. With [[Pixel.BorderPos.Inside]], the
    // stroke stays inside the rectangle.
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
            let devSize = cast(s32, Math.round(pen.size * k))
            return devSize & 1 ? 0.5 / k : 0.0

        case .Inside:
            return pen.size * 0.5
        }
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
        // A device-aligned copy has no edge coverage to compute or glyph mask to sample.
        // Keep this choice beside the geometry, so layers and ordinary texture copies share it.
        // Other blend modes can depend on the general shader discarding zero-alpha texels;
        // explicit effects and custom shaders must never be replaced by this shortcut.
        let simpleCopy = .usesDefaultShader and brush.type == .Texture and .curState.blendingMode == .Copy
        if simpleCopy do
            .setDefaultShader(.Simple)
        defer
        {
            if simpleCopy do
                .setDefaultShader()
        }

        .setTexture0(Vector2{l, t}, Vector2{l + w, t + h}, brush)
        .resetTextureFont()

        let v0 = Math.Vector2{l, t}
        let v1 = Math.Vector2{l + w, t}
        let v2 = Math.Vector2{l + w, t + h}
        let v3 = Math.Vector2{l, t + h}
        discard .pushTriangle(v0, v1, v2, brush.color)
        discard .pushTriangle(v0, v2, v3, brush.color)
    }

    // Fills a rectangle.
    //
    // The edges are snapped to the device-pixel grid, so adjacent fills meet without a seam.
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

    // Strokes the outline of a rectangle with elliptical corners.
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

    // Fills a rectangle with elliptical corners.
    //
    // The straight edges are snapped to the device-pixel grid; the radii are used as given.
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

    // Fills a rounded rectangle whose corners carry their own radius.
    //
    // The radii are given clockwise from the top left, as a style sheet writes them. Corners that
    // would overlap are scaled down together; see [[Pixel.LinePath.setRoundRectRaw]].
    mtd fillRoundRect(rect: Math.Rectangle, topLeft, topRight, bottomRight, bottomLeft: f32, brush: Brush)
    {
        if rect.width == 0 or rect.height == 0 or .isInvisible(brush) do
            return

        let l = .snapToDeviceX(rect.x)
        let t = .snapToDeviceY(rect.y)
        let w = .snapToDeviceX(rect.right()) - l
        let h = .snapToDeviceY(rect.bottom()) - t
        .sharedLinePath.setRoundRectRaw(l, t, w, h, topLeft, topRight, bottomRight, bottomLeft)
        .fillPath(&.sharedLinePath, brush)
    }

    // Fills a rounded rectangle whose corners carry their own radius.
    mtd fillRoundRect(rect: Math.Rectangle, topLeft, topRight, bottomRight, bottomLeft: f32, color: Color)
    {
        if rect.width == 0 or rect.height == 0 or .isInvisible(color) do
            return

        let brush = Brush.createSolid(color)
        .fillRoundRect(rect, topLeft, topRight, bottomRight, bottomLeft, brush)
    }

    // Strokes the outline of a rounded rectangle whose corners carry their own radius.
    //
    // The pen is centred on the outline, exactly as the uniform form places it.
    mtd drawRoundRect(rect: Math.Rectangle, topLeft, topRight, bottomRight, bottomLeft: f32, pen: Pen)
    {
        if rect.width == 0 or rect.height == 0 or .isInvisible(pen.brush) or pen.size == 0 do
            return

        let l = .snapToDeviceX(rect.x)
        let t = .snapToDeviceY(rect.y)
        let w = .snapToDeviceX(rect.right()) - l
        let h = .snapToDeviceY(rect.bottom()) - t

        // Move every radius with the inset, for the reason the uniform form records.
        let o = .strokeInset(pen)
        .sharedLinePath.setRoundRectRaw(l + o, t + o, w - 2 * o, h - 2 * o, Math.max(0, topLeft - o), Math.max(0, topRight - o), Math.max(0, bottomRight - o), Math.max(0, bottomLeft - o))
        .drawPath(&.sharedLinePath, pen)
    }

    // Strokes the outline of a rounded rectangle whose corners carry their own radius.
    mtd drawRoundRect(rect: Math.Rectangle, topLeft, topRight, bottomRight, bottomLeft: f32, color: Color, penSize: f32 = 1)
    {
        if rect.width == 0 or rect.height == 0 or .isInvisible(color) or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawRoundRect(rect, topLeft, topRight, bottomRight, bottomLeft, pen)
    }

    // Fills a soft shadow around a rounded rectangle, from a faint outer edge in to its border.
    //
    // `spread` is how far the shadow reaches beyond the shape, in logical units, and `color`'s
    // alpha is the darkening it reaches where it meets the shape. The shape itself is filled at
    // that strength, so a shadow offset from the shape that casts it leaves no gap beside it;
    // paint the shape over the result.
    //
    // The ramp is smoothstep: a long faint tail where it meets the ground and a flat shoulder
    // against the shape, which is what reads as air under it rather than as an outline drawn
    // around it. It is painted as eight gradient tiles — one along each side, one around each
    // corner — that meet on the device grid, so every pixel is blended exactly once. A stack of
    // nested translucent rings drew the same ramp, but each ring rounded the ground it landed on,
    // and a wide shadow, one ring per device pixel, came out much darker than it was asked to be.
    mtd fillShadow(rect: Math.Rectangle, cornerRadius, spread: f32, color: Color)
    {
        if spread <= 0 or color.a == 0 do
            return

        let r  = Math.clamp(cornerRadius, 0, Math.min(rect.width, rect.height) * 0.5)
        let x0 = rect.x
        let y0 = rect.y
        let x1 = rect.right()
        let y1 = rect.bottom()

        // Smoothstep from the peak at the shape to nothing at `spread`, sampled on as many stops
        // as a gradient carries without a stop table.
        const Stops = 8

        func ramp(brush: *Brush, color: Color)
        {
            let peak = cast(f32, color.a) / 255.0
            for i in Stops
            {
                let t = cast(f32, i) / cast(f32, Stops - 1)
                brush.addGradientStop(t, color.withAlphaF32(peak * Math.smoothstep(0.0, 1.0, 1.0 - t)))
            }
        }

        // The shape, at full strength: three bands that leave its corners to the corner tiles.
        .fillRect({x0 + r, y0, x1 - x0 - 2 * r, y1 - y0}, color)
        .fillRect({x0, y0 + r, r, y1 - y0 - 2 * r}, color)
        .fillRect({x1 - r, y0 + r, r, y1 - y0 - 2 * r}, color)

        // The sides, each ramping away from the edge it stands on.

        func side(painter: *Painter, tile: Math.Rectangle, start, end: Math.Vector2, color: Color)
        {
            var brush = Brush.createLinearGradient(start, end, color, color)
            brush.gradientStops.clear()
            ramp(&brush, color)
            painter.fillRect(tile, brush)
        }

        side(me, {x0 + r, y0 - spread, x1 - x0 - 2 * r, spread}, {x0, y0}, {x0, y0 - spread}, color)
        side(me, {x0 + r, y1, x1 - x0 - 2 * r, spread}, {x0, y1}, {x0, y1 + spread}, color)
        side(me, {x0 - spread, y0 + r, spread, y1 - y0 - 2 * r}, {x0, y0}, {x0 - spread, y0}, color)
        side(me, {x1, y0 + r, spread, y1 - y0 - 2 * r}, {x1, y0}, {x1 + spread, y0}, color)

        // The corners, each ramping away from the arc that rounds it.
        func corner(painter: *Painter, tile: Math.Rectangle, center: Math.Vector2, r, spread: f32, color: Color)
        {
            var brush = Brush.createRadialGradient(center, r + spread, color, color)
            brush.gradientRadius0 = r
            brush.gradientStops.clear()
            ramp(&brush, color)
            painter.fillRect(tile, brush)
        }

        let tile = r + spread
        corner(me, {x0 - spread, y0 - spread, tile, tile}, {x0 + r, y0 + r}, r, spread, color)
        corner(me, {x1 - r, y0 - spread, tile, tile}, {x1 - r, y0 + r}, r, spread, color)
        corner(me, {x0 - spread, y1 - r, tile, tile}, {x0 + r, y1 - r}, r, spread, color)
        corner(me, {x1 - r, y1 - r, tile, tile}, {x1 - r, y1 - r}, r, spread, color)
    }
}

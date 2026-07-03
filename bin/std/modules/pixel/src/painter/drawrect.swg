#global public
using Core

impl Painter
{
    // Draw an empty rectangle
    mtd drawRect(left, top, width, height: f32, color: Color, penSize: f32 = 1)
    {
        if width == 0 or height == 0 or color.a == 0 or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawRect(left, top, width, height, pen)
    }

    mtd drawRect(rect: Math.Rectangle, color: Color, penSize: f32 = 1)
    {
        .drawRect(rect.x, rect.y, rect.width, rect.height, color, penSize)
    }

    mtd drawRect(left, top, width, height: f32, pen: Pen)
    {
        if width == 0 or height == 0 or !pen.brush.hasVisibleAlpha() or pen.size == 0 do
            return

        var l = Math.round(left)
        var t = Math.round(top)
        var w = Math.round(width)
        var h = Math.round(height)

        #[Swag.Complete]
        switch pen.borderPos
        {
        case None:
            let o = 0.5
            l += o
            t += o
            w -= 2 * o
            h -= 2 * o
        case Inside:
            let o = 0.5 + pen.size * 0.5
            l += o
            t += o
            w -= 2 * o
            h -= 2 * o
        }

        .sharedLinePath.setRectRaw(l, t, w, h)
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
        if width == 0 or height == 0 or !brush.hasVisibleAlpha() do
            return

        let l = Math.round(left)
        let t = Math.round(top)
        let w = Math.round(width)
        let h = Math.round(height)

        // Fast path: an axis-aligned, pixel-snapped rectangle under a pure-translation
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
        if width == 0 or height == 0 or color.a == 0 do
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
        if width == 0 or height == 0 or color.a == 0 or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawRoundRect(left, top, width, height, radiusX, radiusY, pen)
    }

    mtd drawRoundRect(left, top, width, height: f32, radiusX, radiusY: f32, pen: Pen)
    {
        if width == 0 or height == 0 or !pen.brush.hasVisibleAlpha() or pen.size == 0 do
            return

        var l = Math.round(left)
        var t = Math.round(top)
        var w = Math.round(width)
        var h = Math.round(height)

        #[Swag.Complete]
        switch pen.borderPos
        {
        case None:
            let o = 0.5
            l += o
            t += o
            w -= 2 * o
            h -= 2 * o
        case Inside:
            let o = 0.5 + pen.size * 0.5
            l += o
            t += o
            w -= 2 * o
            h -= 2 * o
        }

        .sharedLinePath.setRoundRect(l, t, w, h, radiusX, radiusY)
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
        if width == 0 or height == 0 or !brush.hasVisibleAlpha() do
            return
        .sharedLinePath.setRoundRect(left, top, width, height, radiusX, radiusY)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillRoundRect(rect: Math.Rectangle, radiusX, radiusY: f32, brush: Brush)
    {
        if rect.width == 0 or rect.height == 0 or !brush.hasVisibleAlpha() do
            return
        .sharedLinePath.setRoundRect(rect.x, rect.y, rect.width, rect.height, radiusX, radiusY)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillRoundRect(left, top, width, height: f32, radiusX, radiusY: f32, color: Color)
    {
        if width == 0 or height == 0 or color.a == 0 do
            return

        let brush = Brush.createSolid(color)
        .fillRoundRect(left, top, width, height, radiusX, radiusY, brush)
    }

    mtd fillRoundRect(rect: Math.Rectangle, radiusX, radiusY: f32, color: Color)
    {
        .fillRoundRect(rect.x, rect.y, rect.width, rect.height, radiusX, radiusY, color)
    }
}

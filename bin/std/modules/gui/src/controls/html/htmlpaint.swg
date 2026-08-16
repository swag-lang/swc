#global internal

using Core, Pixel

// Draws a laid-out document.
//
// The traversal is the paint order CSS defines — a box's own background and borders, then the
// boxes it contains, then its text — and it prunes any subtree whose rectangle falls outside the
// visible area, which is what lets a document of a hundred thousand boxes draw one screen in the
// time one screen costs.
struct HtmlPainter
{
    layout:   *HtmlLayout = undefined
    painter:  *Painter    = undefined
    images:   #null *HtmlImageCache
    renderer: #null IRenderer

    visible: Math.Rectangle
    scrollY: f32

    // The link under the pointer, and the colour it takes. A state pseudo-class would have to
    // restyle the document to answer the pointer; lighting the run while it is painted costs one
    // comparison per drawn item and no layout at all.
    hoverLink = HtmlNoNode
    hotLink: Color
}

impl HtmlPainter
{
    private func withAlpha(color: Color, alpha: f32)->Color
    {
        if alpha >= 1 do
            return color
        var result = color
        result.a = cast(u8) Math.clamp(cast(f32) color.a * alpha, 0, 255)
        return result
    }

    // Returns the extra offset a box is drawn at, which is what makes a sticky box hold its
    // place while the reader scrolls past its container.
    private mtd const stickyOffset(box: u32, offset: Math.Point)->f32
    {
        let target = .layout.constBox(box)
        if !target.sticky do
            return 0

        // `offset` carries the scroll translation and whatever sticky offsets the ancestors added,
        // so removing the first recovers where this box currently sits in the document.
        let documentY = target.rect.y + offset.y + .scrollY
        let parent    = target.parent
        let limit     = parent == HtmlNoNode ? target.rect.bottom() : .layout.constBox(parent).content.bottom()
        let wanted    = .scrollY + target.stickyTop - documentY
        return Math.clamp(wanted, 0, Math.max(limit - target.rect.bottom(), 0))
    }

    // Returns the band geometry is allowed to reach.
    //
    // A document is tens of thousands of pixels tall and its outermost boxes are that tall too.
    // Handing such a shape to the rasterizer asks it to walk a quarter of a million scanlines for
    // the thousand that are visible, and the coordinates leave the range its edge arithmetic is
    // accurate over. Everything is therefore clamped to the visible area first, which changes
    // nothing about what is seen.
    private mtd const band()->Math.Rectangle
    {
        var result = .visible
        result.x      -= result.width
        result.y      -= result.height
        result.width  *= 3
        result.height *= 3
        return result
    }

    // Fills the background and strokes the borders of one box.
    private mtd paintDecorations(rect: Math.Rectangle, style: const *HtmlComputedStyle, alpha: f32)
    {
        let radius = Math.max(Math.max(style.radiusTopLeft, style.radiusTopRight), Math.max(style.radiusBottomRight, style.radiusBottomLeft))
        if style.background.a and !style.masked
        {
            let ground = HtmlPainter.withAlpha(style.background, alpha)
            let area   = Math.Rectangle.intersect(rect, .band())
            if radius > 0 do
                .painter.fillRoundRect(rect.height < .band().height ? rect : area, radius, radius, ground)
            else do
                .painter.fillRect(area, ground)
        }

        if radius > 0 and style.borderTop.width > 0 and style.borderTop.style != .None
        {
            let color = HtmlPainter.withAlpha(style.borderTop.color, alpha)
            .painter.drawRoundRect(rect, radius, radius, color, style.borderTop.width)
            return
        }

        // Border sides meet on the diagonal of the corner they share. Drawing each as a rectangle
        // instead is invisible while the four are the same color, and wrong the moment they are
        // not — including the widespread idiom that makes a triangle out of a zero-sized box and
        // three borders, only one of which is opaque.
        let left     = rect.x
        let top      = rect.y
        let right    = rect.right()
        let bottom   = rect.bottom()
        let inLeft   = left + style.borderLeft.width
        let inTop    = top + style.borderTop.width
        let inRight  = right - style.borderRight.width
        let inBottom = bottom - style.borderBottom.width

        // A side is a trapezoid when its neighbours differ in colour, and a rectangle otherwise.
        // The rectangle is what almost every document draws, and it is the only shape a large box
        // may be given: a wide, thin polygon corrupts what the painter draws after it — see F-144.
        let mitred = rect.width < .band().width and rect.height < .band().height and .hasDistinctSides(style)
        if style.borderTop.width > 0 and style.borderTop.style != .None
        {
            let color = HtmlPainter.withAlpha(style.borderTop.color, alpha)
            if mitred do
                .fillQuad(left, top, right, top, inRight, inTop, inLeft, inTop, color)
            else do
                .fillSide(left, top, right - left, style.borderTop.width, color)
        }

        if style.borderBottom.width > 0 and style.borderBottom.style != .None
        {
            let color = HtmlPainter.withAlpha(style.borderBottom.color, alpha)
            if mitred do
                .fillQuad(inLeft, inBottom, inRight, inBottom, right, bottom, left, bottom, color)
            else do
                .fillSide(left, inBottom, right - left, style.borderBottom.width, color)
        }

        if style.borderLeft.width > 0 and style.borderLeft.style != .None
        {
            let color = HtmlPainter.withAlpha(style.borderLeft.color, alpha)
            if mitred do
                .fillQuad(left, top, inLeft, inTop, inLeft, inBottom, left, bottom, color)
            else do
                .fillSide(left, top, style.borderLeft.width, bottom - top, color)
        }

        if style.borderRight.width > 0 and style.borderRight.style != .None
        {
            let color = HtmlPainter.withAlpha(style.borderRight.color, alpha)
            if mitred do
                .fillQuad(inRight, inTop, right, top, right, bottom, inRight, inBottom, color)
            else do
                .fillSide(inRight, top, style.borderRight.width, bottom - top, color)
        }
    }

    // Reports whether the four sides differ enough for the diagonal between them to be visible.
    private func hasDistinctSides(style: const *HtmlComputedStyle)->bool
    {
        if style.borderTop.color != style.borderBottom.color do
            return true
        if style.borderLeft.color != style.borderRight.color do
            return true
        if style.borderTop.color != style.borderLeft.color do
            return true
        return false
    }

    private mtd fillSide(x, y, width, height: f32, color: Color)
    {
        if !color.a do
            return

        var side: Math.Rectangle
        side.x      = x
        side.y      = y
        side.width  = width
        side.height = height
        .painter.fillRect(Math.Rectangle.intersect(side, .band()), color)
    }

    // Fills one border side as the trapezoid it really is, its corners given in order around the
    // shape.
    private mtd fillQuad(ax, ay, bx, by, cx, cy, dx, dy: f32, color: Color)
    {
        if !color.a do
            return

        var points: Array'Math.Vector2
        points.add(HtmlPainter.point(ax, ay))
        points.add(HtmlPainter.point(bx, by))
        points.add(HtmlPainter.point(cx, cy))
        points.add(HtmlPainter.point(dx, dy))
        .painter.fillPolygon(points.toSlice(), Brush.createSolid(color))
    }

    private func point(x, y: f32)->Math.Vector2
    {
        var result: retval
        result.x = x
        result.y = y
        return result
    }

    // Draws the text decorations a run carries, in the color the document chose for them.
    private mtd paintDecorationLines(item: const *HtmlInlineItem, style: const *HtmlComputedStyle, alpha: f32, x: f32, y: f32)
    {
        if style.textDecoration == .None do
            return

        let color     = HtmlPainter.withAlpha(style.hasDecorationColor ? style.textDecorationColor : style.color, alpha)
        let thickness = Math.max(Math.round(style.fontSize / 14), 1)
        if style.textDecoration.has(.Underline) do
            .painter.fillRect({x, Math.round(y + item.ascent + thickness), item.width, thickness}, color)
        if style.textDecoration.has(.Overline) do
            .painter.fillRect({x, Math.round(y), item.width, thickness}, color)
        if style.textDecoration.has(.LineThrough) do
            .painter.fillRect({x, Math.round(y + item.ascent * 0.68), item.width, thickness}, color)
    }

    // Reports whether a node is `ancestor` or sits under it.
    private mtd const isInside(node: u32, ancestor: u32)->bool
    {
        var walk = node
        while walk != HtmlNoNode
        {
            if walk == ancestor do
                return true
            walk = .layout.document.constNode(walk).parent
        }

        return false
    }

    // Draws the inline content of one box.
    private mtd paintItems(box: u32, offset: Math.Point, alpha: f32)
    {
        let target = .layout.constBox(box)
        for index in target.items.count
        {
            let item = &target.items[index]
            if !item.visible do
                continue

            let x = item.x + offset.x
            let y = item.y + offset.y
            if y > .visible.bottom() or y + item.ascent + item.descent < .visible.y do
                continue

            let style = .layout.constStyle(item.style)
            if !style.visible do
                continue

            if item.kind == .Atomic
            {
                if item.box != HtmlNoNode do
                    .paintBox(item.box, offset, alpha * style.opacity)
                continue
            }

            if style.background.a
            {
                let padTop    = item.ascent * 0.28
                let padBottom = item.descent * 0.4
                .painter.fillRect({x, y - padTop, item.width, item.ascent + item.descent + padTop + padBottom}, HtmlPainter.withAlpha(style.background, alpha))
            }

            if item.kind == .Space
            {
                .paintDecorationLines(item, style, alpha, x, y)
                continue
            }

            let font = .layout.font(item.style)
            let hot  = .hoverLink != HtmlNoNode and .hotLink.a and .isInside(item.node, .hoverLink)
            let ink  = HtmlPainter.withAlpha(hot ? .hotLink : style.color, alpha * style.opacity)
            if style.letterSpacing != 0
            {
                // Extra tracking is a property of the shaped run, not of the draw call, so a run
                // that asks for it is shaped here rather than drawn straight.
                var shaped = Painter.shapeRun(item.text.toString(), font, DefaultTextTabSize, style.letterSpacing)
                .painter.drawShapedRun(x, y, &shaped, font, Brush.createSolid(ink))
            }
            else do
                .painter.drawString(x, y, item.text.toString(), font, ink)
            .paintDecorationLines(item, style, alpha, x, y)
        }
    }

    // Draws the marker a list item or a disclosure summary carries beside its content.
    private mtd paintMarker(box: u32, offset: Math.Point, ink: Color)
    {
        let target  = .layout.constBox(box)
        let content = target.content
        let font    = .layout.font(target.style)
        let left    = content.x + offset.x - target.markerWidth - font.height * 0.35
        let top     = content.y + offset.y

        if target.markerKind == .Text
        {
            .painter.drawString(left, top, target.marker.toString(), font, ink)
            return
        }

        if target.markerKind == .Checked
        {
            let inside  = content
            let tick    = Math.min(inside.width, inside.height) * 0.9
            let originX = inside.x + offset.x + (inside.width - tick) * 0.5
            let originY = inside.y + offset.y + (inside.height - tick) * 0.5
            let stroke  = Math.max(Math.round(tick * 0.18), 1)
            .fillQuad(originX, originY + tick * 0.5, originX + stroke, originY + tick * 0.5 - stroke, originX + tick * 0.4, originY + tick, originX + tick * 0.4 - stroke, originY + tick, ink)
            .fillQuad(originX + tick * 0.4 - stroke, originY + tick, originX + tick * 0.4, originY + tick, originX + tick, originY + stroke, originX + tick - stroke, originY, ink)
            return
        }

        let size = Math.max(Math.round(font.height * 0.34), 3)
        let midY = top + font.height * 0.5
        var points: Array'Math.Vector2
        if target.markerKind == .DisclosureOpen
        {
            points.add({left, midY - size * 0.5})
            points.add({left + size * 2, midY - size * 0.5})
            points.add({left + size, midY + size * 0.7})
        }
        else
        {
            points.add({left + size * 0.5, midY - size})
            points.add({left + size * 0.5 + size * 1.4, midY})
            points.add({left + size * 0.5, midY + size})
        }

        .painter.fillPolygon(points.toSlice(), Brush.createSolid(ink))
    }

    // Draws one box and everything under it.
    mtd paintBox(box: u32, parentOffset: Math.Point, alpha: f32)
    {
        let style = .layout.constStyle(.layout.constBox(box).style)
        if !style.visible or style.display == .None do
            return

        var offset = parentOffset
        offset.y += .stickyOffset(box, parentOffset)

        var rect = .layout.constBox(box).rect
        rect.offset(offset.x, offset.y)

        let combined = alpha * style.opacity
        if combined <= 0.004 do
            return

        // A box outside the visible band hides everything it contains.
        if !rect.intersects(.visible) do
            return

        .paintDecorations(rect, style, combined)

        if .layout.constBox(box).kind == .Replaced
        {
            .paintReplaced(box, rect, combined)
            return
        }

        if .layout.constBox(box).markerKind != .None do
            .paintMarker(box, offset, HtmlPainter.withAlpha(style.color, combined))

        var inner = offset
        let clips = false and (style.overflowX != .Visible or style.overflowY != .Visible)
        if clips
        {
            var clip = .layout.constBox(box).content
            clip.offset(offset.x, offset.y)
            clip.inflate(1)
            .painter.pushClippingRect(clip)
            inner.y -= .layout.constBox(box).scrollTop
        }

        .paintItems(box, inner, combined)

        let children = .layout.constBox(box).children
        for child in children do
            .paintBox(child, inner, combined)

        if clips do
            .painter.popClippingRect()
    }

    private mtd paintReplaced(box: u32, rect: Math.Rectangle, alpha: f32)
    {
        let node  = .layout.constBox(box).node
        let inner = .layout.constBox(box).content
        var frame = rect
        frame.x      = inner.x + (rect.x - .layout.constBox(box).rect.x)
        frame.y      = inner.y + (rect.y - .layout.constBox(box).rect.y)
        frame.width  = inner.width
        frame.height = inner.height

        if .images and .renderer and node != HtmlNoNode
        {
            let texture = .images!.texture(.renderer!, .layout.document.attribute(node, "src"))
            if texture
            {
                .painter.drawTexture(frame, texture[], HtmlPainter.withAlpha(Color.fromArgb(Argb.White), alpha))
                return
            }
        }

        // A picture the engine has no bytes for still shows the room it takes, so a broken
        // reference reads as a missing image instead of as a hole in the page.
        let style = .layout.constStyle(.layout.constBox(box).style)
        .painter.drawRect(frame, HtmlPainter.withAlpha(style.color, alpha * 0.35), 1)
    }

    // Draws the part of the document the viewport shows.
    //
    // Boxes are placed in document coordinates and the whole tree is drawn through one offset, so
    // scrolling costs a translation rather than a relayout.
    mtd paint(visible: Math.Rectangle, scrollY: f32)
    {
        .visible = visible
        .scrollY = scrollY
        if .layout.root != HtmlNoNode do
            .paintBox(.layout.root, {0, -scrollY}, 1)
    }
}

// Hit testing.
impl HtmlPainter
{
    // Returns the innermost node drawn at a point, or `HtmlNoNode` when nothing is.
    mtd const nodeAt(point: Math.Point)->u32
    {
        if .layout.root == HtmlNoNode do
            return HtmlNoNode
        return .nodeAtBox(.layout.root, point, {0, -.scrollY})
    }

    private mtd const nodeAtBox(box: u32, point: Math.Point, parentOffset: Math.Point)->u32
    {
        let style = .layout.constStyle(.layout.constBox(box).style)
        if !style.visible or style.display == .None do
            return HtmlNoNode

        var offset = parentOffset
        offset.y += .stickyOffset(box, parentOffset)

        var rect = .layout.constBox(box).rect
        rect.offset(offset.x, offset.y)

        var inner = offset
        if style.overflowX != .Visible or style.overflowY != .Visible
        {
            if !rect.contains(point) do
                return HtmlNoNode
            inner.y -= .layout.constBox(box).scrollTop
        }

        let children = .layout.constBox(box).children
        for index in children.count
        {
            let found = .nodeAtBox(children[children.count - index - 1], point, inner)
            if found != HtmlNoNode do
                return found
        }

        let target = .layout.constBox(box)
        for index in target.items.count
        {
            let item = &target.items[index]
            if !item.visible do
                continue

            if item.kind == .Atomic and item.box != HtmlNoNode
            {
                let found = .nodeAtBox(item.box, point, inner)
                if found != HtmlNoNode do
                    return found
                continue
            }

            let frame = Math.Rectangle{item.x + inner.x, item.y + inner.y, item.width, item.ascent + item.descent}
            if frame.contains(point) do
                return item.node
        }

        if rect.contains(point) and target.node != HtmlNoNode do
            return target.node
        return HtmlNoNode
    }

    // Returns the innermost scrollable region drawn at a point.
    mtd const scrollableAt(point: Math.Point)->u32
    {
        if .layout.root == HtmlNoNode do
            return HtmlNoNode
        return .scrollableAtBox(.layout.root, point, {0, -.scrollY})
    }

    private mtd const scrollableAtBox(box: u32, point: Math.Point, parentOffset: Math.Point)->u32
    {
        var offset = parentOffset
        offset.y += .stickyOffset(box, parentOffset)

        var rect = .layout.constBox(box).rect
        rect.offset(offset.x, offset.y)
        if !rect.contains(point) do
            return HtmlNoNode

        var inner = offset
        if .layout.constBox(box).scrollable do
            inner.y -= .layout.constBox(box).scrollTop

        let children = .layout.constBox(box).children
        for index in children.count
        {
            let found = .scrollableAtBox(children[children.count - index - 1], point, inner)
            if found != HtmlNoNode do
                return found
        }

        return .layout.constBox(box).scrollable ? box : HtmlNoNode
    }
}

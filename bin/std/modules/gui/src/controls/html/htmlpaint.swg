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

    searchNode = HtmlNoNode
    searchStart: u64
    searchEnd:   u64
    selection:   Color

    scrollTrack:    Color
    scrollThumb:    Color
    scrollBarSize:  f32
    scrollThumbMin: f32
}

// Geometry of one independently scrolling region's vertical bar in canvas coordinates.
struct HtmlRegionScrollBar
{
    box = HtmlNoNode
    track: Math.Rectangle
    thumb: Math.Rectangle
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

    // Returns the stacking level a child contributes to its parent's paint order. CSS ignores
    // `z-index` on statically positioned boxes, so they stay in the ordinary level-zero flow.
    private mtd const stackingLevel(box: u32)->s32
    {
        let style = .layout.constStyle(.layout.constBox(box).style)
        return style.position == .Static ? 0 : style.zIndex
    }

    // Finds the adjacent non-zero stacking level on one side of normal flow.
    private mtd const nextStackingLevel(box: u32, previous: s32, hasPrevious: bool, positive: bool, ascending: bool)->{ value: s32, found: bool }
    {
        var result: retval
        for child in .layout.constBox(box).children
        {
            let level = .stackingLevel(child)
            if level == 0 or (level > 0) != positive do
                continue
            if hasPrevious and (ascending ? level <= previous : level >= previous) do
                continue
            if result.found and (ascending ? level >= result.value : level <= result.value) do
                continue
            result.value = level
            result.found = true
        }

        return result
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
        if style.clipPath != HtmlNoNode
        {
            .paintClippedDecorations(rect, style, alpha)
            return
        }

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
        // may be given: a wide, thin polygon corrupts what the painter draws after it — see F-148.
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

    // Resolves `polygon()` pairs against the painted border box. This covers the generated
    // documentation's cut cards, tags, and outline buttons while retaining the same percentage
    // and `calc()` rules as the rest of the style engine.
    private mtd clipPolygon(rect: Math.Rectangle, style: const *HtmlComputedStyle)->Array'Math.Vector2
    {
        var result: retval
        let parsed = htmlFunctionArguments(.layout.pool.text(style.clipPath), "polygon")
        if !parsed.matched or parsed.arguments.count < 3 do
            return result

        var values:  HtmlValuePool
        var context: HtmlLengthContext
        context.fontSize       = style.fontSize
        context.rootFontSize   = .layout.defaults.fontSize
        context.viewportWidth  = .layout.viewport.x
        context.viewportHeight = .layout.viewport.y
        context.hasBasis       = true

        for argument in parsed.arguments
        {
            let coordinates = htmlSplitValue(argument.toString())
            if coordinates.count != 2
            {
                result.clear()
                return result
            }

            context.basis = rect.width
            let x  = htmlParseLength(&values, coordinates[0].toString(), context)
            let px = x.length.resolve(&values, context)
            context.basis = rect.height
            let y  = htmlParseLength(&values, coordinates[1].toString(), context)
            let py = y.length.resolve(&values, context)
            if !x.matched or !y.matched
            {
                result.clear()
                return result
            }

            result.add(HtmlPainter.point(rect.x + px, rect.y + py))
        }

        return result
    }

    // Paints a clipped fill and, when the four border sides form one outline, traces that same
    // polygon. Different side colors are intentionally omitted: clipping each of those sides
    // needs polygon intersection rather than a misleading rectangular approximation.
    private mtd paintClippedDecorations(rect: Math.Rectangle, style: const *HtmlComputedStyle, alpha: f32)
    {
        var points = .clipPolygon(rect, style)
        if points.count < 3 do
            return

        if style.background.a and !style.masked do
            .painter.fillPolygon(points.toSlice(), Brush.createSolid(HtmlPainter.withAlpha(style.background, alpha)))

        let border = &style.borderTop
        if border.width <= 0 or border.style == .None or !border.color.a do
            return
        if style.borderRight.width != border.width or style.borderBottom.width != border.width or style.borderLeft.width != border.width do
            return
        if style.borderRight.color != border.color or style.borderBottom.color != border.color or style.borderLeft.color != border.color do
            return

        var path: LinePath
        path.start(points[0].x, points[0].y)
        for index in 1 until points.count do
            path.lineTo(points[index].x, points[index].y)
        path.close()
        .painter.drawPath(&path, HtmlPainter.withAlpha(border.color, alpha), border.width)
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
        let thickness = style.textDecorationThickness > 0 ? style.textDecorationThickness : Math.max(Math.round(style.fontSize / 14), 1)
        let offset    = style.textUnderlineOffset != 0 ? style.textUnderlineOffset : thickness
        if style.textDecoration.has(.Underline) do
            .paintDecorationLine({x, Math.round(y + item.ascent + offset), item.width, thickness}, color, style.textDecorationStyle)
        if style.textDecoration.has(.Overline) do
            .paintDecorationLine({x, Math.round(y), item.width, thickness}, color, style.textDecorationStyle)
        if style.textDecoration.has(.LineThrough) do
            .paintDecorationLine({x, Math.round(y + item.ascent * 0.68), item.width, thickness}, color, style.textDecorationStyle)
    }

    private mtd paintDecorationLine(rect: Math.Rectangle, color: Color, style: HtmlTextDecorationStyle)
    {
        if style == .Solid
        {
            .painter.fillRect(rect, color)
            return
        }

        let dot = Math.max(rect.height, 1)
        var x   = rect.x
        while x < rect.right()
        {
            .painter.fillRect({x, rect.y, Math.min(dot, rect.right() - x), rect.height}, color)
            x += dot * 2
        }
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

            .paintSearchHit(item, alpha, x, y)

            if item.kind == .Space
            {
                .paintDecorationLines(item, style, alpha, x, y)
                continue
            }

            let font      = .layout.font(item.style)
            let hot       = .hoverLink != HtmlNoNode and .hotLink.a and .isInside(item.node, .hoverLink)
            let ink       = HtmlPainter.withAlpha(hot ? .hotLink : style.color, alpha * style.opacity)
            let boxStyle  = .layout.constStyle(target.style)
            let clipRight = target.content.right() + offset.x
            let ellipsis  = boxStyle.textOverflowEllipsis and boxStyle.overflowX != .Visible and style.whiteSpace == .NoWrap and x + item.width > clipRight
            if ellipsis and clipRight > x do
                .paintEllipsized(item, style, font, ink, x, y, clipRight - x)
            else do
                .paintTextRun(item.text.toString(), style, font, ink, x, y)
            .paintDecorationLines(item, style, alpha, x, y)
        }
    }

    private mtd paintTextRun(text: string, style: const *HtmlComputedStyle, font: *Font, ink: Color, x, y: f32)
    {
        if style.letterSpacing != 0
        {
            // Extra tracking is a property of the shaped run, not of the draw call, so a run
            // that asks for it is shaped here rather than drawn straight.
            var shaped = Painter.shapeRun(text, font, DefaultTextTabSize, style.letterSpacing)
            .painter.drawShapedRun(x, y, &shaped, font, Brush.createSolid(ink))
        }
        else do
            .painter.drawString(x, y, text, font, ink)
    }

    // Draws the longest UTF-8 prefix that leaves room for a visible truncation marker.
    private mtd paintEllipsized(item: const *HtmlInlineItem, style: const *HtmlComputedStyle, font: *Font, ink: Color, x, y, room: f32)
    {
        const Marker = "..."
        let markerWidth = .layout.measure(item.style, Marker)
        if room < markerWidth do
            return

        let source = item.text.toString()
        var end    = 0'u64
        while end < @countof(source)
        {
            let {?, eat} = Utf8.decodeRune(source[end to])
            let next     = end + eat
            if .layout.measure(item.style, source[0 until next]) + markerWidth > room do
                break
            end = next
        }

        var clipped: String
        if end do
            clipped += source[0 until end]
        clipped += Marker
        .paintTextRun(clipped.toString(), style, font, ink, x, y)
    }

    // Marks the part of a text run covered by the current find result. Source offsets remain on
    // each inline item, so a match split by wrapping or inline markup still paints continuously.
    private mtd paintSearchHit(item: const *HtmlInlineItem, alpha: f32, x: f32, y: f32)
    {
        if item.node != .searchNode or .searchEnd <= item.sourceStart or .searchStart >= item.sourceEnd do
            return

        var left         = x
        var width        = item.width
        let sourceLength = item.sourceEnd - item.sourceStart
        if sourceLength == @countof(item.text) and sourceLength
        {
            let start = Math.max(.searchStart, item.sourceStart) - item.sourceStart
            let end   = Math.min(.searchEnd, item.sourceEnd) - item.sourceStart
            left  += .layout.measure(item.style, item.text[0 until start])
            width = .layout.measure(item.style, item.text[start until end])
        }

        if width <= 0 do
            return
        let padTop    = item.ascent * 0.28
        let padBottom = item.descent * 0.4
        .painter.fillRect({left, y - padTop, width, item.ascent + item.descent + padTop + padBottom}, HtmlPainter.withAlpha(.selection, alpha))
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

    // Draws one sign of positioned stacking levels in ascending order, preserving document order
    // between siblings on the same level.
    private mtd paintStackedChildren(box: u32, offset: Math.Point, alpha: f32, positive: bool)
    {
        let children = .layout.constBox(box).children
        var previous:    s32
        var hasPrevious: bool
        while true
        {
            let next = .nextStackingLevel(box, previous, hasPrevious, positive, true)
            if !next.found do
                return
            for child in children where .stackingLevel(child) == next.value do
                .paintBox(child, offset, alpha)
            previous    = next.value
            hasPrevious = true
        }
    }

    // Draws children in CSS stacking order: negative positioned levels, normal flow, then
    // positive positioned levels.
    private mtd paintChildren(box: u32, offset: Math.Point, alpha: f32)
    {
        .paintStackedChildren(box, offset, alpha, false)
        for child in .layout.constBox(box).children where .stackingLevel(child) == 0 do
            .paintBox(child, offset, alpha)
        .paintStackedChildren(box, offset, alpha, true)
    }

    private mtd paintContents(box: u32, offset: Math.Point, alpha: f32)
    {
        .paintItems(box, offset, alpha)
        .paintChildren(box, offset, alpha)
    }

    // Draws a compact themed scrollbar over an independently scrolling CSS region. Keeping the
    // region inside the document tree preserves CSS layout and hit testing; a native child window
    // per `overflow` box would split one DOM into unrelated coordinate systems.
    private mtd const regionScrollBar(box: u32, rect: Math.Rectangle)->HtmlRegionScrollBar
    {
        var result: retval
        let target = .layout.constBox(box)
        if !target.scrollable or target.scrollHeight <= target.content.height or rect.height <= 0 do
            return result

        let width = Math.min(Math.max(.scrollBarSize, 2), rect.width)
        result.box         = box
        result.track       = rect
        result.track.x     = rect.right() - width
        result.track.width = width

        let limit       = target.scrollHeight - target.content.height
        let thumbHeight = Math.min(Math.max(result.track.height * target.content.height / target.scrollHeight, .scrollThumbMin), result.track.height)
        let travel      = Math.max(result.track.height - thumbHeight, 0)
        result.thumb        = result.track
        result.thumb.y      += limit > 0 ? travel * target.scrollTop / limit : 0
        result.thumb.height = thumbHeight
        result.thumb.x      += width * 0.25
        result.thumb.width  -= width * 0.5
        return result
    }

    private mtd paintRegionScrollBar(box: u32, rect: Math.Rectangle, alpha: f32)
    {
        let bar = .regionScrollBar(box, rect)
        if bar.box == HtmlNoNode do
            return

        if .scrollTrack.a do
            .painter.fillRect(bar.track, HtmlPainter.withAlpha(.scrollTrack, alpha))
        .painter.fillRect(bar.thumb, HtmlPainter.withAlpha(.scrollThumb, alpha))
    }

    // Draws one box and everything under it.
    mtd paintBox(box: u32, parentOffset: Math.Point, alpha: f32)
    {
        let style = .layout.constStyle(.layout.constBox(box).style)
        if !style.visible or style.display == .None do
            return

        var offset = parentOffset
        offset.y += .stickyOffset(box, parentOffset)

        var rect   = .layout.constBox(box).rect
        var bounds = .layout.constBox(box).paintBounds
        rect.offset(offset.x, offset.y)
        bounds.offset(offset.x, offset.y)

        let combined = alpha * style.opacity
        if combined <= 0.004 do
            return

        // Visible overflow can outlive the parent's own rectangle, so prune by the complete
        // subtree extent rather than clipping an image or positioned descendant too early.
        if !bounds.intersects(.visible) do
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
        let clips = style.overflowX != .Visible or style.overflowY != .Visible
        if clips
        {
            var clip = rect
            clip.x      += style.borderLeft.width
            clip.y      += style.borderTop.width
            clip.width  -= style.borderLeft.width + style.borderRight.width
            clip.height -= style.borderTop.width + style.borderBottom.width
            .painter.pushClippingRect(clip)
            defer .painter.popClippingRect()
            inner.y -= .layout.constBox(box).scrollTop
            .paintContents(box, inner, combined)
            .paintRegionScrollBar(box, clip, combined)
            return
        }

        .paintContents(box, inner, combined)
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
    // Returns the frontmost region scrollbar under a point.
    mtd const scrollBarAt(point: Math.Point)->HtmlRegionScrollBar
    {
        if .layout.root == HtmlNoNode do
            return {}
        return .scrollBarAtBox(.layout.root, point, {0, -.scrollY})
    }

    private mtd const scrollBarAtStackedChildren(box: u32, point: Math.Point, offset: Math.Point, positive: bool)->HtmlRegionScrollBar
    {
        let children = .layout.constBox(box).children
        var previous:    s32
        var hasPrevious: bool
        while true
        {
            let next = .nextStackingLevel(box, previous, hasPrevious, positive, false)
            if !next.found do
                return {}
            for index in children.count
            {
                let child = children[children.count - index - 1]
                if .stackingLevel(child) != next.value do
                    continue
                let found = .scrollBarAtBox(child, point, offset)
                if found.box != HtmlNoNode do
                    return found
            }

            previous    = next.value
            hasPrevious = true
        }
    }

    private mtd const scrollBarAtChildren(box: u32, point: Math.Point, offset: Math.Point)->HtmlRegionScrollBar
    {
        let positive = .scrollBarAtStackedChildren(box, point, offset, true)
        if positive.box != HtmlNoNode do
            return positive

        let children = .layout.constBox(box).children
        for index in children.count
        {
            let child = children[children.count - index - 1]
            if .stackingLevel(child) != 0 do
                continue
            let found = .scrollBarAtBox(child, point, offset)
            if found.box != HtmlNoNode do
                return found
        }

        return .scrollBarAtStackedChildren(box, point, offset, false)
    }

    private mtd const scrollBarAtBox(box: u32, point: Math.Point, parentOffset: Math.Point)->HtmlRegionScrollBar
    {
        let style = .layout.constStyle(.layout.constBox(box).style)
        if !style.visible or style.display == .None do
            return {}

        var offset = parentOffset
        offset.y += .stickyOffset(box, parentOffset)

        var rect = .layout.constBox(box).rect
        rect.offset(offset.x, offset.y)
        if !rect.contains(point) do
            return {}

        // A region paints its own bar after its contents, so that bar also wins hit testing over
        // any descendant that happens to extend beneath it.
        var clip = rect
        clip.x      += style.borderLeft.width
        clip.y      += style.borderTop.width
        clip.width  -= style.borderLeft.width + style.borderRight.width
        clip.height -= style.borderTop.width + style.borderBottom.width
        let result = .regionScrollBar(box, clip)
        if result.box != HtmlNoNode and result.track.contains(point) do
            return result

        var inner = offset
        if .layout.constBox(box).scrollable do
            inner.y -= .layout.constBox(box).scrollTop

        return .scrollBarAtChildren(box, point, inner)
    }

    // Returns the innermost node drawn at a point, or `HtmlNoNode` when nothing is.
    mtd const nodeAt(point: Math.Point)->u32
    {
        if .layout.root == HtmlNoNode do
            return HtmlNoNode
        return .nodeAtBox(.layout.root, point, {0, -.scrollY})
    }

    // Hit-tests one sign of positioned stacking levels from front to back.
    private mtd const nodeAtStackedChildren(box: u32, point: Math.Point, offset: Math.Point, positive: bool)->u32
    {
        let children = .layout.constBox(box).children
        var previous:    s32
        var hasPrevious: bool
        while true
        {
            let next = .nextStackingLevel(box, previous, hasPrevious, positive, false)
            if !next.found do
                return HtmlNoNode
            for index in children.count
            {
                let child = children[children.count - index - 1]
                if .stackingLevel(child) != next.value do
                    continue
                let found = .nodeAtBox(child, point, offset)
                if found != HtmlNoNode do
                    return found
            }

            previous    = next.value
            hasPrevious = true
        }
    }

    private mtd const nodeAtChildren(box: u32, point: Math.Point, offset: Math.Point)->u32
    {
        let positive = .nodeAtStackedChildren(box, point, offset, true)
        if positive != HtmlNoNode do
            return positive

        let children = .layout.constBox(box).children
        for index in children.count
        {
            let child = children[children.count - index - 1]
            if .stackingLevel(child) != 0 do
                continue
            let found = .nodeAtBox(child, point, offset)
            if found != HtmlNoNode do
                return found
        }

        return .nodeAtStackedChildren(box, point, offset, false)
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

        let child = .nodeAtChildren(box, point, inner)
        if child != HtmlNoNode do
            return child

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

    // Finds a scrollable box through one sign of positioned stacking levels, frontmost first.
    private mtd const scrollableAtStackedChildren(box: u32, point: Math.Point, offset: Math.Point, positive: bool)->u32
    {
        let children = .layout.constBox(box).children
        var previous:    s32
        var hasPrevious: bool
        while true
        {
            let next = .nextStackingLevel(box, previous, hasPrevious, positive, false)
            if !next.found do
                return HtmlNoNode
            for index in children.count
            {
                let child = children[children.count - index - 1]
                if .stackingLevel(child) != next.value do
                    continue
                let found = .scrollableAtBox(child, point, offset)
                if found != HtmlNoNode do
                    return found
            }

            previous    = next.value
            hasPrevious = true
        }
    }

    private mtd const scrollableAtChildren(box: u32, point: Math.Point, offset: Math.Point)->u32
    {
        let positive = .scrollableAtStackedChildren(box, point, offset, true)
        if positive != HtmlNoNode do
            return positive

        let children = .layout.constBox(box).children
        for index in children.count
        {
            let child = children[children.count - index - 1]
            if .stackingLevel(child) != 0 do
                continue
            let found = .scrollableAtBox(child, point, offset)
            if found != HtmlNoNode do
                return found
        }

        return .scrollableAtStackedChildren(box, point, offset, false)
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

        let child = .scrollableAtChildren(box, point, inner)
        if child != HtmlNoNode do
            return child

        return .layout.constBox(box).scrollable ? box : HtmlNoNode
    }
}

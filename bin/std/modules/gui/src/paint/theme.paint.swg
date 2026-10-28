#global public

using Core, Pixel

impl Theme
{
    // Draws the ring that says the keyboard focus is on `rect`.
    //
    // Call it at the end of the paint of a control that has nothing else to show for the focus —
    // a button, a check box, a picker. A field with its own focus outline and a list with a
    // selected row already say it, and a second mark on them would only be noise.
    //
    // The ring is [[Gui.ThemeMetrics.focusRing_Size]] wide and stands
    // [[Gui.ThemeMetrics.focusRing_Offset]] outside `rect`, so it never touches the control's own
    // edge or fill: it reads the same on a secondary button, on the primary action filled with
    // what acts, and on a switch filled with Arc. Draw it only while [[Gui.Wnd.showsFocusRing]]
    // holds, so a control pressed with the pointer stays unmarked.
    //
    // `corner` is the corner of the control, which the ring follows: stepped out by the offset it
    // stays concentric with the outline it surrounds. A control with no shape of its own — a check
    // box and its label, a slider, a tab — passes zero and gets
    // [[Gui.ThemeMetrics.focusRing_Radius]], which is the softest corner the ring ever takes.
    mtd drawFocusRing(painter: *Painter, rect: Math.Rectangle, corner = 0'f32)
    {
        let color = .colors.focusRing
        if color.a == 0 or rect.isEmpty() do
            return

        // The pen is centered on the path, so the path runs half a ring beyond the gap.
        let size   = .metrics.focusRing_Size
        let offset = .metrics.focusRing_Offset + size * 0.5
        var ring   = rect
        ring.inflate(offset)

        // A pill keeps round ends rather than turning into a lozenge.
        var radius = Math.max(corner + offset, .metrics.focusRing_Radius)
        radius = Math.min(radius, Math.min(ring.width, ring.height) * 0.5)
        painter.drawRoundRect(ring, radius, radius, color, size)
    }

    // Draws a themed image region, using its optional nine-slice margins.
    mtd drawSubRect(painter: *Painter, dstRect: Math.Rectangle, subRect: *ThemeImageRect?, color: Color, center = true, interpol = InterpolationMode.Linear)
    {
        drawSubRect(painter, .res.imgWidgets, dstRect, subRect, color, center, interpol, .res.atlasScale)
    }

    // Draws a texture region, preserving its optional nine-slice borders.
    //
    // `subRect` is expressed in authored atlas texels; `srcScale` maps it onto a texture
    // rasterized that many times larger, as the theme atlas is on a scaled display.
    func drawSubRect(painter: *Painter, texture: Texture, dstRect: Math.Rectangle, subRect: *ThemeImageRect?, color: Color, center = true, interpol = InterpolationMode.Linear, srcScale = 1'f32)
    {
        if not subRect or subRect.rect.isEmpty() or dstRect.isEmpty() or color.a == 0 do
            return

        let k = srcScale > 0 ? srcScale : 1

        // The atlas is rasterized at a whole scale at least as dense as any surface
        // (see [[Gui.Theme.ensureAtlasScale]]), so a fractional content scale samples it
        // at or below 1:1: plain bilinear then behaves as supersampled downscaling
        // and keeps borders even. Only when the mapping still magnifies — an atlas
        // coarser than the surface — does pixel sampling, sharpened by the renderers
        // to one device pixel of smoothing per texel edge, preserve the tile look.
        var effInterpol = interpol
        if painter.contentScale() > k do
            effInterpol = .Pixel
        elif k > 1 do
            effInterpol = .Linear

        let oldInterpol = painter.interpolationMode()
        painter.setInterpolationMode(effInterpol)
        defer painter.setInterpolationMode(oldInterpol)

        if subRect.corner == 0
        {
            painter.drawTexture(dstRect, subRect.rect.scaledFromOrigin(k), texture, color)
            return
        }

        let cx, cy = subRect.corner
        if dstRect.width <= subRect.rect.width and dstRect.height <= subRect.rect.height
        {
            painter.drawTexture(dstRect, subRect.rect.scaledFromOrigin(k), texture, color)
            return
        }

        var cxd, cyd = subRect.corner
        if cxd * 2 > dstRect.width do
            cxd = dstRect.width / 2
        if cyd * 2 > dstRect.height do
            cyd = dstRect.height / 2

        if subRect.keepBordersRatio
        {
            cxd = Math.min(cxd, cyd)
            cyd = cxd
        }

        var d = dstRect
        var s = subRect.rect
        for i in 9
        {
            switch i
            {
            case 0:
                d.width  = cxd
                d.height = cyd
                s.width  = cx
                s.height = cy
                painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)

            case 1, 7:
                d.x     += cxd
                s.x     += cx
                d.width = dstRect.width - (cxd * 2)
                s.width = subRect.rect.width - (cx * 2)
                painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)

            case 2, 8:
                d.x     = dstRect.x + dstRect.width - cxd
                s.x     = subRect.rect.x + subRect.rect.width - cx
                d.width = cxd
                s.width = cx
                painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)

            case 3:
                d.x      = dstRect.x
                d.y      = dstRect.y + cyd
                s.x      = subRect.rect.x
                s.y      = subRect.rect.y + cy
                d.width  = cxd
                s.width  = cx
                d.height = dstRect.height - (cyd * 2)
                s.height = subRect.rect.height - (cy * 2)
                painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)

            case 4:
                d.x      += cxd
                s.x      += cx
                d.width  = dstRect.width - (cxd * 2)
                d.height = dstRect.height - (cyd * 2)
                s.width  = subRect.rect.width - (cx * 2)
                s.height = subRect.rect.height - (cy * 2)
                if center do
                    painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)

            case 5:
                d.x     += d.width
                s.x     += s.width
                d.width = cxd
                s.width = cx
                painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)

            case 6:
                d.x      = dstRect.x
                d.y      = dstRect.y + dstRect.height - cyd
                s.x      = subRect.rect.x
                s.y      = subRect.rect.y + subRect.rect.height - cy
                d.width  = cxd
                d.height = cyd
                s.width  = cx
                s.height = cy
                painter.drawTexture(d, s.scaledFromOrigin(k), texture, color)
            }
        }
    }

    // Draws rich text with an optional leading icon inside `position`.
    func drawIconText(painter: *Painter, position: Math.Rectangle, icon: Icon, name: *RichString, stringFormat: RichStringFormat, iconMargin = 4'f32)
    {
        let count = (name[]).count
        if count == 0 and not icon.isValid() do
            return

        var pos       = position
        let iconColor = icon.color.a ? icon.color : stringFormat.palette[0]

        // Icon alone
        if count == 0
        {
            pos.x = pos.horzCenter() - icon.sizeX * 0.5
            icon.paint(painter, pos.x, pos.vertCenter() - (icon.sizeY * 0.5), iconColor)
            return
        }

        // Text + icon
        if icon.isValid() do
            pos.moveLeft(icon.sizeX + iconMargin)

        // Text
        painter.drawRichString(pos, name, stringFormat)

        // Icon, levelled with the text it leads rather than with the box around it.
        if icon.isValid()
        {
            // A line centered on its own capitals already sits where the eye reads it, so the
            // glyph only has to share that center; a line centered on its box needs the offset
            // between the two. See [[Pixel.Font.opticalLineTop]].
            var top: f32
            if stringFormat.vertAlignment == .OpticalCenter
            {
                top = position.vertCenter() - icon.sizeY * 0.5
            }
            else
            {
                let centerY = stringFormat.vertAlignment == .Center ? position.vertCenter() : name.boundRect.vertCenter()
                top = opticalTop(stringFormat.font, centerY, icon.sizeY)
            }

            icon.paint(painter, name.boundRect.x - icon.sizeX - iconMargin, top, iconColor)
        }
    }

    // Fills the palette of `fmt`: `mainColor` for plain text, then the three rich-text colors of the theme.
    mtd setTextColors(fmt: *RichStringFormat, mainColor: Color)
    {
        fmt.palette[0] = mainColor
        fmt.palette[1] = .colors.richColor1
        fmt.palette[2] = .colors.richColor2
        fmt.palette[3] = .colors.richColor3
    }
}

#global public

using Core, Pixel

impl Theme
{
    // Draws the ring that says the keyboard focus is on `rect`.
    //
    // Call it at the end of the paint of a control that has nothing else to show for the focus —
    // a button, a check box, a picker. A field with a caret and a list with a selected row
    // already say it, and a second mark on them would only be noise.
    //
    // The ring is a rule inside the control, inset by [[Gui.ThemeMetrics.focusRing_Inset]] so it
    // never merges with the control's own border. Draw it only while
    // [[Gui.Wnd.hasVisibleFocus]] holds, so a control pressed with the pointer stays unmarked.
    // Its four corners are cut at 45 degrees, by [[Gui.ThemeMetrics.focusRing_Cut]]: a square
    // corner sitting a couple of pixels inside a rounded one crosses it, and the cut is the
    // identity's own answer to a corner anyway.
    //
    // `onAccent` is for a control filled with the accent — the default action of a dialog — whose
    // fill the ring would otherwise be drawn in and disappear into. See
    // [[Gui.ThemeColors.focusRingOnAccent]].
    mtd drawFocusRing(painter: *Painter, rect: Math.Rectangle, onAccent = false)
    {
        let color = onAccent ? .colors.focusRingOnAccent : .colors.focusRing
        if color.a == 0 do
            return

        var ring = rect
        ring.inflate(-.metrics.focusRing_Inset)
        if ring.isEmpty() do
            return

        // A cut wider than a third of the shorter side would eat the whole corner and leave a
        // lozenge, so the smallest controls simply get a smaller cut.
        let cut = Math.min(.metrics.focusRing_Cut, Math.min(ring.width, ring.height) / 3)
        let l   = ring.x
        let t   = ring.y
        let r   = ring.right()
        let b   = ring.bottom()

        var path: LinePath
        path.start(l + cut, t)
        path.lineTo(r - cut, t)
        path.lineTo(r, t + cut)
        path.lineTo(r, b - cut)
        path.lineTo(r - cut, b)
        path.lineTo(l + cut, b)
        path.lineTo(l, b - cut)
        path.lineTo(l, t + cut)
        path.close()
        painter.drawPath(&path, color, .metrics.focusRing_Size)
    }

    // Draws a themed image region, using its optional nine-slice margins.
    mtd drawSubRect(painter: *Painter, dstRect: Math.Rectangle, subRect: #null *ThemeImageRect, color: Color, center = true, interpol = InterpolationMode.Linear)
    {
        drawSubRect(painter, .res.imgWidgets, dstRect, subRect, color, center, interpol, .res.atlasScale)
    }

    // Draws a texture region, preserving its optional nine-slice borders.
    //
    // `subRect` is expressed in authored atlas texels; `srcScale` maps it onto a texture
    // rasterized that many times larger, as the theme atlas is on a scaled display.
    func drawSubRect(painter: *Painter, texture: Texture, dstRect: Math.Rectangle, subRect: #null *ThemeImageRect, color: Color, center = true, interpol = InterpolationMode.Linear, srcScale = 1'f32)
    {
        if !subRect or subRect.rect.isEmpty() or dstRect.isEmpty() or color.a == 0 do
            return

        var k = srcScale
        if k <= 0 do
            k = 1

        // The atlas is rasterized at a whole scale at least as dense as any surface
        // (see [[Theme.ensureAtlasScale]]), so a fractional content scale samples it
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
        for [i] in 9
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
        let count = @countof(dref name)
        if count == 0 and !icon.isValid() do
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
            let centerY = stringFormat.vertAlignment == .Center ? position.vertCenter() : name.boundRect.vertCenter()
            let top     = opticalTop(stringFormat.font, centerY, icon.sizeY)
            icon.paint(painter, name.boundRect.x - icon.sizeX - iconMargin, top, iconColor)
        }
    }

    // Sets text colors.
    mtd setTextColors(fmt: *RichStringFormat, mainColor: Color)
    {
        fmt.palette[0] = mainColor
        fmt.palette[1] = .colors.richColor1
        fmt.palette[2] = .colors.richColor2
        fmt.palette[3] = .colors.richColor3
    }
}

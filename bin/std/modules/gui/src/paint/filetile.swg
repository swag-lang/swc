#global public
#global namespace FileTile

using Core, Pixel

// How a file preview fits its image area without changing the source texture.
enum Fit
{
    Cover       // Crop around the centre to fill the area.
    Contain     // Keep the whole image inside the area's inset.
    Poster      // Fill with portrait artwork; keep a landscape frame whole over a quiet crop.
}

// Borrowed text and graphics displayed by the file-tile renderer.
//
// The caller keeps all strings, `texture`, and the atlas behind `icon` alive for the paint call.
// Rendering performs no file I/O, decoding, texture upload, texture release or window creation.
struct Content
{
    public
    {
        texture:     Texture = {}     // Preview supplied by the host's renderer.
        icon:        Icon    = {}     // Fallback when no preview is available.
        name:        string  = ""     // Display name below the image.
        facts:       string  = ""     // Secondary information at the start of the metadata line.
        detail:      string  = ""     // Secondary information aligned to the end of that line.
        badge:       string  = ""     // Optional short label over the image's lower trailing corner.
        placeholder: string  = ""     // Optional extension or status below the fallback icon.
    }
}

// Presentation of a virtualized file cell, independent of its host's selection and layout model.
struct Options
{
    public
    {
        fit:         Fit  = .Cover     // Image fitting policy.
        hovered:     bool              // Whether the pointer is over the cell.
        selected:    bool              // Whether the host's selection contains the item.
        showCaption: bool = true       // False displays only the image and its state outline.
        nameTick:    u64               // Animation step for an overflowing active name; zero leaves it at the start.

        // Optional custom preview, called synchronously between the ground and the state overlays.
        //
        // Return true when it painted the preview, false to use the texture or fallback. Restore
        // any painter state changed by the callback before returning.
        previewPainter: (func||(*Wnd, *Painter, Math.Rectangle)->bool)?
    }
}

// Returns the logical height reserved below an image for its name and metadata.
func captionHeight(host: *Wnd)->f32
{
    let metrics = host.themeMetrics()
    return metrics.fileTile_NameGap + metrics.fileTile_NameHeight + metrics.fileTile_FactsHeight
}

// Paints one visible cell in host-local coordinates, borrowing all arguments for this call.
//
// `imageRect` excludes the caption; the caption extends by [[Gui.FileTile.captionHeight]].
// The selection outline extends beyond the image by the theme's ring width and gap. The
// host must reserve that space between cells. Empty image areas paint nothing. Returns whether
// an active name overflows; the host may advance `nameTick` and repaint to reveal the whole name.
#[Swag.Discardable]
func paint(host: *Wnd, painter: *Painter, imageRect: Math.Rectangle, content: const *Content, options: Options = {})->bool
{
    if imageRect.width <= 0 or imageRect.height <= 0 do
        return false
    let colors  = host.themeColors()
    let metrics = host.themeMetrics()
    let radius  = metrics.corner_Control
    painter.setAntialiased(true)
    painter.fillRoundRect(imageRect, radius, radius, colors.raised)
    let custom = options.previewPainter and options.previewPainter(host, painter, imageRect)
    if not custom
    {
        if content.texture.isValid()
        {
            paintImage(host, painter, imageRect, content.texture, options.fit)
        }
        else
        {
            let icon = content.icon
            icon.paint(painter, Math.round(imageRect.horzCenter() - icon.sizeX * 0.5), Math.round(imageRect.vertCenter() - icon.sizeY * 0.5), icon.color.a ? icon.color : colors.faintText)
            if content.placeholder.count != 0
            {
                let font = host.theme().createDefaultFontFs(metrics.fileTile_FactsFontSize)
                painter.drawString(imageRect.x + metrics.fileTile_Inset, font.opticalLineTop(imageRect.bottom() - metrics.fileTile_Inset), content.placeholder, font, colors.faintText)
            }
        }
    }

    if content.badge.count != 0
    {
        let font = host.theme().createDefaultFontFs(metrics.fileTile_FactsFontSize, .Bold)
        let text = Painter.measureString(content.badge, font)
        let pad  = metrics.fileTile_BadgePadding
        let gap  = metrics.fileTile_NameGap
        let size = Math.Point{Math.ceil(text.width) + 2 * pad, Math.ceil(font.height) + pad}
        if size.x + 2 * gap <= imageRect.width and size.y + 2 * gap <= imageRect.height
        {
            let chip = Math.Rectangle{imageRect.right() - size.x - gap, imageRect.bottom() - size.y - gap, size.x, size.y}
            painter.fillRoundRect(chip, radius, radius, colors.surface)
            painter.drawString(chip.x + pad, font.opticalLineTop(chip.vertCenter()), content.badge, font, colors.text)
        }
    }

    if options.selected
    {
        var ring   = imageRect
        let outset = metrics.fileTile_RingWidth + metrics.fileTile_RingGap
        ring.inflate(outset)
        painter.drawRoundRect(ring, radius + outset, radius + outset, colors.arc, metrics.fileTile_RingWidth)
    }
    elif options.hovered
    {
        painter.drawRoundRect(imageRect, radius, radius, colors.strongLine, metrics.fileTile_RingWidth)
    }

    if options.showCaption do
        return paintCaption(host, painter, imageRect, content, options)
    return false
}

private func paintImage(host: *Wnd, painter: *Painter, rect: Math.Rectangle, texture: Texture, fit: Fit)
{
    let radius = host.themeMetrics().corner_Control
    let tw     = cast(f32, texture.width)
    let th     = cast(f32, texture.height)
    if tw <= 0 or th <= 0 do
        return
    let scale = Math.max(rect.width / tw, rect.height / th)
    let sw    = rect.width / scale
    let sh    = rect.height / scale
    var brush = Brush.createTexture(texture)
    brush.uvMode = .FillSubRect
    brush.uvRect = Math.Rectangle{(tw - sw) * 0.5, (th - sh) * 0.5, sw, sh}
    if fit == .Poster and tw > th
    {
        brush.setOpacityF32(0.16)
        painter.fillRoundRect(rect, radius, radius, brush)
        let zoom   = Math.min(rect.width / tw, rect.height / th)
        let width  = Math.round(tw * zoom)
        let height = Math.round(th * zoom)
        let frame  = Math.Rectangle{Math.round(rect.horzCenter() - width * 0.5), Math.round(rect.vertCenter() - height * 0.5), width, height}
        painter.fillRoundRect(frame, radius, radius, Brush.createTexture(texture))
    }
    elif fit == .Contain
    {
        var room = rect
        room.inflate(-Math.min(host.themeMetrics().fileTile_Inset, Math.min(rect.width, rect.height) * 0.5))
        let zoom   = Math.min(room.width / tw, room.height / th)
        let width  = Math.round(tw * zoom)
        let height = Math.round(th * zoom)
        let frame  = Math.Rectangle{Math.round(room.horzCenter() - width * 0.5), Math.round(room.vertCenter() - height * 0.5), width, height}
        painter.fillRoundRect(frame, radius, radius, Brush.createTexture(texture))
    }
    else
    {
        painter.fillRoundRect(rect, radius, radius, brush)
    }
}

private func paintCaption(host: *Wnd, painter: *Painter, tile: Math.Rectangle, content: const *Content, options: Options)->bool
{
    let metrics = host.themeMetrics()
    let colors  = host.themeColors()
    let rect    = Math.Rectangle{tile.x, tile.bottom() + metrics.fileTile_NameGap, tile.width, metrics.fileTile_NameHeight}
    let font    = nnFont(host.font().regular)
    let width   = Painter.measureString(content.name, font).width
    let active  = options.hovered or options.selected
    painter.pushClippingRect(rect)
    if active and width > rect.width
    {
        let distance = cast(u64, Math.ceil(width - rect.width))
        let phase    = options.nameTick % (distance * 2 + 40)
        var offset: u64
        if phase > 20 and phase <= distance + 20 do
            offset = phase - 20
        elif phase > distance + 20 and phase <= distance + 40 do
            offset = distance
        elif phase > distance + 40 do
            offset = distance * 2 + 40 - phase
        painter.drawString(rect.x - cast(f32, offset), font.opticalLineTop(rect.vertCenter()), content.name, font, colors.text)
    }
    else
    {
        let text = Painter.elideString(content.name, font, rect.width, host.deviceScale())
        painter.drawString(rect.x, font.opticalLineTop(rect.vertCenter()), text, font, colors.text)
    }

    painter.popClippingRect()

    let mono   = host.theme().createDefaultFontFs(metrics.fileTile_FactsFontSize)
    let facts  = Math.Rectangle{tile.x, rect.bottom(), tile.width, metrics.fileTile_FactsHeight}
    let y      = mono.opticalLineTop(facts.vertCenter())
    let detail = Painter.elideString(content.detail, mono, facts.width, host.deviceScale())
    var right  = facts.right()
    painter.pushClippingRect(facts)
    if not detail.isEmpty()
    {
        right -= Painter.measureString(detail, mono).width
        painter.drawString(right, y, detail, mono, colors.faintText)
        right -= metrics.fileTile_Inset
    }

    let label = Painter.elideString(content.facts, mono, Math.max(right - facts.x, 0), host.deviceScale())
    painter.drawString(facts.x, y, label, mono, colors.faintText)
    painter.popClippingRect()
    return active and width > rect.width
}

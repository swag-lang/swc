#global internal

using Core, Gui, Pixel

func pictureModeTitle(mode: PictureComparisonMode)->string
{
    let text = appStrings()
    switch #complete mode
    {
    case .SideBySide: return text.scene_SideBySide
    case .Curtain:    return text.scene_Curtain
    case .OnionSkin:  return text.scene_OnionSkin
    case .Difference: return text.scene_Difference
    case .Flip:       return text.scene_Flip
    }
}

struct ComparedDrawing
{
    source:  *ImageView?
    image:   Image
    texture: Texture
}

impl SceneComparison
{
    mtd clearComparedDrawings()
    {
        for &vector in .vectors
        {
            .app().renderer.removeTexture(&vector.texture)
            vector[] = {}
        }
    }

    private mtd comparisonTexture(side: u64, view: *ImageView)->Texture
    {
        let raster = view.presentationTexture()
        if raster.isValid() do
            return raster
        let vector = &.vectors[side]
        if vector.source != view or not vector.texture.isValid()
        {
            let image = view.rasterizeDrawing(2048)
            if not image.isValid() do
                return {}
            .app().renderer.removeTexture(&vector.texture)
            vector.source  = view
            vector.texture = .app().renderer.addImage(image)
            vector.image   = image
        }

        return vector.texture
    }

    private mtd comparisonImage(side: u64, view: *ImageView)->const *Image?
    {
        if let image = view.picture() do
            return image
        let vector = &.vectors[side]
        return vector.source == view and vector.image.isValid() ? &vector.image : null
    }

    mtd paintPictures(painter: *Painter, area: Math.Rectangle)
    {
        let left   = .pictureView(0)
        let right  = .pictureView(1)
        let colors = .themeColors()
        let footer = Math.Rectangle{area.x, area.bottom() - FooterHeight, area.width, FooterHeight}
        let body   = Math.Rectangle{area.x, area.y, area.width, Math.max(area.height - FooterHeight, 0)}
        painter.fillRect(body, Color.fromArgb(Argb.Black))
        painter.fillRect(footer, colors.ground)
        if not left or not right do
            return

        let pictures = [.comparisonTexture(0, left), .comparisonTexture(1, right)]
        if not pictures[0].isValid() or not pictures[1].isValid() do
            return

        var bounds: [2] Math.Rectangle
        for side in 2
        {
            let viewport = .mode == .SideBySide ?
                           Math.Rectangle{body.x + cast(f32, side) * body.width / 2, body.y, body.width / 2, body.height} : body
            bounds[side] = .pictureBounds(viewport, pictures[side], pictures[1 - side], side)
        }

        painter.pushClippingRect(body)
        switch #complete .mode
        {
        case .SideBySide:
            for side in 2
            {
                painter.pushClippingRect({body.x + cast(f32, side) * body.width / 2, body.y, body.width / 2, body.height})
                painter.drawTexture(bounds[side], pictures[side])
                painter.popClippingRect()
            }

            painter.fillRect(body.horzCenter(), body.y, 1, body.height, colors.line)

        case .Curtain:
            let x = Math.round(body.x + body.width * .separator)
            painter.pushClippingRect({x, body.y, body.right() - x, body.height})
            painter.drawTexture(bounds[1], pictures[1])
            painter.popClippingRect()
            painter.pushClippingRect({body.x, body.y, x - body.x, body.height})
            painter.drawTexture(bounds[0], pictures[0])
            painter.popClippingRect()
            painter.fillRect(x, body.y, 1, body.height, Color.fromArgb(Argb.White))
            painter.fillCircle(x, body.vertCenter(), 12, colors.raised)
            painter.drawCircle(x, body.vertCenter(), 12, colors.arc, 1.5)

        case .OnionSkin:
            painter.drawTexture(bounds[0], pictures[0])
            painter.drawTexture(bounds[1], pictures[1], Color.fromArgb(Argb.White).withAlphaF32(.opacity))

        case .Difference:
            let difference = .pictureDifference(pictures)
            if difference.isValid() do
                painter.drawTexture(.pictureBounds(body, difference, difference), difference)

        case .Flip:
            let side = .shownRight ? 1 : 0
            painter.drawTexture(bounds[side], pictures[side])
        }

        painter.popClippingRect()
        .paintPictureNames(painter)
        .paintProbe(painter, footer, bounds, left, right)
    }

    private mtd independentRight(side: u64)->bool
    {
        let scene = unwrap .workspace.scene()
        return .mode == .SideBySide and side == 1 and (not scene.linked or not scene.links.framing)
    }

    mtd pictureZoom(side: u64)->f32 => .independentRight(side) ? .rightZoom : .zoom

    mtd changePictureZoom(side: u64, factor: f32)
    {
        let zoom = Math.clamp(.pictureZoom(side) * factor, 0.1, 20)
        if .independentRight(side) do
            .rightZoom = zoom
        else do
            .zoom = zoom
    }

    mtd synchronizePictureFraming(fromRight: bool)
    {
        if fromRight and .mode == .SideBySide
        {
            .zoom = .rightZoom
            .pan  = .rightPan
        }

        .rightZoom = .zoom
        .rightPan  = .pan
        .refresh()
    }

    private mtd pictureBounds(viewport: Math.Rectangle, image, other: Texture, side = 0'u64)->Math.Rectangle
    {
        let wide   = cast(f32, image.width)
        let high   = cast(f32, image.height)
        let fitW   = .pixelAligned ? cast(f32, Math.max(image.width, other.width)) : wide
        let fitH   = .pixelAligned ? cast(f32, Math.max(image.height, other.height)) : high
        let scale  = Math.min(viewport.width / fitW, viewport.height / fitH) * .pictureZoom(side)
        let pan    = .independentRight(side) ? .rightPan : .pan
        let width  = wide * scale
        let height = high * scale
        return {viewport.horzCenter() - width / 2 + pan.x * viewport.width,
                viewport.vertCenter() - height / 2 + pan.y * viewport.height, width, height}
    }

    private mtd pictureHeader(side: u64)->{name: String, rect: Math.Rectangle}
    {
        let body    = .clientRect()
        let font    = .theme().createDefaultFont(12)
        let metrics = .themeMetrics()
        let inset   = metrics.floating_Inset
        let pad     = 2 * metrics.wnd_CaptionButtonMargin
        let close        = ViewerWorkspace.ViewTitleHeight
        let path: string = .paths[side]
        let name    = Path.fileName(path) orelse path
        var text    = Painter.elideString(name, font, Math.max(0, body.width * 0.5 - 2 * (inset + pad) - close), .deviceScale())
        let width   = Painter.measureString(text, font).width + 2 * pad + close
        let x       = side == 0 ? body.x + inset : body.right() - inset - width
        return {#move text, {x, .stripInset() + inset, width, ViewerWorkspace.ViewTitleHeight}}
    }

    mtd pictureCloseRect(side: u64)->Math.Rectangle
    {
        let header = .pictureHeader(side)
        let size   = header.rect.height
        return {header.rect.right() - size, header.rect.y, size, size}
    }

    mtd showsPictureHeader(side: u64)->bool =>
        .mode != .Flip or (.flipTimer != null and (side != 0) == .shownRight)

    private mtd paintPictureNames(painter: *Painter)
    {
        let colors = .themeColors()
        let font   = .theme().createDefaultFont(12)
        let radius = .themeMetrics().corner_Chip
        for side in 2 where .showsPictureHeader(side)
        {
            let header = .pictureHeader(side)
            let close  = header.rect.height
            painter.fillRoundRect(header.rect, radius, radius, colors.raised)
            painter.drawStringCenter(header.rect.horzCenter() - close * 0.5, header.rect.vertCenter(), header.name, font, colors.text)
        }
    }

    private mtd paintProbe(painter: *Painter, footer: Math.Rectangle, bounds: [2] Math.Rectangle, left, right: *ImageView)
    {
        let a = .comparisonImage(0, left)
        let b = .comparisonImage(1, right)
        if not a or not b do
            return
        let sideBySide = .mode == .SideBySide
        let side       = sideBySide and .pointer.x >= footer.horzCenter() ? 1 : 0
        var pointA     = .pointer
        var pointB     = .pointer
        if sideBySide
        {
            if side == 0 do
                pointB.x += footer.width * 0.5
            else do
                pointA.x -= footer.width * 0.5
        }

        if not bounds[0].contains(pointA) or not bounds[1].contains(pointB) do
            return
        let first  = probePixel(a, bounds[0], pointA)
        let second = probePixel(b, bounds[1], pointB)
        let font   = .theme().createDefaultFontFs(12)
        painter.drawString(footer.x + .themeMetrics().floating_Inset,
                           font.opticalLineTop(footer.vertCenter()),
                           Format.toString("A % % % · B % % %", first.r, first.g, first.b, second.r, second.g, second.b),
                           font,
                           .themeColors().softText)
    }

    private mtd pictureDifference(sources: [2] Texture)->Texture
    {
        var frames: [2] u64
        let scene = unwrap .workspace.scene()
        for side in 2
        {
            if scene.views[side].document?.currentView is Viewers.Film.Panel as film do
                frames[side] = film.frameIndex
        }

        if .diffTexture.isValid() and
           .diffSources == sources and
           .diffFrames == frames and
           .diffAligned == .pixelAligned do
            return .diffTexture

        let width  = Math.max(sources[0].width, sources[1].width)
        let height = Math.max(sources[0].height, sources[1].height)
        if cast(u64, width) * cast(u64, height) > 16 * 1024 * 1024 do
            return {}
        let renderer = .app().renderer
        let left     = renderer.readTexturePixels(sources[0], .RGBA8)
        let right    = renderer.readTexturePixels(sources[1], .RGBA8)
        if left.isEmpty() or right.isEmpty() do
            return {}

        let area    = Math.Rectangle{0, 0, cast(f32, width), cast(f32, height)}
        let sampleA = differenceBounds(area, sources[0], .pixelAligned)
        let sampleB = differenceBounds(area, sources[1], .pixelAligned)
        var image   = Image.create(width, height, .RGBA8)
        for y in height
        {
            for x in width
            {
                let point = Math.Point{cast(f32, x) + 0.5, cast(f32, y) + 0.5}
                let a     = pictureSample(sources[0], left.toSlice(), sampleA, point)
                let b     = pictureSample(sources[1], right.toSlice(), sampleB, point)
                let index = (y * cast(u64, width) + x) * 4
                image.pixels[index]     = amplifiedDifference(a.r, b.r)
                image.pixels[index + 1] = amplifiedDifference(a.g, b.g)
                image.pixels[index + 2] = amplifiedDifference(a.b, b.b)
                image.pixels[index + 3] = 255
            }
        }

        renderer.removeTexture(&.diffTexture)
        .diffTexture = renderer.addImage(image)
        .diffSources = sources
        .diffFrames  = frames
        .diffAligned = .pixelAligned
        return .diffTexture
    }

    mtd picturePointer(evt: *MouseEvent, point: Math.Point)
    {
        .pointer = point
        let body = .clientRect()
        switch evt.kind
        {
        case .Accept:
            evt.accepted = point.y >= .stripInset() and point.y < body.bottom() - FooterHeight

        case .Pressed where evt.button == .Left:
            .drag = true
            .captureMouse()
            if .mode == .Curtain do
                .separator = Math.clamp(point.x / Math.max(body.width, 1), 0, 1)
            if .mode == .SideBySide do
                .workspace.selectView(point.x < body.horzCenter() ? 0 : 1)

        case .Released where .drag:
            .drag = false
            .releaseMouse()

        case .Move:
            if .mode == .Flip and evt.delta != {} do
                .showFlippedName()
            if .drag
            {
                if .mode == .Curtain
                {
                    .separator = Math.clamp(point.x / Math.max(body.width, 1), 0, 1)
                }
                else
                {
                    let side   = .workspace.scene()!.active
                    let width  = .mode == .SideBySide ? body.width * 0.5 : body.width
                    let height = body.height - FooterHeight - .stripInset()
                    let delta  = Math.Point{evt.delta.x / Math.max(width, 1), evt.delta.y / Math.max(height, 1)}
                    if .independentRight(side) do
                        .rightPan += delta
                    else do
                        .pan += delta
                }
            }

        case .Wheel:
            if .mode == .OnionSkin and evt.modifiers.has(.Alt)
            {
                .opacity = Math.clamp(.opacity + (evt.delta.y > 0 ? 0.05 : -0.05), 0, 1)
            }
            else
            {
                let side = .mode == .SideBySide and point.x >= body.horzCenter() ? 1'u64 : 0'u64
                if .mode == .SideBySide do
                    .workspace.selectView(side)
                .changePictureZoom(side, evt.delta.y > 0 ? 1.25 : 0.8)
            }

            .refresh()

        default:
            evt.accepted = false
        }

        .invalidate()
    }
}

private func amplifiedDifference(a, b: u8)->u8 =>
    cast(u8, Math.min(Math.abs(cast(s32, a) - cast(s32, b)) * 4, 255))

private func probePixel(image: const *Image, bounds: Math.Rectangle, point: Math.Point)->Color
{
    let x = cast(s32, cast(f32, image.width) * (point.x - bounds.x) / bounds.width)
    let y = cast(s32, cast(f32, image.height) * (point.y - bounds.y) / bounds.height)
    return image.pixelColor(x, y)
}

private func differenceBounds(area: Math.Rectangle, image: Texture, aligned: bool)->Math.Rectangle
{
    let width  = cast(f32, image.width)
    let height = cast(f32, image.height)
    let scale  = aligned ? 1.0 : Math.min(area.width / width, area.height / height)
    return {area.horzCenter() - width * scale / 2, area.vertCenter() - height * scale / 2, width * scale, height * scale}
}

private func pictureSample(image: Texture, bytes: const [..] u8, bounds: Math.Rectangle, point: Math.Point)->Color
{
    if not bounds.contains(point) do
        return {}
    let sx    = cast(u64, cast(f32, image.width) * (point.x - bounds.x) / bounds.width)
    let sy    = cast(u64, cast(f32, image.height) * (point.y - bounds.y) / bounds.height)
    let index = 4 * (sy * cast(u64, image.width) + sx)
    return Color{r: bytes[index], g: bytes[index + 1], b: bytes[index + 2], a: bytes[index + 3]}
}

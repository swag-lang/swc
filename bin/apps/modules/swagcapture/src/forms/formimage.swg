// What an image form shows: a picture, a blurred, pixelated, or magnified view of the capture
// under it, or a copy of that capture.
enum FormImageKind
{
    Image
    Blur
    Pixelate
    Zoom
    Capture
}

// How a picture sits in its form: stretched to the frame, centered at its own size, or at a free
// rectangle.
enum FormImagePlacement
{
    Frame
    Center
    Free
}

// A rectangle showing a picture or an effect on the capture under it.
#[Swag.Using(Properties)]
#[Serialization.TypeKey("swag.capture.form.image")]
struct FormImage
{
    using base: BaseForm
    image:      Image
    #[Name("Kind"), RecalcLayout]
    kind: FormImageKind = .Image
    #[Name("Strength"), SliderMinMax(0, 100)]
    strength: s32 = 50
    #[Name("Place")]
    place:   FormImagePlacement = .Center
    freePos: Math.Rectangle

    #[Serialization.NoSerialize]
    {
        editInside:       bool
        dirty:            bool
        isReadyToCapture: bool

        serial:      u32
        stc:         s32
        xc, yc:      s32
        wc, hc:      s32
        texture:     Texture
        gizmo:       GizmoRect
        textureKind: FormImageKind = .Image
    }
}

impl FormImage
{
    mtd opDrop()
    {
        if .texture.isValid() do
            g_App.renderer.removeTexture(&.texture)
    }

    mtd opPostCopy()
    {
        Swag.init(&.texture, 1)
    }

    mtd backCaptureMask(mask: *Image)
    {
        let renderer = g_App.renderer

        .image.visitPixels(mask)
        {
            var maskImg = cast(*Image, userData)
            var pix1    = maskImg.pixels.storage() + x * 4
            pix1 += maskImg.width * y * 4
            if not pix1[0] do
                cast(*u32, pix)[] = 0
        }

        renderer.removeTexture(&.texture)
        .texture = g_App.renderer.addImage(.image)
    }

    mtd backCapture()
    {
        let renderer = g_App.renderer
        let capture  = .capture!
        let x1       = cast(s32, .x - capture.backImagePos.x)
        let y1       = cast(s32, .y - capture.backImagePos.y)

        if .w > 1 and .h > 1 and .isReadyToCapture
        {
            .isReadyToCapture = false
            .dirty            = false
            .textureKind      = .kind
            renderer.removeTexture(&.texture)
            .image   = capture.backImg.cropped(x1, y1, .w, .h)
            .texture = g_App.renderer.addImage(.image)
        }
        elif .image.isValid()
        {
            .texture = g_App.renderer.addImage(.image)
        }
    }

    // The glyph of a kind of image form, in the quick-style cells.
    func kindIcon(kind: FormImageKind)->CaptureIcons
    {
        switch #complete kind
        {
        case .Image:    return .Image
        case .Blur:     return .Blur
        case .Pixelate: return .Pixelate
        case .Zoom:     return .Zoom
        case .Capture:  return .Cube
        }
    }

    // Whether the effect texture no longer matches the form: moved, resized, retuned, or computed
    // from a capture image that changed since.
    mtd effectIsStale(capture: *Capture)->bool
    {
        return not .texture.isValid() or .xc != .x or .yc != .y or .wc != .w or .hc != .h or .textureKind != .kind or .dirty or .stc != .strength or .serial != capture.serialBackTexture
    }

    // The effect computed from the capture image under the form: a blurred or pixelated copy, or a
    // magnified middle part.
    mtd effectImage(capture: *Capture)->Image
    {
        let x = cast(s32, .x - capture.backImagePos.x)
        let y = cast(s32, .y - capture.backImagePos.y)
        if .kind == .Zoom
        {
            const ZoomFactor = 2.5
            let stw    = cast(s32, Math.map(cast(f32, .strength), 0, 100, 1, .w / ZoomFactor))
            let sth    = cast(s32, Math.map(cast(f32, .strength), 0, 100, 1, .h / ZoomFactor))
            var result = capture.backImg.cropped(x + stw, y + sth, .w - stw * 2, .h - sth * 2)
            result.resize(.w, .h, .Nearest)
            return result
        }

        var result = capture.backImg.cropped(x, y, .w, .h)
        let st     = Math.map(cast(f32, .strength), 0, 100, 1, 16)
        let nw     = Math.max(cast(s32, result.width / st), 4)
        let nh     = Math.max(cast(s32, result.height / st), 4)
        result.resize(nw, nh, .Quadratic)
        result.resize(.w, .h, .kind == .Pixelate ? .Nearest : .Quadratic)
        return result
    }

    // Brings the texture up to date with what the form shows: its picture, the capture it copies,
    // or the effect it applies.
    mtd refreshTexture()
    {
        let renderer = g_App.renderer
        let capture  = .capture!
        switch .kind
        {
        case .Image:
            if (not .texture.isValid() or .textureKind != .kind or .dirty) and .image.isValid()
            {
                .dirty       = false
                .textureKind = .kind
                renderer.removeTexture(&.texture)
                .texture = renderer.addImage(.image)
                if not .freePos.width do
                    .freePos.width = .image.width
                if not .freePos.height do
                    .freePos.height = .image.height
            }

        case .Capture:
            if not .texture.isValid() or .textureKind != .kind do
                .backCapture()

        case .Blur, .Pixelate, .Zoom:
            if .effectIsStale(capture) and .w > 1 and .h > 1
            {
                .dirty       = false
                .serial      = capture.serialBackTexture
                .textureKind = .kind
                .stc         = .strength
                .xc          = .x
                .yc          = .y
                .wc          = .w
                .hc          = .h
                renderer.removeTexture(&.texture)
                .texture = renderer.addImage(.effectImage(capture))
            }
        }
    }
}

impl IForm for FormImage
{
    mtd impl canRotate()->bool => not .mustEditInside() and .subKind == .None

    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = (catch cast(*FormImage?, ptr))
        if not other do
            return false

        // backColor only matters for the plain image kind; the processed kinds
        // (blur, pixelate, zoom, capture) have no fill.
        return .isSameBase(ptr, compareBackColor: .kind == .Image) and
               .kind == other.kind and
               .strength == other.strength
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let dstf = assume cast(*FormImage, dst)
        let srcf = assume cast(*FormImage, src)
        dstf.kind     = srcf.kind
        dstf.strength = srcf.strength
        if srcf.image.isValid() do
            dstf.image = srcf.image
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        let xa = cast(s32, movingStart.x / zoom)
        let ya = cast(s32, movingStart.y / zoom)
        let xb = cast(s32, localPos.x / zoom)
        let yb = cast(s32, localPos.y / zoom)
        .setBaseForm(xa, ya, xb - xa, yb - ya)
        if evt.kind == .Released and evt.button == .Left
        {
            .isReadyToCapture = true
            return false
        }

        return true
    }

    mtd mustEditInside() => .kind == .Image and .place == .Free and .editInside

    mtd impl moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        if .mustEditInside()
        {
            .freePos.x      += newPosX
            .freePos.y      += newPosY
            .freePos.width  += newSizeX
            .freePos.height += newSizeY
        }
        else
        {
            .moveRectForm(newPosX, newPosY, newSizeX, newSizeY)
        }
    }

    mtd impl scaleBaseForm(scale: f32) => .scaleRectForm(scale)

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        if .mustEditInside()
        {
            if newSizeX < 0
            {
                .freePos.x     = newPosX + newSizeX
                .freePos.width = -newSizeX
            }
            else
            {
                .freePos.x     = newPosX
                .freePos.width = newSizeX
            }

            if newSizeY < 0
            {
                .freePos.y      = newPosY + newSizeY
                .freePos.height = -newSizeY
            }
            else
            {
                .freePos.y      = newPosY
                .freePos.height = newSizeY
            }
        }
        else
        {
            .setRectForm(newPosX, newPosY, newSizeX, newSizeY)
        }
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        if .mustEditInside()
        {
            .freePos.x += newPosX
            .freePos.y += newPosY
        }
        else
        {
            .x += newPosX
            .y += newPosY
        }
    }

    mtd impl movePoint(?: u32, ?, ?: s32) {}

    mtd impl boundRect()->Math.Rectangle => .rectFormBound()

    mtd impl mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        if .kind == .Image and
           .place == .Free and
           evt.kind == .DoubleClick and
           evt.button == .Left and
           .image.isValid()
        {
            .editInside = not .editInside
            return true
        }

        if .mustEditInside()
        {
            evt.modifiers ^= .Shift
        }

        return .gizmo.mouse(view, pos, evt)
    }

    mtd impl paintGizmo(painter: *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            .gizmo.rect          = .boundRect() * z
            .gizmo.rotateValue   = .rotate
            .gizmo.rotateEnabled = .canRotate()
            if .mustEditInside()
            {
                .gizmo.rect.offset(.freePos.x * z, .freePos.y * z)
                .gizmo.rect.width  = .freePos.width * z
                .gizmo.rect.height = .freePos.height * z
                .gizmo.paint(painter, not flags.has(.Selected), Argb.Yellow)
            }
            else
            {
                .gizmo.paint(painter, not flags.has(.Selected))
            }
        }
        else
        {
            .editInside = false
        }
    }

    mtd impl isInside(pt: Math.Point)->bool => .boundRect().contains(pt)

    mtd impl hitTest(pt: Math.Point, z: f32)->bool
    {
        var pp = .boundRect() * z
        if .mustEditInside()
        {
            pp.offset(.freePos.x * z, .freePos.y * z)
            pp.width  = .freePos.width * z
            pp.height = .freePos.height * z
            return pp.contains(pt)
        }

        return pp.contains(pt)
    }

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        let z     = cxt.z
        let bSize = BaseForm.adaptSize(.borderSize, MinBorderSize, MaxBorderSize, cxt)
        var pp    = .boundRect() * z
        let pen   = Pen.createSolid(.borderColor, bSize)

        if not cxt.quickMode do
            .refreshTexture()

        let iconColor = g_App.theme.colors.btnIcon_Icon

        // Both axes must use the same operator so degenerate rects render consistently.
        if .borderColor.a and (pp.width <= 2 * bSize or pp.height <= 2 * bSize)
        {
            painter.fillRect(pp, .borderColor)
        }
        elif cxt.quickMode
        {
            // Reserve room below the icon, but never let a tiny thumbnail's height go
            // negative and invert the rect.
            pp.height = Math.max(pp.height - 10, 1'f32)

            if .kind == .Image do
                painter.fillRect(pp, .backColor)
            var icon = g_Main!.icon(kindIcon(.kind), 48)
            icon.sizeX, icon.sizeY = 32
            icon.paint(painter, pp.horzCenter() - icon.sizeX * 0.5, pp.vertCenter() - icon.sizeY * 0.5, iconColor)
            pp.inflate(-bSize * 0.5)
            painter.drawRect(pp, pen)
        }
        elif .kind == .Capture and not .texture.isValid()
        {
            painter.drawRect(pp, Argb.White, 4)
        }
        elif .kind == .Image and not .image.isValid()
        {
            painter.fillRect(pp, .backColor)
            let icon = g_Main!.icon(.Image, 48)
            icon.paint(painter, pp.horzCenter() - icon.sizeX * 0.5, pp.vertCenter() - icon.sizeY * 0.5, iconColor)
            pp.inflate(-bSize * 0.5)
            painter.drawRect(pp, pen)
        }
        elif .kind == .Image
        {
            painter.fillRect(pp, .backColor)
            switch .place
            {
            case .Frame:
                painter.drawTexture(pp, .texture)

            case .Center:
                var pp1 = pp
                pp1.x      = pp.horzCenter() - (.texture.width / 2) * z
                pp1.y      = pp.vertCenter() - (.texture.height / 2) * z
                pp1.width  = .texture.width * z
                pp1.height = .texture.height * z
                painter.drawTexture(pp1, .texture)

            case .Free:
                var pp1 = pp
                pp1.offset(.freePos.x * z, .freePos.y * z)
                pp1.width  = .freePos.width * z
                pp1.height = .freePos.height * z
                painter.drawTexture(pp1, .texture)
            }

            pp.inflate(-bSize * 0.5)
            painter.drawRect(pp, pen)
        }
        else
        {
            painter.drawTexture(pp, .texture)
            pp.inflate(-bSize * 0.5)
            painter.drawRect(pp, pen)
        }
    }

    mtd impl setup(capt: *Capture)
    {
        .capture = capt
        .gizmo.setupForForm(me)
    }
}

#global public

using Core, Pixel

// Selects the color components mapped to the picker's horizontal and vertical axes.
enum ColorPickerMode
{
    SaturationLightness      // Maps saturation horizontally and lightness vertically.
    HueSaturation            // Maps hue horizontally and saturation vertically.
    HueLightness             // Maps hue horizontally and lightness vertically.
    GreenBlue                // Maps green horizontally and blue vertically.
    RedBlue                  // Maps red horizontally and blue vertically.
    RedGreen                 // Maps red horizontally and green vertically.
    HueVertical              // Maps hue from top to bottom.
    HueHorizontal            // Maps hue from left to right.
    LightnessVertical        // Maps lightness from top to bottom.
    LightnessHorizontal      // Maps lightness from left to right.
    SaturationVertical       // Maps saturation from top to bottom.
    SaturationHorizontal     // Maps saturation from left to right.
    AlphaHorizontal          // Maps alpha from left to right.
    AlphaVertical            // Maps alpha from top to bottom.
    RedHorizontal            // Maps red from left to right.
    RedVertical              // Maps red from top to bottom.
    GreenHorizontal          // Maps green from left to right.
    GreenVertical            // Maps green from top to bottom.
    BlueHorizontal           // Maps blue from left to right.
    BlueVertical             // Maps blue from top to bottom.
}

// Selects a color component or component pair from a rendered gradient.
struct ColorPicker
{
    using wnd: Wnd     // Embedded window behavior and presentation.

    sigColorChanged: SigArray'func||(*ColorPicker)     // Emitted after the selected color changes.

    readonly
    {
        hue, saturation, lightness: f32                // Current HSL components in the closed interval [0, 1].
        alpha, red, green, blue:    f32                // Current ARGB components in the closed interval [0, 1].
        mode = ColorPickerMode.SaturationLightness     // Current component mapping.
    }

    internal
    {
        dirty:            bool = true
        isDragging:       bool
        image:            Image
        texture:          Texture
        cursorX, cursorY: s32
    }
}

impl IWnd for ColorPicker
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .texture.isValid() do
            .app().renderer.removeTexture(&.texture)
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .dirty = true
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        if (evt.kind == .Hide or evt.kind == .Disable) and .isDragging
        {
            .isDragging = false
            .releaseMouse()
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc         = evt.paintContext
        let painter    = bc.painter
        let clientRect = .clientRect()
        let theme      = .theme()
        let rects      = .themeRects()
        let colors     = .themeColors()

        // Reconstruct image
        if .dirty
        {
            .dirty = false
            let imageWidth  = cast(s32) Math.max(clientRect.width, 1)
            let imageHeight = cast(s32) Math.max(clientRect.height, 1)
            if !.image.isValid() or .image.width != imageWidth or .image.height != imageHeight
            {
                .image = Image.create(imageWidth, imageHeight, .RGBA8)
                if .texture.isValid()
                {
                    .app().renderer.removeTexture(&.texture)
                    @init(&.texture, 1)
                }
            }

            var modeFill: Image.FillHslType = undefined

            if .mode == .AlphaHorizontal
            {
                let c  = Color.fromHsl(.hue, .saturation, .lightness)
                var c1 = c
                c1.a = 0
                var c2 = c
                c2.a = 255
                .image.fillGradient(c1, c2)
            }
            elif .mode == .AlphaVertical
            {
                let c  = Color.fromHsl(.hue, .saturation, .lightness)
                var c1 = c
                c1.a = 255
                var c2 = c
                c2.a = 0
                .image.fillGradient(c1, c1, c2, c2)
            }
            elif .mode == .RedHorizontal
            {
                let c  = Color.fromRgbF32(.red, .green, .blue)
                var c1 = c
                c1.r = 0
                var c2 = c
                c2.r = 255
                .image.fillGradient(c1, c2)
            }
            elif .mode == .RedVertical
            {
                let c  = Color.fromRgbF32(.red, .green, .blue)
                var c1 = c
                c1.r = 255
                var c2 = c
                c2.r = 0
                .image.fillGradient(c1, c1, c2, c2)
            }
            elif .mode == .GreenHorizontal
            {
                let c  = Color.fromRgbF32(.red, .green, .blue)
                var c1 = c
                c1.g = 0
                var c2 = c
                c2.g = 255
                .image.fillGradient(c1, c2)
            }
            elif .mode == .GreenVertical
            {
                let c  = Color.fromRgbF32(.red, .green, .blue)
                var c1 = c
                c1.g = 255
                var c2 = c
                c2.g = 0
                .image.fillGradient(c1, c1, c2, c2)
            }
            elif .mode == .BlueHorizontal
            {
                let c  = Color.fromRgbF32(.red, .green, .blue)
                var c1 = c
                c1.b = 0
                var c2 = c
                c2.b = 255
                .image.fillGradient(c1, c2)
            }
            elif .mode == .BlueVertical
            {
                let c  = Color.fromRgbF32(.red, .green, .blue)
                var c1 = c
                c1.b = 255
                var c2 = c
                c2.b = 0
                .image.fillGradient(c1, c1, c2, c2)
            }
            else
            {
                switch .mode
                {
                case .SaturationLightness:
                    modeFill = .SaturationLightness

                case .HueSaturation:
                    modeFill = .HueSaturation

                case .HueLightness:
                    modeFill = .HueLightness

                case .GreenBlue:
                    modeFill = .GreenBlue

                case .RedBlue:
                    modeFill = .RedBlue

                case .RedGreen:
                    modeFill = .RedGreen

                case .HueVertical:
                    modeFill = .HueVert

                case .HueHorizontal:
                    modeFill = .HueHorz

                case .LightnessVertical:
                    modeFill = .LightnessVert

                case .LightnessHorizontal:
                    modeFill = .LightnessHorz

                case .SaturationVertical:
                    modeFill = .SaturationVert

                case .SaturationHorizontal:
                    modeFill = .SaturationHorz

                default:

                    // The gradient modes are all handled by the branches above.
                    unreachable
                }

                .image.fillHsl(modeFill, Color.fromHsl(.hue, .saturation, .lightness))
            }

            if .texture.isValid() do
                .app().renderer.updateTexture(.texture, nnPixels(.image.pixels.buffer))
            else do
                .texture = .app().renderer.addImage(.image)
            .computeXY()
        }

        // Clipping
        painter.startClippingRegion()
        theme.drawSubRect(painter, clientRect, &rects.colorPicker_Bk, Argb.White)
        painter.endClippingRegion()

        // Image
        if .mode == .AlphaHorizontal or .mode == .AlphaVertical do
            painter.fillRect(clientRect, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
        painter.drawTexture(clientRect, .texture)
        painter.resetClippingRegion()

        // Border
        theme.drawSubRect(painter, clientRect, &rects.colorPicker_Border, colors.colorPicker_Border)
    }

    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        let bc         = evt.paintContext
        let painter    = bc.painter
        let theme      = .theme()
        let rects      = .themeRects()
        let clientRect = .clientRect()
        let metrics    = .themeMetrics()
        let colors     = .themeColors()

        switch #complete .mode
        {
        case .SaturationLightness, .HueSaturation, .HueLightness, .GreenBlue, .RedBlue, .RedGreen:
            let size = metrics.colorPicker_RoundPick
            let rect = Math.Rectangle{.cursorX - size, .cursorY - size, 2 * size, 2 * size}
            theme.drawSubRect(painter, rect, &rects.colorPicker_RoundPick, colors.colorPicker_Mark)

        case .RedVertical, .GreenVertical, .BlueVertical, .AlphaVertical, .HueVertical, .LightnessVertical, .SaturationVertical:
            let size = metrics.colorPicker_SquarePick
            let rect = Math.Rectangle{clientRect.horzCenter() - size, .cursorY - size, 2 * size, 2 * size}
            theme.drawSubRect(painter, rect, &rects.colorPicker_SquarePick, colors.colorPicker_Mark)

        case .RedHorizontal, .GreenHorizontal, .BlueHorizontal, .AlphaHorizontal, .HueHorizontal, .LightnessHorizontal, .SaturationHorizontal:
            let size = metrics.colorPicker_SquarePick
            let rect = Math.Rectangle{.cursorX - size, clientRect.vertCenter() - size, 2 * size, 2 * size}
            theme.drawSubRect(painter, rect, &rects.colorPicker_SquarePick, colors.colorPicker_Mark)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        var pos        = .surfaceToLocal(evt.surfacePos)
        let clientRect = .clientRect()
        pos.x = Math.clamp(pos.x, 0, clientRect.width)
        pos.y = Math.clamp(pos.y, 0, clientRect.height)

        switch evt.kind
        {
        case .Pressed:
            if evt.button == .Left
            {
                .isDragging = true
                .captureMouse()
                .invalidate()
                fallthrough
            }

        case .Move:
            if .isDragging and clientRect.width > 0 and clientRect.height > 0
            {
                let x = Math.clamp(pos.x / clientRect.width, 0, 1)
                let y = Math.clamp(pos.y / clientRect.height, 0, 1)

                switch #complete .mode
                {
                case .SaturationLightness:
                    .saturation = Math.clamp(x, 0, 1)
                    let l1 = Math.lerp(1, 0.5, .saturation)
                    .lightness = Math.lerp(l1, 0, y)
                    .computeRGB()

                case .HueSaturation:
                    .hue        = x
                    .saturation = 1 - y
                    .computeRGB()

                case .HueLightness:
                    .hue       = x
                    .lightness = 1 - y
                    .computeRGB()

                case .GreenBlue:
                    .green = x
                    .blue  = y
                    .computeHsl()

                case .RedBlue:
                    .red  = x
                    .blue = y
                    .computeHsl()

                case .RedGreen:
                    .red   = x
                    .green = y
                    .computeHsl()

                case .HueHorizontal:
                    .hue = x
                    .computeRGB()

                case .HueVertical:
                    .hue = y
                    .computeRGB()

                case .LightnessHorizontal:
                    .lightness = x
                    .computeRGB()

                case .LightnessVertical:
                    .lightness = y
                    .computeRGB()

                case .SaturationHorizontal:
                    .saturation = x
                    .computeRGB()

                case .SaturationVertical:
                    .saturation = y
                    .computeRGB()

                case .AlphaHorizontal:
                    .alpha = x

                case .AlphaVertical:
                    .alpha = y

                case .RedHorizontal:
                    .red = x
                    .computeHsl()

                case .RedVertical:
                    .red = y
                    .computeHsl()

                case .GreenHorizontal:
                    .green = x
                    .computeHsl()

                case .GreenVertical:
                    .green = y
                    .computeHsl()

                case .BlueHorizontal:
                    .blue = x
                    .computeHsl()

                case .BlueVertical:
                    .blue = y
                    .computeHsl()
                }

                .computeXY()
                .sigColorChanged.call(me)
                .invalidate()
            }

        case .Released:
            if evt.button == .Left and .isDragging
            {
                .isDragging = false
                .releaseMouse()
                .invalidate()
            }
        }
    }
}

private impl ColorPicker
{
    mtd computeXY()
    {
        let clientRect = .clientRect()

        switch #complete .mode
        {
        case .SaturationLightness:
            .cursorX = cast() (.saturation * clientRect.width)
            let l1 = Math.lerp(1, 0.5, .saturation)
            var l2 = 1 - (.lightness / l1)
            if l2 < 0
            {
                l2       = -l2
                l2       = 1 - l2
                .cursorY = 0
                .cursorX = cast() (l2 * clientRect.width)
            }
            else do
                .cursorY = cast() (l2 * clientRect.height)

        case .HueSaturation:
            .cursorX = cast() (.hue * clientRect.width)
            .cursorY = cast() ((1 - .saturation) * clientRect.height)

        case .HueLightness:
            .cursorX = cast() (.hue * clientRect.width)
            .cursorY = cast() ((1 - .lightness) * clientRect.height)

        case .GreenBlue:
            .cursorX = cast() (.green * clientRect.width)
            .cursorY = cast() (.blue * clientRect.height)

        case .RedBlue:
            .cursorX = cast() (.red * clientRect.width)
            .cursorY = cast() (.blue * clientRect.height)

        case .RedGreen:
            .cursorX = cast() (.red * clientRect.width)
            .cursorY = cast() (.green * clientRect.height)

        case .HueVertical:
            .cursorY = cast() (.hue * clientRect.height)

        case .HueHorizontal:
            .cursorX = cast() (.hue * clientRect.width)

        case .LightnessVertical:
            .cursorY = cast() (.lightness * clientRect.height)

        case .LightnessHorizontal:
            .cursorX = cast() (.lightness * clientRect.width)

        case .SaturationVertical:
            .cursorY = cast() (.saturation * clientRect.height)

        case .SaturationHorizontal:
            .cursorX = cast() (.saturation * clientRect.width)

        case .AlphaHorizontal:
            .cursorX = cast() (.alpha * clientRect.width)

        case .AlphaVertical:
            .cursorY = cast() (.alpha * clientRect.height)

        case .RedHorizontal:
            .cursorX = cast() (.red * clientRect.width)

        case .RedVertical:
            .cursorY = cast() (.red * clientRect.height)

        case .GreenHorizontal:
            .cursorX = cast() (.green * clientRect.width)

        case .GreenVertical:
            .cursorY = cast() (.green * clientRect.height)

        case .BlueHorizontal:
            .cursorX = cast() (.blue * clientRect.width)

        case .BlueVertical:
            .cursorY = cast() (.blue * clientRect.height)
        }
    }

    mtd computeRGB()
    {
        let color = Color.fromHsl(.hue, .saturation, .lightness)
        {.red, .green, .blue} = color.toRgbF32()
    }

    mtd computeHsl()
    {
        let color = Color.fromRgbF32(.red, .green, .blue)
        {.hue, .saturation, .lightness} = color.toHsl()
    }
}

impl ColorPicker
{
    // Creates a saturation-lightness picker initialized to opaque red.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*ColorPicker
    {
        Debug.assert(parent != null)
        let result = Wnd.create'ColorPicker(parent, null, position, id)
        result.wndFlags |= .AfterChildrenPaint
        result.setColor(Argb.Red, false)
        result.invalidatePadding = {-32, -32, -32, -32}
        return result
    }

    // Replaces the HSL and alpha components, clamped to [0, 1].
    mtd setHsla(hue, saturation, lightness, alpha: f32, notify = true)
    {
        let newHue        = Math.clamp(hue, 0, 1)
        let newSaturation = Math.clamp(saturation, 0, 1)
        let newLightness  = Math.clamp(lightness, 0, 1)
        let newAlpha      = Math.clamp(alpha, 0, 1)
        if .hue == newHue and .saturation == newSaturation and .lightness == newLightness and .alpha == newAlpha do
            return

        .hue        = newHue
        .saturation = newSaturation
        .lightness  = newLightness
        .alpha      = newAlpha
        .computeRGB()
        .dirty = true
        .computeXY()
        .invalidate()
        if notify do
            .sigColorChanged.call(me)
    }

    // Replaces the HSL components while preserving alpha.
    mtd setHsl(hue, saturation, lightness: f32, notify = true)
    {
        .setHsla(hue, saturation, lightness, .alpha, notify)
    }

    // Replaces the selected color.
    mtd setColor(color: Color, notify = true)
    {
        let {newAlpha, newRed, newGreen, newBlue} = color.toArgbF32()
        if .alpha == newAlpha and .red == newRed and .green == newGreen and .blue == newBlue do
            return

        {.alpha, .red, .green, .blue} = {newAlpha, newRed, newGreen, newBlue}
        .computeHsl()
        .dirty = true
        .computeXY()
        .invalidate()
        if notify do
            .sigColorChanged.call(me)
    }

    // Returns the selected color.
    mtd const color()->Color
    {
        return Color.fromArgbF32(.alpha, .red, .green, .blue)
    }

    // Changes the component mapping without changing the selected color.
    mtd setMode(mode: ColorPickerMode)
    {
        if .mode == mode do
            return
        .mode  = mode
        .dirty = true
        .computeXY()
        .invalidate()
    }
}

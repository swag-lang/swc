#global public

using Core, Pixel

// Selects the two-dimensional plane and the companion channel slider shown by a color picker control.
enum ColorPickerViewMode
{
    SaturationLightness     // Edits saturation and lightness in the plane, with hue in the slider.
    HueSaturation           // Edits hue and saturation in the plane, with lightness in the slider.
    HueLightness            // Edits hue and lightness in the plane, with saturation in the slider.
    GreenBlue               // Edits green and blue in the plane, with red in the slider.
    RedBlue                 // Edits red and blue in the plane, with green in the slider.
    RedGreen                // Edits red and green in the plane, with blue in the slider.
}

// Configures the channels available in a color picker control.
#[Swag.EnumFlags]
enum ColorPickerFlags
{
    None                 // Edits opaque RGB colors only.
    AllowAlpha           // Enables alpha editing and ARGB hexadecimal input.
    All = AllowAlpha     // Enables every optional channel.
}

// Combines color planes, channel editors, an eyedropper, and an optional palette into one picker.
struct ColorPickerCtrl
{
    using frameWnd: FrameWnd     // Embedded frame wnd state.

    sigColorChanged: SigArray'func||(*ColorPickerCtrl)     // Emitted once after the selected color changes.

    readonly
    {
        originalColor: Color                                // Color captured by the first `setColor` call.
        selectedColor: Color                                // Current selected color.
        flags = ColorPickerFlags.All                        // Available optional channels.
        mode  = ColorPickerViewMode.SaturationLightness     // Active plane and slider arrangement.

        #[Swag.Late]
        {
            preview:   *Wnd             // Side-by-side original and selected color preview.
            pickBox:   *ColorPicker     // Two-dimensional channel picker.
            pickBar:   *ColorPicker     // Companion one-dimensional channel picker.
            pickAlpha: *ColorPicker     // Alpha channel picker.
            editA:     *EditBox         // Alpha numeric editor.
            editR:     *EditBox         // Red numeric editor.
            editG:     *EditBox         // Green numeric editor.
            editB:     *EditBox         // Blue numeric editor.
            editHex:   *EditBox         // RGB or ARGB hexadecimal editor.
            radioH:    *RadioButton     // Hue mode selector.
            radioL:    *RadioButton     // Lightness mode selector.
            radioS:    *RadioButton     // Saturation mode selector.
            radioR:    *RadioButton     // Red mode selector.
            radioG:    *RadioButton     // Green mode selector.
            radioB:    *RadioButton     // Blue mode selector.
        }
    }

    internal
    {
        hasOriginalColor: bool     // Whether the first assigned color has been captured.
    }
}

impl IWnd for ColorPickerCtrl
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPaint(evt)

        var rect    = .preview.position
        let painter = evt.paintContext.painter

        let brush = Brush.createHatch(.CheckBoardLarge, .themeColors().colorPicker_BackAlpha)

        if .originalColor.a != 255 do
            painter.fillRect(rect, brush)
        painter.fillRect(rect, .originalColor)

        rect.x += rect.width
        if .selectedColor.a != 255 do
            painter.fillRect(rect, brush)
        painter.fillRect(rect, .selectedColor)
    }
}

private impl ColorPickerCtrl
{
    mtd updateMode()
    {
        .radioH.setChecked(.mode == .SaturationLightness)
        .radioL.setChecked(.mode == .HueSaturation)
        .radioS.setChecked(.mode == .HueLightness)
        .radioR.setChecked(.mode == .GreenBlue)
        .radioG.setChecked(.mode == .RedBlue)
        .radioB.setChecked(.mode == .RedGreen)
    }

    mtd updatePickers()
    {
        .pickBox.setColor(.selectedColor, false)
        .pickBar.setColor(.selectedColor, false)
        .pickAlpha.setColor(.selectedColor, false)
    }

    mtd updateEdits(notify = false)
    {
        var t = Format.toString("%", .selectedColor.r)
        .editR.setText(t, false)
        t = Format.toString("%", .selectedColor.g)
        .editG.setText(t, false)
        t = Format.toString("%", .selectedColor.b)
        .editB.setText(t, false)
        t = Format.toString("%", .selectedColor.a)
        .editA.setText(t, false)

        if .flags.has(.AllowAlpha) do
            t = Format.toString("%{X08}", .selectedColor.argb)
        else do
            t = Format.toString("%{X02}%{X02}%{X02}", .selectedColor.r, .selectedColor.g, .selectedColor.b)
        .editHex.setText(t, false)

        .preview.invalidate()
        if notify do
            .sigColorChanged.call(me)
    }

    mtd updateAll()
    {
        .updatePickers()
        .updateEdits()
        .updateMode()
    }
}

impl ColorPickerCtrl
{
    // Creates a color picker with channel planes, numeric editors, and an eyedropper.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle, flags = ColorPickerFlags.All, id: #null WndId = null)->*ColorPickerCtrl
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.width == 0 do
            pos.width = 340
        if pos.height == 0 do
            pos.height = 330

        with let v = Wnd.create'ColorPickerCtrl(parent, "", pos, id)
        {
            .flags = flags

            .pickBox   = ColorPicker.create(v, {10, 10, 260, 185})
            .pickBar   = ColorPicker.create(v, {10, 215, 220, 16})
            .pickAlpha = ColorPicker.create(v, {10, 240, 220, 16})

            .preview = Wnd.create'Wnd(v, "", {245, 215, 40, 40})
            var icon = v.theme().icon(.Picker)
            icon.color = Argb.White
            let picker = IconButton.create(v, icon, {245, 215, 40, 40})

            .editA   = EditBox.create(v, "", {10, 265, 50})
            .editR   = EditBox.create(v, "", {70, 265, 50})
            .editG   = EditBox.create(v, "", {125, 265, 50})
            .editB   = EditBox.create(v, "", {180, 265, 50})
            .editHex = EditBox.create(v, "", {240, 265, 90})

            var l = Label.create(v, "A", {.editA.position.x, .editA.position.bottom() + 0, .editA.position.width})
            l.updateFlags(.SecondaryText)
            l = Label.create(v, "R", {.editR.position.x, .editR.position.bottom() + 0, .editR.position.width})
            l.updateFlags(.SecondaryText)
            l = Label.create(v, "G", {.editG.position.x, .editG.position.bottom() + 0, .editG.position.width})
            l.updateFlags(.SecondaryText)
            l = Label.create(v, "B", {.editB.position.x, .editB.position.bottom() + 0, .editB.position.width})
            l.updateFlags(.SecondaryText)

            l = Label.create(v, flags.has(.AllowAlpha) ? "ARGB" : "RGB", {.editHex.position.x, .editHex.position.bottom() + 0, .editHex.position.width})
            l.updateFlags(.SecondaryText)

            .radioH = RadioButton.create(v, "H", {280, 10, 40})
            .radioS = RadioButton.create(v, "S", {280, 40, 40})
            .radioL = RadioButton.create(v, "L", {280, 70, 40})
            .radioR = RadioButton.create(v, "R", {280, 100, 40})
            .radioG = RadioButton.create(v, "G", {280, 130, 40})
            .radioB = RadioButton.create(v, "B", {280, 160, 40})

            picker.sigPressed += func|v|(cb)
            {
                var app   = cb.app()
                var save  = v.color()
                var sfade = app.fadeDisabledSurface
                app.fadeDisabledSurface = false
                discard app.doModalLoop(null,
                                        func|v, save|(app)
                                        {
                                            app.setFrameCursor(Cursor.from(.Cross))

                                            if app.mouse.isButtonPressed(.Right)
                                            {
                                                v.setColor(save)
                                                app.exitModal()
                                                return
                                            }

                                            var col = Application.pickColorAtMouse()
                                            v.setColor(col)

                                            if app.mouse.isButtonPressed(.Left) do
                                                app.exitModal()
                                        })

                app.fadeDisabledSurface = sfade
            }

            .pickBox.sigColorChanged += func|v|(cb)
            {
                if !v.flags.has(.AllowAlpha) do
                    v.selectedColor.a = 255
                switch v.mode
                {
                case .SaturationLightness:
                    let c = Color.fromHsl(v.pickBar.hue, cb.saturation, cb.lightness)
                    v.selectedColor.setArgb(v.selectedColor.a, c.r, c.g, c.b)
                    v.pickAlpha.setHsl(v.pickAlpha.hue, cb.saturation, cb.lightness, false)

                case .HueSaturation:
                    let c = Color.fromHsl(cb.hue, cb.saturation, v.pickBar.lightness)
                    v.selectedColor.setArgb(v.selectedColor.a, c.r, c.g, c.b)
                    v.pickBar.setHsl(cb.hue, cb.saturation, v.pickBar.lightness, false)
                    v.pickAlpha.setHsl(cb.hue, cb.saturation, v.pickAlpha.lightness, false)

                case .HueLightness:
                    let c = Color.fromHsl(cb.hue, v.pickBar.saturation, cb.lightness)
                    v.selectedColor.setArgb(v.selectedColor.a, c.r, c.g, c.b)
                    v.pickBar.setHsl(cb.hue, v.pickBar.saturation, cb.lightness, false)
                    v.pickAlpha.setHsl(cb.hue, v.pickAlpha.saturation, cb.lightness, false)

                case .GreenBlue:
                    v.selectedColor.g = cast(u8) (cb.green * 255)
                    v.selectedColor.b = cast(u8) (cb.blue * 255)
                    v.updatePickers()

                case .RedBlue:
                    v.selectedColor.r = cast(u8) (cb.red * 255)
                    v.selectedColor.b = cast(u8) (cb.blue * 255)
                    v.updatePickers()

                case .RedGreen:
                    v.selectedColor.r = cast(u8) (cb.red * 255)
                    v.selectedColor.g = cast(u8) (cb.green * 255)
                    v.updatePickers()
                }

                v.updateEdits(true)
            }

            .pickBar.sigColorChanged += func|v|(cb)
            {
                switch v.mode
                {
                case .SaturationLightness:
                    let c = Color.fromHsl(v.pickBar.hue, v.pickBox.saturation, v.pickBox.lightness)
                    v.selectedColor.setArgb(v.selectedColor.a, c.r, c.g, c.b)
                    v.pickBox.setHsl(cb.hue, v.pickBox.saturation, v.pickBox.lightness, false)
                    v.pickAlpha.setHsl(cb.hue, v.pickAlpha.saturation, v.pickAlpha.lightness, false)

                case .HueSaturation:
                    let c = Color.fromHsl(v.pickBox.hue, v.pickBox.saturation, v.pickBar.lightness)
                    v.selectedColor.setArgb(v.selectedColor.a, c.r, c.g, c.b)
                    v.pickBox.setHsl(v.pickBox.hue, v.pickBox.saturation, cb.lightness, false)
                    v.pickAlpha.setHsl(v.pickAlpha.hue, v.pickAlpha.saturation, cb.lightness, false)

                case .HueLightness:
                    let c = Color.fromHsl(v.pickBox.hue, v.pickBar.saturation, v.pickBox.lightness)
                    v.selectedColor.setArgb(v.selectedColor.a, c.r, c.g, c.b)
                    v.pickBox.setHsl(v.pickBox.hue, cb.saturation, v.pickBox.lightness, false)
                    v.pickAlpha.setHsl(v.pickAlpha.hue, cb.saturation, v.pickAlpha.lightness, false)

                case .GreenBlue:
                    v.selectedColor.r = cast(u8) (cb.red * 255)
                    v.updatePickers()

                case .RedBlue:
                    v.selectedColor.g = cast(u8) (cb.green * 255)
                    v.updatePickers()

                case .RedGreen:
                    v.selectedColor.b = cast(u8) (cb.blue * 255)
                    v.updatePickers()
                }

                v.updateEdits(true)
            }

            .pickAlpha.setMode(.AlphaHorizontal)
            .pickAlpha.sigColorChanged += func|v|(cb)
            {
                v.selectedColor.a = cast(u8) (cb.alpha * 255)
                v.updateEdits(true)
            }

            .editR.setUnsignedIntegerRange(0, 255)
            .editR.setMaximumLength(3)
            .editR.sigFocusLost += func|v|(ed)
            {
                var res = catch StrConv.parseU32(ed.text())
                v.selectedColor.r = cast() Math.clamp(res.value, 0, 255)
                v.updateAll()
                v.sigColorChanged.call(v)
            }

            .editG.setUnsignedIntegerRange(0, 255)
            .editG.setMaximumLength(3)
            .editG.sigFocusLost += func|v|(ed)
            {
                var res = catch StrConv.parseU32(ed.text())
                v.selectedColor.g = cast() Math.clamp(res.value, 0, 255)
                v.updateAll()
                v.sigColorChanged.call(v)
            }

            .editB.setUnsignedIntegerRange(0, 255)
            .editB.setMaximumLength(3)
            .editB.sigFocusLost += func|v|(ed)
            {
                var res = catch StrConv.parseU32(ed.text())
                v.selectedColor.b = cast() Math.clamp(res.value, 0, 255)
                v.updateAll()
                v.sigColorChanged.call(v)
            }

            .editA.setUnsignedIntegerRange(0, 255)
            .editA.setMaximumLength(3)
            .editA.sigFocusLost += func|v|(ed)
            {
                var res = catch StrConv.parseU32(ed.text())
                v.selectedColor.a = cast() Math.clamp(res.value, 0, 255)
                v.pickAlpha.setColor(v.selectedColor, false)
                v.updateEdits(true)
            }

            .editHex.setHexadecimalRange(0, 0xFFFFFFFF)
            .editHex.setMaximumLength(8)
            .editHex.sigFocusLost += func|v|(ed)
            {
                var res = catch StrConv.parseX64(ed.text())
                if !v.flags.has(.AllowAlpha) do
                    res.value |= 0xFF000000
                v.selectedColor.argb = cast(u32) res.value
                v.updateAll()
                v.sigColorChanged.call(v)
            }

            .radioH.sigChanged += func|v|(bt) { v.setMode(.SaturationLightness); }
            .radioS.sigChanged += func|v|(bt) { v.setMode(.HueLightness); }
            .radioL.sigChanged += func|v|(bt) { v.setMode(.HueSaturation); }
            .radioR.sigChanged += func|v|(bt) { v.setMode(.GreenBlue); }
            .radioG.sigChanged += func|v|(bt) { v.setMode(.RedBlue); }
            .radioB.sigChanged += func|v|(bt) { v.setMode(.RedGreen); }

            if !.flags.has(.AllowAlpha)
            {
                .editA.enable(false)
                .pickAlpha.hide()
                .pickBar.position.height = 40
                .editHex.setHexadecimalRange(0, 0x00FFFFFF)
                .editHex.setMaximumLength(6)
            }
        }

        v.setMode(v.mode)
        return v
    }

    // Creates a color picker with a nine-item palette above it.
    // Missing entries are completed with the built-in default colors.
    #[Swag.Discardable]
    func createWithPalette(parent: *Wnd, position: Math.Rectangle, pal: Array'Color, flags = ColorPickerFlags.All, id: #null WndId = null)->*ColorPickerCtrl
    {
        let picker = ColorPickerCtrl.create(parent, position, flags, id)

        // Setup palette
        with let palette = PalettePicker.create(parent, {16, 16, picker.position.width - 16, 48})
        {
            for [i] in 9
            {
                if i >= pal.count
                {
                    switch i
                    {
                    case 0:
                        .addColor(Argb.White)

                    case 1:
                        .addColor(Argb.Gray)

                    case 2:
                        .addColor(Argb.Black)

                    case 3:
                        .addColor(Argb.Red)

                    case 4:
                        .addColor(Argb.Green)

                    case 5:
                        .addColor(Argb.Blue)

                    case 6:
                        .addColor(Argb.Yellow)

                    case 7:
                        .addColor(Argb.Purple)

                    case 8:
                        if flags.has(.AllowAlpha) do
                            .addColor(Color.fromArgb(0))
                        else do
                            .addColor(Argb.Gold)
                    }
                }
                else
                {
                    palette.addColor(pal[i])
                }
            }

            .setItemMetrics(32, 3)
            .sigSelectionChanged += func|picker|(pal)
            {
                if !pal.selectedColor.a or !picker.selectedColor.a do
                    picker.setColor(pal.selectedColor)
                else do
                    picker.setColorPreservingAlpha(pal.selectedColor)
            }
        }

        return picker
    }

    // Changes the channel plane and companion slider while preserving the selected color.
    mtd setMode(mode: ColorPickerViewMode)
    {
        .mode = mode
        switch .mode
        {
        case .SaturationLightness:
            .pickBox.setMode(.SaturationLightness)
            .pickBar.setMode(.HueHorizontal)

        case .HueSaturation:
            .pickBox.setMode(.HueSaturation)
            .pickBar.setMode(.LightnessHorizontal)

        case .HueLightness:
            .pickBox.setMode(.HueLightness)
            .pickBar.setMode(.SaturationHorizontal)

        case .GreenBlue:
            .pickBox.setMode(.GreenBlue)
            .pickBar.setMode(.RedHorizontal)

        case .RedBlue:
            .pickBox.setMode(.RedBlue)
            .pickBar.setMode(.GreenHorizontal)

        case .RedGreen:
            .pickBox.setMode(.RedGreen)
            .pickBar.setMode(.BlueHorizontal)
        }

        .updateMode()
        .updatePickers()
    }

    // Changes the comparison color shown in the original-color preview.
    mtd setOriginalColor(color: Color)
    {
        var col = color
        if !.flags.has(.AllowAlpha) do
            col.a = 255
        if .hasOriginalColor and .originalColor == col do
            return
        .originalColor    = col
        .hasOriginalColor = true
        .preview.invalidate()
    }

    // Returns the selected color.
    #[Swag.Inline]
    mtd color()->Color
    {
        return .selectedColor
    }

    // Changes the selected RGB channels while preserving alpha.
    mtd setColorPreservingAlpha(color: Color, notify = true)
    {
        var col = color
        col.a = .selectedColor.a
        .setColor(col, notify)
    }

    // Changes the selected color and optionally emits `sigColorChanged` once.
    // The first assigned color is also captured in `originalColor` for the preview.
    mtd setColor(color: Color, notify = true)
    {
        var col = color
        if !.flags.has(.AllowAlpha) do
            col.a = 255

        if !.hasOriginalColor
        {
            .originalColor    = col
            .hasOriginalColor = true
        }
        elif .selectedColor == col
        {
            return
        }

        .selectedColor = col
        .updateAll()
        if notify do
            .sigColorChanged.call(me)
    }
}

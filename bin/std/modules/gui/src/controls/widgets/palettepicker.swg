#global public

using Core, Pixel

// Displays a wrapping palette and lets the user select one color.
struct PalettePicker
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigSelectionChanged: SigArray'func||(*Wnd)     // Emitted after the selected color changes.

        readonly
        {
            colors:        Array'Color            // Colors displayed in insertion order.
            selectedColor: Color                  // Selected color, or transparent black when no item is selected.
            selectedIndex: s32 = Swag.S32.Max     // Selected color index, or `Swag.S32.Max` when absent.
            itemSize:      s32 = 24               // Width and height of each color item, in logical units.
            spacing:       s32 = 3                // Gap between adjacent color items, in logical units.
        }
    }

    itemRects: Array'Math.Rectangle     // Current hit-test rectangle for every color.
    hotIndex:  s32 = Swag.S32.Max       // Item under the pointer, or `Swag.S32.Max`.
}

private impl PalettePicker
{
    mtd updateItemRects()
    {
        let rect = .paddedClientRect()
        .itemRects.resize(.colors.count)

        var x = rect.x
        var y = rect.y
        for i in .colors.count
        {
            .itemRects[i] = Math.Rectangle{x, y, cast(f32, .itemSize), cast(f32, .itemSize)}
            x += .itemSize + .spacing
            if x + .itemSize > rect.right()
            {
                x = rect.x
                y += .itemSize + .spacing
            }
        }
    }

    mtd columnCount()->s32
    {
        let width  = Math.max(.paddedClientRect().width, cast(f32, .itemSize))
        let stride = .itemSize + .spacing
        return Math.max(1, cast(s32, ((width + .spacing) / stride)))
    }
}

impl IWnd for PalettePicker
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .updateItemRects()

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let corner  = metrics.corner_Chip

        // A swatch is a chip with a hairline that keeps a white or a ground-colored one visible.
        // The chosen one is ringed in Arc, a gap away, the way a chosen thumbnail is; the one under
        // the pointer is ringed in the stronger rule.
        let inset      = metrics.palPicker_SwatchInset
        let ringSize   = metrics.focusRing_Size
        let ringOffset = inset - ringSize * 0.5
        painter.setParams(.Antialiased)
        for color, i in .colors
        {
            var swatch = .itemRects[i]
            swatch.inflate(-inset)
            if color.a != 255 do
                painter.fillRoundRect(swatch, corner, corner, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
            painter.fillRoundRect(swatch, corner, corner, color)
            painter.drawRoundRect(swatch, corner, corner, colors.palPicker_Border, metrics.separator_HairlineSize)

            var ringColor: Color
            if i == .selectedIndex do
                ringColor = colors.palPicker_CheckedRing
            elif i == .hotIndex do
                ringColor = colors.palPicker_HotBorder
            if ringColor.a == 0 do
                continue

            var ring = swatch
            ring.inflate(ringOffset)
            painter.drawRoundRect(ring, corner + ringOffset, corner + ringOffset, ringColor, ringSize)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        .updateItemRects()
        let pos = .surfaceToLocal(evt.surfacePos)
        evt.accepted = false

        var newHotIndex = Swag.S32.Max
        for i in .itemRects.count
        {
            if .itemRects[i].contains(pos)
            {
                newHotIndex = cast(i)
                break
            }
        }

        if newHotIndex != .hotIndex
        {
            .hotIndex = newHotIndex
            .invalidate()
        }

        switch evt.kind
        {
        case .Pressed:
            if evt.button == .Left and .hotIndex != Swag.S32.Max
            {
                .setSelectedIndex(.hotIndex)
                evt.accepted = true
            }

        case .Leave:
            if .hotIndex != Swag.S32.Max
            {
                .hotIndex = Swag.S32.Max
                .invalidate()
            }
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed or .colors.isEmpty() do
            return

        var index = .selectedIndex == Swag.S32.Max ? 0 : .selectedIndex
        switch evt.key
        {
        case .Left:  index = Math.max(0, index - 1)
        case .Right: index = Math.min(cast(s32, .colors.count) - 1, index + 1)
        case .Up:    index = Math.max(0, index - .columnCount())
        case .Down:  index = Math.min(cast(s32, .colors.count) - 1, index + .columnCount())
        case .Home:  index = 0
        case .End:   index = cast(s32, .colors.count) - 1
        case .Space, .Return: break
        default:     return
        }

        .setSelectedIndex(index)
        evt.accepted = true
    }
}

impl PalettePicker
{
    // Creates an empty palette picker.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*PalettePicker
    {
        Swag.assert(parent != null)
        let result = Wnd.create'PalettePicker(parent, null, position, id)
        result.focusPolicy = .Tab
        return result
    }

    // Changes color-item size and spacing.
    mtd setItemMetrics(size: s32, spacing: s32)
    {
        Swag.assert(size > 0, "palette item size must be positive")
        Swag.assert(spacing >= 0, "palette spacing cannot be negative")
        if .itemSize == size and .spacing == spacing do
            return
        .itemSize = size
        .spacing  = spacing
        .updateItemRects()
        .invalidate()
    }

    // Selects one color by index and optionally emits [[Gui.PalettePicker.sigSelectionChanged]].
    mtd setSelectedIndex(index: s32, notify = true)
    {
        Swag.assert(index >= 0 and index < .colors.count, "palette color index is out of range")
        if .selectedIndex == index do
            return
        .selectedIndex = index
        .selectedColor = .colors[index]
        .invalidate()
        if notify do
            .sigSelectionChanged.call(me)
    }

    // Clears the current selection and optionally emits [[Gui.PalettePicker.sigSelectionChanged]].
    mtd clearSelection(notify = true)
    {
        if .selectedIndex == Swag.S32.Max do
            return
        .selectedIndex = Swag.S32.Max
        Swag.init(&.selectedColor, 1)
        .invalidate()
        if notify do
            .sigSelectionChanged.call(me)
    }

    // Removes every color and clears the selection without notification.
    mtd clear()
    {
        .colors.clear()
        .itemRects.clear()
        .hotIndex      = Swag.S32.Max
        .selectedIndex = Swag.S32.Max
        Swag.init(&.selectedColor, 1)
        .invalidate()
    }

    // Appends evenly spaced hues without duplicating the circular endpoint.
    mtd addHueRamp(count: s32, saturation, lightness: f32)
    {
        Swag.assert(count >= 0, "palette color count cannot be negative")
        Swag.assert(saturation >= 0 and saturation <= 1, "saturation must be between zero and one")
        Swag.assert(lightness >= 0 and lightness <= 1, "lightness must be between zero and one")
        for i in count
        {
            var color = Color.fromHsl(i / cast(f32, count), saturation, lightness)
            color.a = 255
            .colors.add(color)
        }

        .invalidate()
    }

    // Appends a lightness ramp that includes both endpoints when possible.
    mtd addLightnessRamp(count: s32, base: Color)
    {
        Swag.assert(count >= 0, "palette color count cannot be negative")
        let {h: hue, s: saturation, l: _} = base.toHsl()
        for i in count
        {
            let lightness = count <= 1 ? 0.5 : i / cast(f32, (count - 1))
            var color     = Color.fromHsl(hue, saturation, lightness)
            color.a = 255
            .colors.add(color)
        }

        .invalidate()
    }

    // Appends a saturation ramp that includes both endpoints when possible.
    mtd addSaturationRamp(count: s32, base: Color, lightness: f32 = 0.5)
    {
        Swag.assert(count >= 0, "palette color count cannot be negative")
        Swag.assert(lightness >= 0 and lightness <= 1, "lightness must be between zero and one")
        let {h: hue, s: _, l: _} = base.toHsl()
        for i in count
        {
            let saturation = count <= 1 ? 0 : i / cast(f32, (count - 1))
            var color      = Color.fromHsl(hue, saturation, lightness)
            color.a = 255
            .colors.add(color)
        }

        .invalidate()
    }

    // Appends one color.
    mtd addColor(color: Color)
    {
        .colors.add(color)
        .invalidate()
    }

    // Appends all colors in insertion order.
    mtd addColors(colors: Array'Color)
    {
        .colors.add(colors.toSlice())
        .invalidate()
    }
}

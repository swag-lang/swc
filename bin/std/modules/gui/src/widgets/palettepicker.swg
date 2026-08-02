#global public

using Core, Pixel

// Displays a wrapping palette and lets the user select one color.
struct PalettePicker
{
    using
    wnd: Wnd     // Embedded window behavior and presentation.

    sigSelectionChanged: SigArray'func||(*PalettePicker)     // Emitted after the selected color changes.

    readonly
    {
        colors:        Array'Color            // Colors displayed in insertion order.
        selectedColor: Color                  // Selected color, or transparent black when no item is selected.
        selectedIndex: s32 = Swag.S32.Max     // Selected color index, or `Swag.S32.Max` when absent.
        itemSize:      s32 = 24               // Width and height of each color item, in logical units.
        spacing:       s32 = 3                // Gap between adjacent color items, in logical units.
    }

    internal
    {
        itemRects: Array'Math.Rectangle     // Current hit-test rectangle for every color.
        hotIndex:  s32 = Swag.S32.Max       // Item under the pointer, or `Swag.S32.Max`.
    }
}

private impl PalettePicker
{
    mtd updateItemRects()
    {
        let rect = .paddedClientRect()
        .itemRects.resize(.colors.count)

        var x = rect.x
        var y = rect.y
        for [i] in @countof(.colors)
        {
            .itemRects[i] = {x, y, cast(f32) .itemSize, cast(f32) .itemSize}
            x             += .itemSize + .spacing
            if x + .itemSize > rect.right()
            {
                x = rect.x
                y += .itemSize + .spacing
            }
        }
    }

    mtd columnCount()->s32
    {
        let width  = Math.max(.paddedClientRect().width, cast(f32) .itemSize)
        let stride = .itemSize + .spacing
        return Math.max(1, cast(s32) ((width + .spacing) / stride))
    }
}

impl IWnd for PalettePicker
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .updateItemRects()

        let painter = evt.paintContext.painter
        let colors  = .themeColors()

        for color, [i] in .colors
        {
            var itemRect = .itemRects[i]
            let border   = i == .hotIndex or i == .selectedIndex ? colors.palPicker_HotBorder : colors.palPicker_Border

            painter.setParams(.Antialiased)
            itemRect.inflate(-2)
            if color.a != 255 do
                painter.fillRoundRect(itemRect, 5, 5, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
            painter.fillRoundRect(itemRect, 5, 5, color)
            itemRect.inflate(1)
            painter.drawRoundRect(itemRect, 5, 5, border, 2)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        .updateItemRects()
        let pos = .surfaceToLocal(evt.surfacePos)
        evt.accepted = false

        var newHotIndex = Swag.S32.Max
        for [i] in @countof(.itemRects)
        {
            if .itemRects[i].contains(pos)
            {
                newHotIndex = cast() i
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
        case .Left:           index = Math.max(0, index - 1)
        case .Right:          index = Math.min(cast(s32) .colors.count - 1, index + 1)
        case .Up:             index = Math.max(0, index - .columnCount())
        case .Down:           index = Math.min(cast(s32) .colors.count - 1, index + .columnCount())
        case .Home:           index = 0
        case .End:            index = cast(s32) .colors.count - 1
        case .Space, .Return: break
        default:              return
        }

        .setSelectedIndex(index)
        evt.accepted = true
    }
}

impl PalettePicker
{
    // Creates an empty palette picker.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*PalettePicker
    {
        Debug.assert(parent != null)
        let result = Wnd.create'PalettePicker(parent, null, position, id)
        result.focusStrategy = .OnMousePress
        return result
    }

    // Changes color-item size and spacing.
    mtd setItemMetrics(size: s32, spacing: s32)
    {
        Debug.assert(size > 0, "palette item size must be positive")
        Debug.assert(spacing >= 0, "palette spacing cannot be negative")
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
        Debug.assert(index >= 0 and index < .colors.count, "palette color index is out of range")
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
        @init(&.selectedColor, 1)
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
        @init(&.selectedColor, 1)
        .invalidate()
    }

    // Appends evenly spaced hues without duplicating the circular endpoint.
    mtd addHueRamp(count: s32, saturation, lightness: f32)
    {
        Debug.assert(count >= 0, "palette color count cannot be negative")
        Debug.assert(saturation >= 0 and saturation <= 1, "saturation must be between zero and one")
        Debug.assert(lightness >= 0 and lightness <= 1, "lightness must be between zero and one")
        for [i] in count
        {
            var color = Color.fromHsl(i / cast(f32) count, saturation, lightness)
            color.a = 255
            .colors.add(color)
        }

        .invalidate()
    }

    // Appends a lightness ramp that includes both endpoints when possible.
    mtd addLightnessRamp(count: s32, base: Color)
    {
        Debug.assert(count >= 0, "palette color count cannot be negative")
        let {hue, saturation, ?} = base.toHsl()
        for [i] in count
        {
            let lightness = count <= 1 ? 0.5 : i / cast(f32) (count - 1)
            var color     = Color.fromHsl(hue, saturation, lightness)
            color.a = 255
            .colors.add(color)
        }

        .invalidate()
    }

    // Appends a saturation ramp that includes both endpoints when possible.
    mtd addSaturationRamp(count: s32, base: Color, lightness: f32 = 0.5)
    {
        Debug.assert(count >= 0, "palette color count cannot be negative")
        Debug.assert(lightness >= 0 and lightness <= 1, "lightness must be between zero and one")
        let {hue, ?, ?} = base.toHsl()
        for [i] in count
        {
            let saturation = count <= 1 ? 0 : i / cast(f32) (count - 1)
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

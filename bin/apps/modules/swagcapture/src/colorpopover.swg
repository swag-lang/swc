// The colour popover of the editor: the colours used last, a palette of eight hues in four tints,
// the exact value in hex, and the opacity. It opens under the swatch it changes, from the inspector
// or from the mini-bar.
const PopoverPadding  = 18.0     // Air between the edge of the popover and what it holds.
const PopoverSwatch   = 28.0     // Side of a swatch.
const PopoverGap      = 6.0      // Air between two swatches.
const PopoverColumns  = 8        // Swatches in a row.
const PopoverTitleRow = 20.0     // Height of the title line.
const PopoverLabelRow = 22.0     // Height of a section label.
const PopoverBlockGap = 12.0     // Air between two blocks of the popover.
const PopoverValueRow = 32.0     // Height of the hex field and of the opacity slider.
const PopoverRingGap  = 2.0      // Air between the chosen swatch and its Arc ring.
const MaxRecentColors = 8        // Colours the popover remembers.

// The hues of the palette, one per column; the last is the gray.
const PaletteHues: [PopoverColumns] u32 = [0xFFDC2626, 0xFFEA580C, 0xFFCA8A04, 0xFF16A34A, 0xFF2563EB, 0xFF7C3AED, 0xFFDB2777, 0xFF52525B]

// Returns the colour of the palette at `row` (lightest first) and `column`.
func paletteColor(row, column: u64)->Color
{
    let hue = Color.fromArgb(PaletteHues[column])
    switch row
    {
    case 0: return Color.lerp(hue, Argb.White, 0.85)
    case 1: return Color.lerp(hue, Argb.White, 0.40)
    case 2: return hue
    }

    return Color.lerp(hue, Argb.Black, 0.45)
}

// Returns whether two colours are the same paint, whatever their opacity.
func sameHue(a, b: Color)->bool => a.r == b.r and a.g == b.g and a.b == b.b

// Picks one colour: what the swatches, the hex field and the opacity slider set.
struct ColorPopover
{
    using wnd: Wnd

    sigColorChanged: SigArray'func||(*ColorPopover)     // Emitted after the reader changes the colour.

    color: Color
    title: String

    late
    {
        recent:       *Array'Color     // The colours used last, newest first; the popover adds its picks.
        hexEdit:      *EditBox
        opacity:      *Slider
        opacityValue: *Label
    }

    swatches: Array'(*IconButton)
}

impl IWnd for ColorPopover
{
    // The title, the key that closes the popover, and the swatch of the colour in force.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let theme   = .theme()
        let width   = .clientRect().width

        let titleFont = theme.createDefaultFont(metrics.defaultFontSize, .Bold)
        let titleY    = titleFont.opticalLineTop(PopoverPadding + PopoverTitleRow * 0.5)
        painter.drawString(PopoverPadding, titleY, .title, titleFont, colors.text)

        let keyFont = theme.createDefaultFont(metrics.defaultFontSize - 1)
        let key     = Gui.strings().key_Escape
        painter.drawString(width - PopoverPadding - Painter.measureString(key, keyFont).width, keyFont.opticalLineTop(PopoverPadding + PopoverTitleRow * 0.5), key, keyFont, colors.faintText)

        let current = Math.Rectangle{x: PopoverPadding, y: .hexEdit.position.vertCenter() - PopoverSwatch * 0.5, width: PopoverSwatch, height: PopoverSwatch}
        paintSwatch(painter, current, .color, metrics, colors)
    }
}

impl ColorPopover
{
    // Paints a swatch of `color` in `rect`, the checkerboard showing through a translucent one.
    func paintSwatch(painter: *Painter, rect: Math.Rectangle, color: Color, metrics: const *ThemeMetrics, colors: const *ThemeColors)
    {
        painter.setParams(.Antialiased)
        if not color.isOpaque() do
            painter.fillRoundRect(rect, metrics.corner_Chip, metrics.corner_Chip, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
        painter.fillRoundRect(rect, metrics.corner_Chip, metrics.corner_Chip, color)
        painter.drawRoundRect(rect, metrics.corner_Chip, metrics.corner_Chip, colors.line, metrics.separator_HairlineSize)
    }

    // Returns the size of the popover.
    func size()->Math.Point
    {
        let width  = 2 * PopoverPadding + PopoverColumns * PopoverSwatch + (PopoverColumns - 1) * PopoverGap
        let rows   = PopoverTitleRow + PopoverBlockGap + 2 * (PopoverLabelRow + PopoverSwatch + PopoverBlockGap) + 3 * (PopoverSwatch + PopoverGap)
        let height = 2 * PopoverPadding + rows + PopoverValueRow + PopoverBlockGap + PopoverValueRow
        return {width, height}
    }

    // Opens the popover under `button`, titled `title`, set to `color`; `recent` is the list of the
    // colours used last, which the popover keeps.
    func open(button: *IconButton, title: string, color: Color, recent: *Array'Color)->*ColorPopover
    {
        let size  = size()
        let frame = button.createAnchorPopup(size.x, size.y)
        with let result = Wnd.create'ColorPopover(frame, {})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .color           = color
            .title           = title
            .recent          = recent
        }

        result.build()
        return result
    }

    // Lays out the swatches, the hex field and the opacity slider.
    mtd build()
    {
        let metrics = .themeMetrics()
        let texts   = appStrings()
        var y       = PopoverPadding + PopoverTitleRow + PopoverBlockGap

        SectionLabel.create(me, texts.ui_RecentColors, Math.Rectangle{x: PopoverPadding, y: y, width: 200, height: PopoverLabelRow})
        y += PopoverLabelRow
        for color, i in .recent[]
        {
            if i == PopoverColumns do
                break
            .addSwatch(color, PopoverPadding + cast(f32, i) * (PopoverSwatch + PopoverGap), y)
        }

        y += PopoverSwatch + PopoverBlockGap
        SectionLabel.create(me, texts.ui_Palette, Math.Rectangle{x: PopoverPadding, y: y, width: 200, height: PopoverLabelRow})
        y += PopoverLabelRow
        for row in 4
        {
            for column in PopoverColumns do
                .addSwatch(paletteColor(row, column), PopoverPadding + cast(f32, column) * (PopoverSwatch + PopoverGap), y)
            y += PopoverSwatch + PopoverGap
        }

        // The exact value: the swatch of the colour in force, then its hex, a measure in mono.
        y += PopoverBlockGap - PopoverGap
        let fieldX = PopoverPadding + PopoverSwatch + PopoverBlockGap
        let width  = .size().x
        with .hexEdit = EditBox.create(me, "", Math.Rectangle{x: fieldX, y: y, width: width - fieldX - PopoverPadding, height: PopoverValueRow}, flags: .ReleaseFocusOnEnterOrEscape)
        {
            .style.setFont(me.theme().res.fontDefaultFs)
            .sigCommitted += func|popover = me|(edit)
            {
                let {value, eat, ovf} = catch StrConv.parseX64(edit.text())
                if eat != 6 or ovf do
                    return
                var color = Color.fromArgb(0xFF000000'u32 | cast(u32, value))
                color.a = popover.color.a
                popover.choose(color)
            }
        }

        // The opacity: its word, the slider, the value in percent.
        y += PopoverValueRow + PopoverBlockGap
        let valueWidth = 48.0'f32
        let labelWidth = 64.0'f32
        with let label = Label.create(me, texts.prop_Opacity, Math.Rectangle{x: PopoverPadding, y: y, width: labelWidth, height: PopoverValueRow}, flags: .SecondaryText)
        {
            .setTextAlignment(.Left, .Center)
        }

        with .opacityValue = Label.create(me, "", Math.Rectangle{x: width - PopoverPadding - valueWidth, y: y, width: valueWidth, height: PopoverValueRow})
        {
            .style.setFont(me.theme().res.fontDefaultFs)
            .setTextAlignment(.Right, .Center)
        }

        let sliderX = PopoverPadding + labelWidth
        with .opacity = Slider.create(me, Math.Rectangle{x: sliderX, y: y + (PopoverValueRow - metrics.slider_Height) * 0.5, width: width - sliderX - valueWidth - PopoverPadding - PopoverGap, height: metrics.slider_Height})
        {
            .setBounds(0, 100)
            .sigChanged += func|popover = me|(wnd)
            {
                var color = popover.color
                color.a = cast(u8, Math.round((assume cast(*Slider, wnd)).value() * 255 / 100))
                if color.a != popover.color.a do
                    popover.apply(color)
            }
        }

        .refresh()
    }

    // Adds a swatch of `color` at `left`, `top`; choosing it keeps the opacity in force.
    mtd addSwatch(color: Color, left, top: f32)
    {
        with let swatch = IconButton.create(me, {}, Math.Rectangle{x: left, y: top, width: PopoverSwatch, height: PopoverSwatch}, flags: .Flat)
        {
            .userData = cast(*void, cast(u64, color.argb))
            .toolTip  = Format.toString("%{X02}%{X02}%{X02}", color.r, color.g, color.b)
        }

        swatch.iconPainter = func|popover = me|(btn, bc, _, _)
        {
            let metrics = btn.themeMetrics()
            let colors  = btn.themeColors()
            let color   = Color.fromArgb(cast(u32, cast(u64, btn.userData)))
            var rect    = btn.clientRect()
            rect.inflate(-PopoverRingGap - 1)
            ColorPopover.paintSwatch(bc.painter, rect, color, metrics, colors)
            if sameHue(color, popover.color)
            {
                var ring = btn.clientRect()
                ring.inflate(-1)
                bc.painter.drawRoundRect(ring, metrics.corner_Chip + PopoverRingGap, metrics.corner_Chip + PopoverRingGap, colors.arc, 2)
            }
        }

        swatch.sigPressed += func|popover = me|(btn)
        {
            var color = Color.fromArgb(cast(u32, cast(u64, btn.userData)))
            color.a = popover.color.a
            popover.choose(color)
        }

        .swatches.add(swatch)
    }

    // Takes `color` as a choice of the reader: it joins the recent colours, then applies.
    mtd choose(color: Color)
    {
        for c, i in .recent[] where sameHue(c, color)
        {
            .recent.removeAtOrdered(i)
            break
        }

        .recent.insertAt(0, color)
        while .recent.count > MaxRecentColors do
            .recent.removeBack()
        .apply(color)
    }

    // Sets the colour in force, shows it, and tells the swatch that opened the popover.
    mtd apply(color: Color)
    {
        .color = color
        .refresh()
        .sigColorChanged.call(me)
    }

    // Shows the colour in force: the ring of its swatch, its hex, its opacity.
    mtd refresh()
    {
        if not .hexEdit.hasFocus() do
            .hexEdit.setText(Format.toString("%{X02}%{X02}%{X02}", .color.r, .color.g, .color.b))
        .opacity.setValueWithoutGesture(Math.round(cast(f32, .color.a) * 100 / 255))
        var value = Format.toString("%", cast(s32, Math.round(cast(f32, .color.a) * 100 / 255)))
        value += " %"
        .opacityValue.setText(value)
        .invalidate()
    }
}

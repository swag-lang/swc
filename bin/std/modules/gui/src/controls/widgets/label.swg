#global public

using Core, Pixel

// Configures label text layout and theme emphasis.
#[Swag.EnumFlags]
enum LabelFlags
{
    None = 0          // Uses a single line, primary text color, and caller-controlled height.
    WordWrap          // Wraps text to the available width.
    SecondaryText     // Uses the theme's lower-emphasis text color.
    AutoHeight        // Fits the window height to laid-out text.
    Ellipsis          // Ends an overflowing line with an ellipsis instead of clipping its tail.
}

// Displays rich text and an optional icon, and reports activated links.
struct Label
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigLinkActivated: SigArray'func||(*Label, string)     // Emitted when the user activates a rich-text link.

        readonly
        {
            icon:        Icon                                        // Optional displayed icon.
            iconColor:   Color                                       // Explicit icon color, or transparent for the icon or theme color.
            textColor:   Color                                       // Explicit text color, or transparent for theme colors.
            flags                   = LabelFlags.None                // Active text layout and presentation options.
            maxLines:    u32                                         // Largest number of lines the text may occupy; zero keeps every line.
            iconHorizontalAlignment = StringHorzAlignment.Center     // Horizontal icon alignment.
            iconVerticalAlignment   = StringVertAlignment.Center     // Vertical icon alignment.
            textHorizontalAlignment = StringHorzAlignment.Center     // Horizontal text alignment.
            textVerticalAlignment   = StringVertAlignment.Center     // Vertical text alignment.
            textPadding: Math.Vector4                                // Insets applied to the text layout rectangle.
            iconPadding: Math.Vector4                                // Insets applied to the icon layout rectangle.
        }
    }

    // Rich-text chunk under the mouse, tracked so a link can be hovered and clicked.
    hotChunk: #null *RichChunk
}

impl IWnd for Label
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false
            return

        case .Pressed:
            if evt.button == .Left and .hotChunk do
                .sigLinkActivated.call(me, .hotChunk.slice)
            else do
                evt.accepted = false

        case .Move:
            let chunk = .name.getUrlChunkAt(pos)
            if chunk != .hotChunk
            {
                .invalidate()
                if chunk
                {
                    chunk.isHotUrl = true
                    .app().setFrameCursor(Cursor.from(.Hand))
                }
                elif .hotChunk
                {
                    .hotChunk.isHotUrl = false
                }

                .hotChunk = chunk
            }

        case .Leave:
            if .hotChunk
            {
                .hotChunk.isHotUrl = false
                .hotChunk          = null
                .invalidate()
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let theme   = .theme()
        let painter = evt.paintContext.painter

        let clientRect = .clientRect()
        var pos        = clientRect
        pos.applyPadding(.padding)

        // Icon
        if .icon.isValid()
        {
            var posIcon = pos
            posIcon.applyPadding(.iconPadding)

            switch .iconHorizontalAlignment
            {
            case .Right:  posIcon.x = posIcon.right() - .icon.sizeX
            case .Center: posIcon.x = posIcon.horzCenter() - (.icon.sizeX * 0.5)
            }

            switch .iconVerticalAlignment
            {
            case .Bottom:
                posIcon.y = posIcon.bottom() - .icon.sizeY

            case .Center:

                // Level with the text the label carries, not with the middle of the box: a
                // glyph centered on the cell reads as having slipped below the word beside it.
                // An icon standing alone has nothing to be level with, so it takes the middle.
                if .name.isEmpty() or .textVerticalAlignment != .Center do
                    posIcon.y = posIcon.vertCenter() - (.icon.sizeY * 0.5)
                else do
                    posIcon.y = opticalTop(.font(), posIcon.vertCenter(), .icon.sizeY)
            }

            // Icon
            var color = .iconColor
            if !color.a do
                color = .icon.color
            if !color.a do
                color = (.wndFlags & .Disabled) ? theme.colors.label_DisabledIcon : theme.colors.label_Icon
            .icon.paint(painter, posIcon.x, posIcon.y, color)
        }

        // Text
        if !.name.isEmpty()
        {
            var posText = pos
            posText.applyPadding(.textPadding)

            let sf = .getStringFormat(bc.isDisabled)
            painter.drawRichString(posText, &.name, sf)
        }
    }

    // Reports the room the rich text and the icon need inside the label's own paddings.
    //
    // Both are placed independently in the same rectangle, so the content is as large as
    // the larger of the two rather than as large as their sum.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        var result: retval

        if !.name.isEmpty()
        {
            let sf = .getStringFormat(false)

            // Wrapped text is only as tall as the width it is given; measuring it
            // unconstrained would report one long line and hide the wrap entirely.
            var layout = Math.Rectangle{0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}
            if .flags.has(.WordWrap) and available.x > 0 do
                layout.width = Math.max(available.x - .padding.x - .padding.z - .textPadding.x - .textPadding.z, 1)

            .name.compute()
            Painter.computeLayout(layout, &.name, sf, .deviceScale())

            result.x = .name.boundRect.width + .textPadding.x + .textPadding.z
            result.y = Math.max(.name.boundRect.height, sf.font.regular!.height) + .textPadding.y + .textPadding.w
        }

        if .icon.isValid()
        {
            result.x = Math.max(result.x, .icon.sizeX + .iconPadding.x + .iconPadding.z)
            result.y = Math.max(result.y, .icon.sizeY + .iconPadding.y + .iconPadding.w)
        }

        if result.x > 0 do
            result.x += .padding.x + .padding.z
        if result.y > 0 do
            result.y += .padding.y + .padding.w
        return result
    }
}

// Layout extent standing in for an unconstrained axis when measuring text.
internal const MaxTextLayoutExtent = 8192.0'f32

impl Label
{
    private mtd getStringFormat(isDisabled: bool)->RichStringFormat
    {
        let theme = .theme()

        var sf: retval
        sf.flags |= .Clip
        if .flags.has(.WordWrap) do
            sf.flags.add(.WordWrap)
        if .flags.has(.Ellipsis) do
            sf.flags.add(.Ellipsis)
        sf.font          = .font()
        sf.horzAlignment = .textHorizontalAlignment
        sf.vertAlignment = .textVerticalAlignment
        sf.maxLines      = .maxLines

        if .textColor.a
        {
            sf.palette[0]  = .textColor
            sf.palette[1]  = .textColor
            sf.palette[2]  = .textColor
            sf.palette[3]  = .textColor
            sf.colorUrl    = .textColor
            sf.colorHotUrl = .textColor
        }
        elif isDisabled
        {
            sf.palette[0]  = theme.colors.label_DisabledText
            sf.palette[1]  = theme.colors.label_DisabledText
            sf.palette[2]  = theme.colors.label_DisabledText
            sf.palette[3]  = theme.colors.label_DisabledText
            sf.colorUrl    = theme.colors.label_DisabledText
            sf.colorHotUrl = theme.colors.label_DisabledText
        }
        else
        {
            if .flags.has(.SecondaryText) do
                sf.palette[0] = theme.colors.label_TextLight
            else do
                sf.palette[0] = theme.colors.label_Text
            sf.palette[1]  = theme.colors.richColor1
            sf.palette[2]  = theme.colors.richColor2
            sf.palette[3]  = theme.colors.richColor3
            sf.colorUrl    = theme.colors.url_Text
            sf.colorHotUrl = theme.colors.url_HotText
        }

        return sf
    }

    // Creates a label with optional wrapping, sizing, and link behavior.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: #null string, position: Math.Rectangle = {}, id: #null WndId = null, flags: LabelFlags = .None)->*Label
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().label_Height
        let lbl = Wnd.create'Label(parent, "", pos, id)
        lbl.flags = flags
        if flags.has(.AutoHeight) and position.height == 0 do
            lbl.releaseAutomaticHeight()
        lbl.setText(name)
        return lbl
    }

    // Replaces the displayed rich text and reapplies automatic sizing.
    mtd setText(text: #null string)
    {
        if .name == (text orelse "") do
            return
        .name.set(text)
        .invalidate()
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    // Returns the displayed plain text.
    mtd text()->string
    {
        return .name.raw
    }

    // Adds and removes label options, then updates layout and presentation.
    mtd updateFlags(add: LabelFlags = .None, remove = LabelFlags.None)
    {
        var newFlags = .flags
        newFlags.add(add)
        newFlags.remove(remove)
        if .flags == newFlags do
            return
        .flags = newFlags
        if add.has(.AutoHeight) do
            .releaseAutomaticHeight()
        .invalidate()
        .updateAutomaticHeight()
    }

    // Hands the height over to the text, so a container measures it instead of reading it.
    //
    // [[Gui.LabelFlags.AutoHeight]] means the text decides, and a layout pass only asks a
    // window for its content on an axis carrying no authored size. Creating the label
    // still leaves a sane height in `position` for a label that is painted before any
    // layout pass runs.
    private mtd releaseAutomaticHeight()
    {
        .preferredSize.y = 0
        .invalidateLayout()
    }

    // Caps the number of lines the text may occupy; zero lifts the cap.
    //
    // The text stops at that line instead of running past the label. Combine it with
    // [[Gui.LabelFlags.Ellipsis]] to have the last kept line end with an ellipsis, so a reader
    // sees that something was left out rather than a sentence that appears to end there.
    mtd setMaxLines(count: u32)
    {
        if .maxLines == count do
            return
        .maxLines = count
        .invalidate()
        .updateAutomaticHeight()
    }

    // Changes text alignment and updates automatic height when needed.
    mtd setTextAlignment(horizontal: StringHorzAlignment, vertical: StringVertAlignment)
    {
        if .textHorizontalAlignment == horizontal and .textVerticalAlignment == vertical do
            return
        .textHorizontalAlignment = horizontal
        .textVerticalAlignment   = vertical
        .invalidate()
        .updateAutomaticHeight()
    }

    // Changes horizontal text alignment.
    mtd setTextHorizontalAlignment(alignment: StringHorzAlignment)
    {
        .setTextAlignment(alignment, .textVerticalAlignment)
    }

    // Changes vertical text alignment.
    mtd setTextVerticalAlignment(alignment: StringVertAlignment)
    {
        .setTextAlignment(.textHorizontalAlignment, alignment)
    }

    // Changes icon alignment.
    mtd setIconAlignment(horizontal: StringHorzAlignment, vertical: StringVertAlignment)
    {
        if .iconHorizontalAlignment == horizontal and .iconVerticalAlignment == vertical do
            return
        .iconHorizontalAlignment = horizontal
        .iconVerticalAlignment   = vertical
        .invalidate()
    }

    // Changes horizontal icon alignment.
    mtd setIconHorizontalAlignment(alignment: StringHorzAlignment)
    {
        .setIconAlignment(alignment, .iconVerticalAlignment)
    }

    // Changes vertical icon alignment.
    mtd setIconVerticalAlignment(alignment: StringVertAlignment)
    {
        .setIconAlignment(.iconHorizontalAlignment, alignment)
    }

    // Changes text insets and updates automatic height when needed.
    mtd setTextPadding(padding: Math.Vector4)
    {
        if .textPadding == padding do
            return
        .textPadding = padding
        .invalidate()
        .updateAutomaticHeight()
    }

    // Changes icon insets.
    mtd setIconPadding(padding: Math.Vector4)
    {
        if .iconPadding == padding do
            return
        .iconPadding = padding
        .invalidate()
    }

    // Changes the displayed icon.
    mtd setIcon(icon: Icon)
    {
        .icon = icon
        .invalidate()
    }

    // Changes the explicit icon color; transparent restores automatic coloring.
    mtd setIconColor(color: Color)
    {
        .iconColor = color
        .invalidate()
    }

    // Changes the explicit text color; transparent restores theme coloring.
    mtd setTextColor(color: Color)
    {
        .textColor = color
        .invalidate()
    }

    // Recomputes height from current text, width, font, flags, and text padding.
    //
    // A label under a layout container does not need this: [[Gui.LabelFlags.AutoHeight]]
    // already hands the height to the measure pass. Call it for a label placed by hand,
    // to read the right `position.height` back straight away. The method has no effect
    // unless `AutoHeight` is active.
    mtd updateAutomaticHeight()
    {
        if .flags.has(.AutoHeight)
        {
            let sf   = .getStringFormat(false)
            var rect = .position
            if rect.width <= 0 do
                rect.width = .preferredSize.x
            if rect.height <= 0 do
                rect.height = sf.font.regular!.height

            // The text is drawn inside textPadding, so wrap against that inset width (else a
            // padded label under-measures and clips), and add the vertical inset back in.
            rect.applyPadding(.textPadding)

            .name.compute()
            Painter.computeLayout(rect, &.name, sf, .deviceScale())

            var height = .name.boundRect.height
            if !.name.isEmpty() do
                height = Math.max(height, sf.font.regular!.height)
            height           += .textPadding.y + .textPadding.w
            .position.height = height
            .invalidateLayout()
        }
    }
}

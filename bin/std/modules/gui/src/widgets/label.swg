#global public

using Core, Pixel

// Configures label text layout and theme emphasis.
#[Swag.EnumFlags]
enum LabelFlags
{
    None = 0                     // Uses a single line, primary text color, and caller-controlled height.
    WordWrap                     // Wraps text to the available width.
    SecondaryText                // Uses the theme's lower-emphasis text color.
    AutoHeight                   // Fits the window height to laid-out text.
    PreserveSingleLineHeight     // Preserves the font line box instead of adapting it to visible glyphs.
}

// Displays rich text and an optional icon, and reports activated links.
struct Label
{
    using wnd: Wnd     // Embedded window behavior and presentation.

    sigLinkActivated: SigArray'func||(*Label, string)     // Emitted when the user activates a rich-text link.

    readonly
    {
        icon:        Icon                                        // Optional displayed icon.
        iconColor:   Color                                       // Explicit icon color, or transparent for the icon or theme color.
        textColor:   Color                                       // Explicit text color, or transparent for theme colors.
        flags                   = LabelFlags.None                // Active text layout and presentation options.
        iconHorizontalAlignment = StringHorzAlignment.Center     // Horizontal icon alignment.
        iconVerticalAlignment   = StringVertAlignment.Center     // Vertical icon alignment.
        textHorizontalAlignment = StringHorzAlignment.Center     // Horizontal text alignment.
        textVerticalAlignment   = StringVertAlignment.Center     // Vertical text alignment.
        textPadding: Math.Vector4                                // Insets applied to the text layout rectangle.
        iconPadding: Math.Vector4                                // Insets applied to the icon layout rectangle.
    }

    // Rich-text chunk under the mouse, tracked so a link can be hovered and clicked.
    internal
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
            case .Bottom: posIcon.y = posIcon.bottom() - .icon.sizeY
            case .Center: posIcon.y = posIcon.vertCenter() - (.icon.sizeY * 0.5)
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

            // Optically center the text against a vertically-centered icon. A glyph line box is
            // descent-heavy, so geometric centering leaves the visible text sitting slightly high of
            // a centered icon. When an icon is present, the text is vertically centered, and the
            // caller has not already nudged it by hand (textPadding.y == 0), shift the text down by
            // half the (negative) descent. This is the general fix for the recurring icon+text
            // vertical-alignment mismatch — callers no longer need to hand-tune textPadding.
            if .icon.isValid() and .textVerticalAlignment == .Center and .textPadding.y == 0
            {
                let font = .font().regular
                if font do
                    posText.y -= font.descent * 0.5
            }

            let sf = .getStringFormat(bc.isDisabled)
            painter.drawRichString(posText, &.name, sf)
        }
    }
}

impl Label
{
    private mtd getStringFormat(isDisabled: bool)->RichStringFormat
    {
        let theme = .theme()

        var sf: retval
        sf.flags |= .Clip
        if .flags.has(.WordWrap) do
            sf.flags.add(.WordWrap)
        if .flags.has(.PreserveSingleLineHeight) do
            sf.flags.add(.DontAdaptSingleLineHeight)
        sf.font          = .font()
        sf.horzAlignment = .textHorizontalAlignment
        sf.vertAlignment = .textVerticalAlignment

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
            sf.palette[1]  = theme.colors.label_Text1
            sf.palette[2]  = theme.colors.label_Text2
            sf.palette[3]  = theme.colors.label_Text3
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
        lbl.setText(name)
        return lbl
    }

    // Replaces the displayed rich text and reapplies automatic sizing.
    mtd setText(text: #null string)
    {
        .name.set(text)
        .invalidate()
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
    // This method has no effect unless [[LabelFlags.AutoHeight]] is active.
    mtd updateAutomaticHeight()
    {
        if .flags.has(.AutoHeight)
        {
            let sf   = .getStringFormat(false)
            var rect = .position
            if rect.width <= 0 do
                rect.width = .preferredSize.x
            if rect.height <= 0 do
                rect.height = .preferredSize.y
            if rect.height <= 0 do
                rect.height = (notnull sf.font.regular).height

            // The text is drawn inside textPadding, so wrap against that inset width (else a
            // padded label under-measures and clips), and add the vertical inset back in.
            rect.applyPadding(.textPadding)

            .name.compute()
            Painter.computeLayout(rect, &.name, sf, .deviceScale())

            var height = .name.boundRect.height
            if !.name.isEmpty() do
                height = Math.max(height, (notnull sf.font.regular).height)
            height           += .textPadding.y + .textPadding.w
            .position.height = height
            .preferredSize.y = height
        }
    }
}

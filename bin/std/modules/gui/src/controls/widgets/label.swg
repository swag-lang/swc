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
    LinkActions       // Keeps links underlined and exposes their actions to keyboard traversal.
}

// Displays text and an optional icon, and reports activated links.
//
// The text given at creation and through [[Gui.Label.setText]] is literal. A sentence that
// styles some of its words is written in inline markup and given to [[Gui.Label.setMarkup]],
// or built as a [[Pixel.RichString]] and given to [[Gui.Label.setRichText]].
//
// Use [[Gui.LabelFlags.LinkActions]] for an action inside prose. The rich string owns wrapping,
// baseline alignment and trailing text; disabling links keeps the rest of the paragraph readable.
//
// ```swag
// let sentence = Label.createMarkup(parent, "Retry after <a>15\u00A0minutes</a>.", flags: .LinkActions)
// sentence.setLinksEnabled(false)
// ```
struct Label
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigLinkActivated: SigArray'func||(*Wnd, string)     // Emitted with the target of the link the user activates.
        accessKeyTarget: *Wnd? = null     // Same-surface window focused when this label's access key is chosen.

        readonly
        {
            icon:         Icon                                       // Optional displayed icon.
            iconColor:    Color                                      // Fallback for an icon without an intrinsic tint; transparent uses the theme.
            textColor:    Color                                      // Explicit text color, or transparent for theme colors.
            flags = LabelFlags.None                                  // Active text layout and presentation options.
            linksEnabled: bool      = true                           // Whether inline links can be activated.
            lineGap:      s32                                        // Extra space between text lines, in logical pixels; zero by default.
            maxLines:     u32                                        // Largest number of lines the text may occupy; zero keeps every line.
            iconHorizontalAlignment = StringHorzAlignment.Center     // Horizontal icon alignment.
            iconVerticalAlignment   = StringVertAlignment.Center     // Vertical icon alignment.
            textHorizontalAlignment = StringHorzAlignment.Center     // Horizontal text alignment.
            textVerticalAlignment   = StringVertAlignment.Center     // Vertical text alignment.
            textPadding:  Math.Vector4                               // Insets applied to the text layout rectangle.
            iconPadding:  Math.Vector4                               // Insets applied to the icon layout rectangle.
        }
    }

    letterSpacing: f32
    localizedTextSource: const *string? = null     // Borrowed catalog field refreshed on language changes.

    // Rich-text chunk under the mouse, tracked so a link can be hovered and clicked.
    hotChunk:   *RichChunk?
    activeLink: u64 = Swag.U64.Max
}

impl IWnd for Label
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        .wnd.IWnd.onNotifyEvent(evt)
        if evt.kind == .LanguageChanged do
            .refreshLocalizedText()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false
            return

        case .Pressed:
            if evt.button == .Left and .linksEnabled and .hotChunk
            {
                if .flags.has(.LinkActions)
                {
                    .setFocus()
                    for &chunk, index in .name.chunks where chunk == .hotChunk do
                        .activeLink = index
                }

                let target = .name.urlTarget(.hotChunk.urlStart)
                .sigLinkActivated.call(me, target.toString())
            }
            else
            {
                evt.accepted = false
            }

        case .Move:
            let chunk = .linksEnabled ? .name.getUrlChunkAt(pos) : null
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
                .hotChunk = null
                .invalidate()
            }
        }
    }

    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        .wnd.IWnd.onFocusEvent(evt)
        if evt.kind == .Gained do
            .activeLink = .actionLink(Swag.U64.Max, false)
        elif evt.kind == .Lost do
            .activeLink = Swag.U64.Max
        .invalidate()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed or not .linksEnabled or not .flags.has(.LinkActions) do
            return
        if evt.key == .Tab and (evt.modifiers == .None or evt.modifiers == .Shift)
        {
            let next = .actionLink(.activeLink, evt.modifiers == .Shift)
            if next != Swag.U64.Max
            {
                .activeLink = next
                .invalidate()
                evt.accepted = true
            }
        }
        elif (evt.key == .Enter or evt.key == .Space) and
             evt.modifiers == .None and
             .activeLink < .name.chunks.count
        {
            let target = .name.urlTarget(.name.chunks[.activeLink].urlStart)
            .sigLinkActivated.call(me, target.toString())
            evt.accepted = true
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
            if not color.a do
                color = (.wndFlags & .Disabled) ? theme.colors.label_DisabledIcon : theme.colors.label_Icon
            .icon.paint(painter, posIcon.x, posIcon.y, color)
        }

        // Text
        if not .name.isEmpty()
        {
            var posText = pos
            posText.applyPadding(.textPadding)

            let sf = .getStringFormat(bc.isDisabled)
            if .flags.has(.LinkActions)
            {
                for &chunk in .name.chunks where chunk.isUrl do
                    chunk.isHotUrl = (.hotChunk and chunk.urlStart == .hotChunk.urlStart) or
                                     (.activeLink < .name.chunks.count and chunk.urlStart == .name.chunks[.activeLink].urlStart and .hasVisibleFocus())
            }

            drawAccessKeyText(painter, posText, &.name, sf, me.accessKey,
                              .surface?.accessKeysVisible orelse false)
        }
    }

    // Reports the room the rich text and the icon need inside the label's own paddings.
    //
    // Both are placed independently in the same rectangle, so the content is as large as
    // the larger of the two rather than as large as their sum.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        var result: #returntype

        if not .name.isEmpty()
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
    // Sets the extra spacing inserted between glyphs, in logical pixels.
    mtd setLetterSpacing(spacing: f32)
    {
        .letterSpacing = spacing
        .invalidate()
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    private mtd getStringFormat(isDisabled: bool)->RichStringFormat
    {
        let theme = .theme()

        var sf: #returntype
        sf.flags |= .Clip
        if .flags.has(.WordWrap) do
            sf.flags.add(.WordWrap)
        if .flags.has(.Ellipsis) do
            sf.flags.add(.Ellipsis)
        sf.font                = .font()
        sf.horzAlignment       = .textHorizontalAlignment
        sf.vertAlignment       = .textVerticalAlignment
        sf.maxLines            = .maxLines
        sf.lineGap             = .lineGap
        sf.letterSpacing       = .letterSpacing
        sf.urlsEnabled         = .linksEnabled and not isDisabled
        sf.underlineUrls       = .flags.has(.LinkActions)
        sf.urlUnderlineOpacity = .themeMetrics().label_LinkUnderlineOpacity
        sf.colorDisabledUrl    = theme.colors.label_DisabledText

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

    // Creates a label showing the literal text `name`.
    //
    // `flags` controls wrapping, automatic sizing, emphasis, ellipsis, and link actions.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string?, position: Math.Rectangle = {}, id: WndId? = null, flags: LabelFlags = .None)->*Label
    {
        Swag.assert(parent != null)
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

    // Creates a label showing a sentence written in inline markup, as [[Gui.Label.create]] does
    // with literal text.
    //
    // See [[Gui.Label.setMarkup]] for what the sentence may contain.
    #[Swag.Discardable]
    func createMarkup(parent: *Wnd, markup: string?, position: Math.Rectangle = {}, id: WndId? = null, flags: LabelFlags = .None)->*Label
    {
        let lbl = create(parent, null, position, id, flags)
        lbl.setMarkup(markup)
        return lbl
    }

    // Replaces the displayed text with the literal `text`, detaches any catalog binding, and reapplies automatic sizing.
    //
    // No character of `text` is interpreted, so outside text is safe as it is.
    mtd setText(text: string?)
    {
        .localizedTextSource = null
        if .name.isPlain() and .name == (text orelse "") do
            return
        .name.set(text)
        .textChanged()
    }

    // Binds the label to a string-table field that the active language retargets.
    //
    // `source` is borrowed for the label's lifetime and must point to a field in a table that
    // remains alive that long. A later call to [[Gui.Label.setText]], [[Gui.Label.setMarkup]],
    // or [[Gui.Label.setRichText]] detaches the binding.
    mtd setLocalizedText(source: const *string)
    {
        Swag.assert(source != null, "localized text source is required")
        .localizedTextSource = source
        .refreshLocalizedText()
    }

    // Replaces the displayed text with a sentence written in inline markup.
    //
    // See [[Pixel.RichString.setMarkup]] for the markup, and pass outside text through
    // [[Pixel.RichString.escape]] before formatting it into the sentence.
    mtd setMarkup(markup: string?)
    {
        .localizedTextSource = null
        .name.setMarkup(markup)
        .textChanged()
    }

    // Replaces the displayed text with a copy of the styled runs of `text`.
    mtd setRichText(text: RichString)
    {
        .localizedTextSource = null
        .name = text
        .textChanged()
    }

    // Copies the current string-table value into the label and refreshes its presentation.
    private mtd refreshLocalizedText()
    {
        if not .localizedTextSource do
            return
        .name.set(.localizedTextSource[])
        .textChanged()
    }

    // Forgets the links of the previous text and fits the label to the new one.
    private mtd textChanged()
    {
        .hotChunk   = null
        .activeLink = Swag.U64.Max
        .updateActionFocus()
        .invalidate()
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    // Returns the displayed text, without any style information.
    mtd text()->string => .name.text

    // Enables or disables only the rich-text links, preserving the paragraph's text emphasis.
    mtd setLinksEnabled(enabled: bool)
    {
        .linksEnabled = enabled
        if .hotChunk do
            .hotChunk.isHotUrl = false
        .hotChunk = null
        .updateActionFocus()
        if not enabled and .hasFocus() do
            .surface?.clearFocus()
        .invalidate()
    }

    // Returns the first visible URL span's bounds in label coordinates.
    //
    // Returns an empty rectangle when there is no visible URL. Use after layout when anchoring a
    // popup to an inline action.
    mtd firstLinkRect()->Math.Rectangle
    {
        var result: Math.Rectangle
        var start = Swag.U64.Max
        for &chunk in .name.chunks where chunk.isUrl and chunk.visible
        {
            var rect = chunk.boundRect
            rect.offset(chunk.pos)
            if start == Swag.U64.Max
            {
                start  = chunk.urlStart
                result = rect
            }
            elif chunk.urlStart != start
            {
                break
            }
            else
            {
                let left = Math.min(result.x, rect.x)
                let top  = Math.min(result.y, rect.y)
                result = Math.Rectangle{left, top, Math.max(result.right(), rect.right()) - left, Math.max(result.bottom(), rect.bottom()) - top}
            }
        }

        return result
    }

    private mtd updateActionFocus()
    {
        if not .flags.has(.LinkActions) do
            return
        .name.compute()
        .focusPolicy = .linksEnabled and .name.hasUrl ? .Tab : .None
    }

    private mtd actionLink(after: u64, backward: bool)->u64
    {
        let current = after < .name.chunks.count ? .name.chunks[after].urlStart : Swag.U64.Max
        if backward
        {
            for index in reversed(.name.chunks.count) where index < after and
                                                            .name.chunks[index].isUrl and
                                                            not .name.chunks[index].isSpace and
                                                            .name.chunks[index].urlStart != current do
                return index
        }
        else
        {
            for index in .name.chunks.count where (after == Swag.U64.Max or index > after) and
                                                  .name.chunks[index].isUrl and
                                                  not .name.chunks[index].isSpace and
                                                  .name.chunks[index].urlStart != current do
                return index
        }

        return Swag.U64.Max
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
        .updateActionFocus()
        if remove.has(.LinkActions)
        {
            .focusPolicy = .None
            if .hasFocus() do
                .surface?.clearFocus()
        }

        if add.has(.AutoHeight) do
            .releaseAutomaticHeight()
        .invalidate()
        .invalidateLayout()
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
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    // Changes the extra space between text lines, in logical pixels.
    //
    // Negative values are clamped to zero. Measurement, painting, and automatic height use
    // the same gap; changing it invalidates the parent layout as well.
    mtd setLineGap(gap: s32)
    {
        let value = Math.max(gap, 0)
        if .lineGap == value do
            return
        .lineGap = value
        .invalidate()
        .invalidateLayout()
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
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    // Changes icon insets and updates layout and automatic height.
    mtd setIconPadding(padding: Math.Vector4)
    {
        if .iconPadding == padding do
            return
        .iconPadding = padding
        .invalidate()
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    // Changes the displayed icon and updates layout and automatic height.
    mtd setIcon(icon: Icon)
    {
        .icon = icon
        .invalidate()
        .invalidateLayout()
        .updateAutomaticHeight()
    }

    // Changes the fallback icon color; transparent restores the theme color.
    //
    // An icon's intrinsic tint takes precedence over this fallback.
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

    // Recomputes height from current text and icon, width, font, flags, and both paddings.
    //
    // A label under a layout container does not need this: [[Gui.LabelFlags.AutoHeight]]
    // already hands the height to the measure pass. Call it for a label placed by hand,
    // to read the right `position.height` back straight away. The method has no effect
    // unless `AutoHeight` is active.
    mtd updateAutomaticHeight()
    {
        if not .flags.has(.AutoHeight) do
            return

        let sf   = .getStringFormat(false)
        var rect = .position
        if rect.width <= 0 do
            rect.width = .preferredSize.x
        if rect.height <= 0 do
            rect.height = sf.font.regular!.height

        // The text is drawn inside the window and text paddings, so wrap against both insets and
        // add their vertical space back in.
        rect.applyPadding(.padding)
        rect.applyPadding(.textPadding)

        .name.compute()
        Painter.computeLayout(rect, &.name, sf, .deviceScale())

        var height = .name.boundRect.height
        if not .name.isEmpty() do
            height = Math.max(height, sf.font.regular!.height)
        height += .textPadding.y + .textPadding.w
        if .icon.isValid() do
            height = Math.max(height, .icon.sizeY + .iconPadding.y + .iconPadding.w)
        height += .padding.y + .padding.w
        .position.height = height
        .invalidateLayout()
    }
}

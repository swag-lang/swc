#global public

using Core, Pixel

// Per-item validation state for the property grid, in increasing severity. A field can be
// flagged Info/Warning/Error (e.g. a value out of range, an empty required string); the
// row then shows an accent bar and a badge in the state color, with the message in a
// tooltip. Mirrors the validation feedback of the Unity/Unreal inspectors.
enum PropValidation
{
    None        // Reports no validation issue.
    Info        // Reports informational guidance.
    Warning     // Reports a non-blocking concern.
    Error       // Reports an invalid value.
}

// Returns one validation severity and its optional user-facing explanation.
struct PropValidationResult
{
    public
    {
        state:   PropValidation = .None     // Validation severity.
        message: string?                    // Explanation shown with the row, or null for none.
    }
}

internal impl Properties
{
    // Background color of the validation bar (reuses the embedded-info palette).
    mtd validationColor(state: PropValidation)->Color
    {
        let colors = .themeColors()
        switch state
        {
        case .Error:   return colors.embInfo_CriticalBk
        case .Warning: return colors.embInfo_MessageBk
        case .Info:    return colors.embInfo_InformationBk
        }

        return Color.fromArgb(0)
    }

    // Text color of the validation bar message.
    mtd validationTextColor(state: PropValidation)->Color
    {
        let colors = .themeColors()
        switch state
        {
        case .Error:   return colors.embInfo_CriticalText
        case .Warning: return colors.embInfo_MessageText
        case .Info:    return colors.embInfo_InformationText
        }

        return colors.label_Text
    }

    // Theme icon for a validation state (matches the embedded-info control).
    mtd validationIcon(state: PropValidation)->Icon
    {
        let theme = .theme()
        switch state
        {
        case .Error:   return theme.icon(.Critical, .valBarIconSize)
        case .Warning: return theme.icon(.Warning, .valBarIconSize)
        case .Info:    return theme.icon(.Information, .valBarIconSize)
        }

        return theme.icon(.Information, .valBarIconSize)
    }

    // Recompute the validation state of every item (called on build and after a change).
    // Returns true when any row's bar appeared, disappeared or changed text, so the
    // caller can re-run the layout (the bar adds/removes height to the row).
    #[Swag.Discardable]
    mtd updateValidation()->bool
    {
        var changed = false
        for it in .items do
            if .updateItemValidation(it!) do
                changed = true
        return changed
    }

    // Ask the notify interface(s) along the item's parent chain for a validation result;
    // the most severe one wins. Items with no notify interface keep whatever was set
    // manually through setItemValidation.
    #[Swag.Discardable]
    mtd updateItemValidation(item: *PropertiesItem)->bool
    {
        var hasNtfy = false
        var result: PropValidationResult

        if .hostNtfy
        {
            hasNtfy = true
            result  = .hostNtfy.validateItem(me, item)
        }

        var scan = cast(*PropertiesItem?) item
        while scan
        {
            if scan.ntfyItf
            {
                hasNtfy = true
                let r = scan.ntfyItf.validateItem(me, item)
                if cast(s32) r.state > cast(s32) result.state do
                    result = r
            }

            scan = scan.parent
        }

        if !hasNtfy do
            return false

        return .applyItemValidation(item, result.state, result.message)
    }

    // Assigns validation state directly for data not represented by a reflected struct field.
    #[Swag.Discardable]
    mtd setItemValidation(item: *PropertiesItem, state: PropValidation, message: string? = null)->bool
    {
        return .applyItemValidation(item, state, message)
    }

    // Draw the colored background of a row's validation bar, in the row line's client space. The
    // severity icon and the message text are drawn by the Label itself (like InfoBar), so they
    // stay vertically centered together — see applyValidationVisual for the icon/colors.
    mtd paintValidationBar(painter: *Painter, item: *PropertiesItem)
    {
        if item.validation == .None or !(item.validationLabel != null) do
            return
        let lbl = item.validationLabel
        if !lbl.isVisible() do
            return

        // The label is sized to the text height; grow the colored background a little
        // above and below for breathing room (the row reserves the margins for it).
        var bar = lbl.position
        bar.y      -= .valBarPaddingY
        bar.height += 2 * .valBarPaddingY
        painter.fillRoundRect(bar, .valBarRadius, .valBarRadius, .validationColor(item.validation))
    }

    // Apply the bar's theme visuals to the Label: the severity icon (icon64, native White tint,
    // like InfoBar) plus the embInfo_* text color. Split out so it can be re-run on a theme
    // switch (the Label colors are manual fields, not styles, so they don't follow the theme alone).
    mtd applyValidationVisual(item: *PropertiesItem)
    {
        if !(item.validationLabel != null) or item.validation == .None do
            return
        let lbl = item.validationLabel
        lbl.setIcon(.validationIcon(item.validation))
        lbl.setIconColor(Argb.White)
        lbl.setTextColor(.validationTextColor(item.validation))
        .syncValidationTextOffset(lbl)
    }

    // Apply an info note's visuals to its label from the CURRENT theme: the info icon (native White
    // tint, like the validation bar) plus the embInfo info text color. Split out so it can be re-run
    // on a theme switch (see onThemeEvent) — a Label's icon/textColor are plain fields, not theme
    // styles, so a note built under one theme would otherwise keep stale colors under the next.
    mtd applyNoteVisual(item: *PropertiesItem)
    {
        if !(item.label != null) do
            return
        let lbl = item.label
        lbl.setIcon(.theme().icon(.Information, .valBarIconSize))
        lbl.setIconColor(Argb.White)
        lbl.setTextColor(.themeColors().embInfo_InformationText)
    }

    mtd syncValidationTextOffset(lbl: *Label)
    {
        let font = lbl.font().regular
        if font do
            lbl.setTextPadding({me.valBarGlyphWidth, -font.descent * 0.5, me.valBarPaddingX, font.descent * 0.5})
    }

    // Match the validation bar to the editor column and size the row to host it. Called once
    // the row's value widgets are positioned (so we can read the editor extent). In list mode
    // the bar caps its width to the value editor; in grid mode it spans the value cell and the
    // row grows downward to make room for it (and shrinks back when the bar is gone). Returns
    // true when it changed the row sizing, so the caller re-runs the row layout.
    #[Swag.Discardable]
    mtd syncValidationBar(item: *PropertiesItem)->bool
    {
        // The only caller guards on 'a presence comparison(item.validationLabel)'.
        let lbl     = item.validationLabel
        let visible = lbl.isVisible()

        if me.isGridLike()
        {
            // Grid rows lay out by docking, which keeps the value cell at the top. To host the
            // bar below it we reserve a bottom band with the row padding (so the name/editor
            // stay in the value cell), grow the row, and place the bar in the band by hand.
            // The bar spans the full row width (inset by the margins) and lives inside the row
            // border, so it reads as part of the row rather than floating over the value column.
            var consume = 0'f32
            if visible
            {
                .syncValidationTextOffset(lbl!)
                let topGap = lbl.margin.y
                let botGap = lbl.margin.w
                let cw     = item.line.clientRect().width
                lbl.position.x     = me.leftMargin
                lbl.position.width = Math.max(cw - me.leftMargin - me.rightMargin, 1.0)
                lbl.updateAutomaticHeight()
                consume        = topGap + lbl.position.height + botGap
                lbl.position.y = item.valueCellHeight + topGap
            }

            let h = item.valueCellHeight + consume
            if item.line.position.height == h and item.line.padding.w == consume do
                return false
            item.line.padding.w       = consume
            item.line.position.height = h
            item.line.preferredSize.y = h
            return true
        }

        if !visible do
            return false

        // List rows use the same content width as labels and editors: the useful row width
        // minus its internal margins. Do not infer this from child widgets, since custom editors
        // can be narrower than the row while messages still need the row wrap width.
        let w = .listContentWidth()
        lbl.maxSize.x      = w
        lbl.position.width = w
        .syncValidationTextOffset(lbl!)
        lbl.updateAutomaticHeight()
        return true
    }
}

private impl Properties
{
    // Apply a validation state + message to an item: create/show/hide its message bar.
    // Returns true when the bar's presence or text changed (a relayout is then needed).
    mtd applyItemValidation(item: *PropertiesItem, state: PropValidation, message: string?)->bool
    {
        if item.validation == state and item.validationMsg == message do
            return false

        item.assignValidation(state, message)

        if state == .None
        {
            if (item.validationLabel != null) and item.validationLabel.isVisible() do
                item.validationLabel.show(false)
        }
        else
        {
            .ensureValidationLabel(item)
            .applyValidationVisual(item)
            item.validationLabel.setText(message)
            item.validationLabel.show(true)
        }

        if item.line != null do
            item.line.invalidate()
        return true
    }

    // Lazily create the message-bar label, stacked under the row editor.
    mtd ensureValidationLabel(item: *PropertiesItem)
    {
        if item.validationLabel != null do
            return

        with let lbl = Label.create(item.line, "", {0, 0, .position.width, 0})
        {
            .updateFlags(.WordWrap | .AutoHeight)
            .setTextAlignment(.Left, .Center)

            // The Label draws the severity icon on the left and the text after it (both vertically
            // centered by the Label — iconVerticalAlignment defaults to Center), like InfoBar.
            .setIconHorizontalAlignment(.Left)
            .setIconPadding({(me.valBarGlyphWidth - me.valBarIconSize) * 0.5, 0, 0, 0})

            // Reserve room for the glyph on the left and inset the text from the colored
            // background edges (vertical breathing room is added when painting the bar).
            .setTextPadding({me.valBarGlyphWidth, 0, me.valBarPaddingX, 0})

            // Gap above the bar + the painted vertical breathing room top and bottom.
            .margin.y = me.valBarGap + me.valBarPaddingY
            .margin.w = me.valBarPaddingY
            if me.isGridLike() do
                .margin.z = me.rightMargin
        }

        item.assignValidationLabel(lbl)
    }
}

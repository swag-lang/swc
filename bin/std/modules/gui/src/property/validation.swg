#global public
using Core, Pixel

// Per-item validation state for the property grid, in increasing severity. A field can be
// flagged Info/Warning/Error (e.g. a value out of range, an empty required string); the
// row then shows an accent bar and a badge in the state color, with the message in a
// tooltip. Mirrors the validation feedback of the Unity/Unreal inspectors.
enum PropValidation
{
    None
    Info
    Warning
    Error
}

struct PropValidationResult
{
    state:   PropValidation = .None
    message: string
}

moduleprivate impl Properties
{
    // Background color of the validation bar (reuses the embedded-info palette).
    mtd validationColor(state: PropValidation)->Color
    {
        let colors = .getThemeColors()
        switch state
        {
        case Error:
            return colors.embInfo_CriticalBk
        case Warning:
            return colors.embInfo_MessageBk
        case Info:
            return colors.embInfo_InformationBk
        }
        return Color.fromArgb(0)
    }

    // Text color of the validation bar message.
    mtd validationTextColor(state: PropValidation)->Color
    {
        let colors = .getThemeColors()
        switch state
        {
        case Error:
            return colors.embInfo_CriticalText
        case Warning:
            return colors.embInfo_MessageText
        case Info:
            return colors.embInfo_InformationText
        }
        return colors.label_Text
    }

    // Theme icon for a validation state (matches the embedded-info control).
    mtd validationIcon(state: PropValidation)->Icon
    {
        let theme = .getTheme()
        switch state
        {
        case Error:
            return theme.getIcon64(.Critical, .valBarIconSize)
        case Warning:
            return theme.getIcon64(.Warning, .valBarIconSize)
        case Info:
            return theme.getIcon64(.Information, .valBarIconSize)
        }
        return theme.getIcon64(.Information, .valBarIconSize)
    }

    // Recompute the validation state of every item (called on build and after a change).
    // Returns true when any row's bar appeared, disappeared or changed text, so the
    // caller can re-run the layout (the bar adds/removes height to the row).
    #[Swag.Discardable]
    mtd updateValidation()->bool
    {
        var changed = false
        foreach it in .items do
            if .updateItemValidation(it) do
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
        var result:   PropValidationResult
        var scan = cast(#null *PropertiesItem) item
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

    // Set the validation of an item directly (for validation not driven by a struct).
    #[Swag.Discardable]
    mtd setItemValidation(item: *PropertiesItem, state: PropValidation, message: string = null)->bool
    {
        return .applyItemValidation(item, state, message)
    }

    // Draw the colored background and severity glyph of a row's validation bar, in the
    // row line's client space (the message text is painted by the label itself on top).
    mtd paintValidationBar(painter: *Painter, item: *PropertiesItem)
    {
        let lbl = item.validationLabel
        if item.validation == .None or !lbl or !lbl.isVisible() do
            return

        // The label is sized to the text height; grow the colored background a little
        // above and below for breathing room (the row reserves the margins for it).
        var bar = lbl.position
        bar.y      -= .valBarPaddingY
        bar.height += 2 * .valBarPaddingY
        painter.fillRoundRect(bar, .valBarRadius, .valBarRadius, .validationColor(item.validation))

        // Severity icon (tinted with the theme text color), centered in the reserved glyph
        // column on the left of the bar.
        let icon = .validationIcon(item.validation)
        let ix   = bar.x + (.valBarGlyphWidth - icon.sizeX) * 0.5
        let iy   = bar.vertCenter() - icon.sizeY * 0.5
        icon.paint(painter, Math.round(ix), Math.round(iy), .validationTextColor(item.validation))
    }
}

fileprivate impl Properties
{
    // Apply a validation state + message to an item: create/show/hide its message bar.
    // Returns true when the bar's presence or text changed (a relayout is then needed).
    mtd applyItemValidation(item: *PropertiesItem, state: PropValidation, message: string)->bool
    {
        if item.validation == state and item.validationMsg == message do
            return false

        item.validation    = state
        item.validationMsg  = message

        // The inline message bar stacks under the editor, which only fits the list mode;
        // the fixed-height grid rows have no room for it.
        if me.isGridLike() do
            return false

        if state == .None
        {
            if item.validationLabel and item.validationLabel.isVisible() do
                item.validationLabel.show(false)
        }
        else
        {
            .ensureValidationLabel(item)
            item.validationLabel.textColor = .validationTextColor(state)
            item.validationLabel.setText(message)
            item.validationLabel.show(true)
        }

        if item.line do
            item.line.invalidate()
        return true
    }

    // Lazily create the message-bar label, stacked under the row editor.
    mtd ensureValidationLabel(item: *PropertiesItem)
    {
        if item.validationLabel do
            return

        with let lbl = Label.create(item.line, "", {0, 0, .position.width, 0})
        {
            .labelFlags |= .WordWrap | .AutoHeight
            .horzAlignmentText = .Left
            .vertAlignmentText = .Center
            .focusStrategy     = .None
            // Reserve room for the glyph on the left and inset the text from the colored
            // background edges (vertical breathing room is added when painting the bar).
            .paddingText = {me.valBarGlyphWidth, 0, me.valBarPaddingX, 0}
            // Gap above the bar + the painted vertical breathing room top and bottom.
            .margin.y = me.valBarGap + me.valBarPaddingY
            .margin.w = me.valBarPaddingY
            if !me.isGridLike() do
                .margin.x = me.leftMargin
            .margin.z = me.rightMargin
        }

        item.validationLabel = lbl
    }
}

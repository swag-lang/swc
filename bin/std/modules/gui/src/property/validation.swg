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

    // Draw the colored background of a row's validation bar, in the row line's client space. The
    // severity icon and the message text are drawn by the Label itself (like EmbInfoCtrl), so they
    // stay vertically centered together — see applyValidationVisual for the icon/colors.
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
    }

    // Apply the bar's theme visuals to the Label: the severity icon (getIcon64, native White tint,
    // like EmbInfoCtrl) plus the embInfo_* text color. Split out so it can be re-run on a theme
    // switch (the Label colors are manual fields, not styles, so they don't follow the theme alone).
    mtd applyValidationVisual(item: *PropertiesItem)
    {
        let lbl = item.validationLabel
        if !lbl or item.validation == .None do
            return
        lbl.icon      = .validationIcon(item.validation)
        lbl.iconColor = Argb.White
        lbl.textColor = .validationTextColor(item.validation)
        .syncValidationTextOffset(lbl)
    }

    mtd syncValidationTextOffset(lbl: *Label)
    {
        let font = lbl.getFont().regular
        if font do
            lbl.paddingText = {me.valBarGlyphWidth, -font.descent * 0.5, me.valBarPaddingX, font.descent * 0.5}
    }

    // Match the validation bar to the editor column and size the row to host it. Called once
    // the row's value widgets are positioned (so we can read the editor extent). In list mode
    // the bar caps its width to the value editor; in grid mode it spans the value cell and the
    // row grows downward to make room for it (and shrinks back when the bar is gone). Returns
    // true when it changed the row sizing, so the caller re-runs the row layout.
    #[Swag.Discardable]
    mtd syncValidationBar(item: *PropertiesItem)->bool
    {
        let lbl     = item.validationLabel
        let visible = lbl != null and lbl.isVisible()

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
                .syncValidationTextOffset(lbl)
                let topGap = lbl.margin.y
                let botGap = lbl.margin.w
                let cw     = item.line.getClientRect().width
                lbl.position.x     = me.leftMargin
                lbl.position.width = Math.max(cw - me.leftMargin - me.rightMargin, 1.0)
                lbl.autoHeight()
                consume = topGap + lbl.position.height + botGap
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

        // List: cap the bar to the right edge of the value editor column so it lines up with
        // the editors above instead of running the full row width.
        let span = .valueWidgetsSpan(item)
        let w    = span.right - lbl.position.x
        if w > 0
        {
            lbl.maxSize.x      = w
            lbl.position.width = w
        }
        .syncValidationTextOffset(lbl)
        lbl.autoHeight()
        return true
    }

    // Horizontal extent [left, right] of an item's value widgets (the editor column): every
    // line child except the name/description labels and the validation bar itself. Falls back
    // to the value cell bounds when the row has no editor (e.g. a pure parent row).
    mtd valueWidgetsSpan(item: *PropertiesItem)->{ left, right: f32 }
    {
        var left  = Swag.F32.Max
        var right = 0'f32
        var found = false
        foreach c in item.line.childs
        {
            if c == item.label or c == item.labelDesc or c == item.validationLabel do
                continue
            if !c.isVisibleState() do
                continue
            left  = Math.min(left, c.position.x)
            right = Math.max(right, c.position.right())
            found = true
        }

        if !found
        {
            left  = me.getColumnX()
            right = Math.max(item.line.getClientRect().width - me.rightMargin, left + 1.0)
        }

        return {left, right}
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

        if state == .None
        {
            if item.validationLabel and item.validationLabel.isVisible() do
                item.validationLabel.show(false)
        }
        else
        {
            .ensureValidationLabel(item)
            .applyValidationVisual(item)
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
            // The Label draws the severity icon on the left and the text after it (both vertically
            // centered by the Label — vertAlignmentIcon defaults to Center), like EmbInfoCtrl.
            .horzAlignmentIcon = .Left
            .paddingIcon.x     = (me.valBarGlyphWidth - me.valBarIconSize) * 0.5
            // Reserve room for the glyph on the left and inset the text from the colored
            // background edges (vertical breathing room is added when painting the bar).
            .paddingText = {me.valBarGlyphWidth, 0, me.valBarPaddingX, 0}
            // Gap above the bar + the painted vertical breathing room top and bottom.
            .margin.y = me.valBarGap + me.valBarPaddingY
            .margin.w = me.valBarPaddingY
            // Left edge stays flush with the row name/description/editor (no extra indent),
            // so the bar reads as belonging to the field above it.
            .margin.z = me.rightMargin
        }

        item.validationLabel = lbl
    }
}

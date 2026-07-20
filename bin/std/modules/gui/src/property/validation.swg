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
    message: #null string
}

internal impl Properties
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
        for it in .items do
            if .updateItemValidation(assume it) do
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

        if .hostNtfy
        {
            hasNtfy = true
            result  = .hostNtfy.validateItem(me, item)
        }

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
    mtd setItemValidation(item: *PropertiesItem, state: PropValidation, message: #null string = null)->bool
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
        .syncValidationTextOffset(assume lbl)
    }

    // Apply an info note's visuals to its label from the CURRENT theme: the info icon (native White
    // tint, like the validation bar) plus the embInfo info text color. Split out so it can be re-run
    // on a theme switch (see onThemeEvent) — a Label's icon/textColor are plain fields, not theme
    // styles, so a note built under one theme would otherwise keep stale colors under the next.
    mtd applyNoteVisual(item: *PropertiesItem)
    {
        let lbl = item.label
        if !lbl do
            return
        lbl.icon      = .getTheme().getIcon64(.Information, .valBarIconSize)
        lbl.iconColor = Argb.White
        lbl.textColor = .getThemeColors().embInfo_InformationText
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
                .syncValidationTextOffset(assume lbl)
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

        // List rows use the same content width as labels and editors: the useful row width
        // minus its internal margins. Do not infer this from child widgets, since custom editors
        // can be narrower than the row while messages still need the row wrap width.
        let w = .listContentWidth()
        lbl.maxSize.x      = w
        lbl.position.width = w
        .syncValidationTextOffset(assume lbl)
        lbl.autoHeight()
        return true
    }

}

private impl Properties
{
    // Apply a validation state + message to an item: create/show/hide its message bar.
    // Returns true when the bar's presence or text changed (a relayout is then needed).
    mtd applyItemValidation(item: *PropertiesItem, state: PropValidation, message: #null string)->bool
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

        with let lbl = Label.create(assume item.line, "", {0, 0, .position.width, 0})
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
            if me.isGridLike() do
                .margin.z = me.rightMargin
        }

        item.validationLabel = lbl
    }
}

#global public

using Core, Pixel

// Selects the validation state of a property grid row, in increasing severity.
//
// A field can be flagged `Info`, `Warning`, or `Error`, for example for a value out of range or
// an empty required string. The row then shows the message under its value, led by a dot in the
// tone of the state, and a failure rings the editor in the critical ink.
enum PropValidation
{
    None        // Reports no validation issue.
    Info        // Reports informational guidance.
    Warning     // Reports a non-blocking concern.
    Error       // Reports an invalid value.
}

// Carries one validation severity and its optional user-facing explanation.
struct PropValidationResult
{
    public
    {
        state:   PropValidation = .None     // Validation severity.
        message: string?     // Explanation shown with the row, or null for none.
    }
}

internal impl Properties
{
    // Ink of a validation message and of its dot: the mark of the tone the state reports.
    mtd validationTextColor(state: PropValidation)->Color
    {
        let colors = .themeColors()
        switch state
        {
        case .Error:   return colors.critical
        case .Warning: return colors.caution
        case .Info:    return colors.info
        }

        return colors.label_Text
    }

    // Recompute the validation state of every item (called on build and after a change).
    // Returns true when any row's bar appeared, disappeared or changed text, so the
    // caller can re-run the layout (the bar adds/removes height to the row).
    #[Swag.Discardable]
    mtd updateValidation()->bool
    {
        var changed = false
        for it in .items do
            if .updateItemValidation(unwrap it) do
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

        var scan = cast(*PropertiesItem?, item)
        while scan
        {
            if scan.ntfyItf
            {
                hasNtfy = true
                let r = scan.ntfyItf.validateItem(me, item)
                if cast(s32, r.state) > cast(s32, result.state) do
                    result = r
            }

            scan = scan.parent
        }

        if not hasNtfy do
            return false

        return .applyItemValidation(item, result.state, result.message)
    }

    // Assigns validation state directly for data not represented by a reflected struct field.
    #[Swag.Discardable]
    mtd setItemValidation(item: *PropertiesItem, state: PropValidation, message: string? = null)->bool => .applyItemValidation(item, state, message)

    // Draws the dot that leads a row's validation message, and the critical ring around the editor of a failure.
    //
    // The message is a line in the tone of its state under the value cell: no ground, no icon,
    // no band — the dot and the ink are the whole vocabulary of a notice in a row.
    mtd paintValidationBar(painter: *Painter, item: *PropertiesItem)
    {
        if item.validation == .None or item.validationLabel == null do
            return
        let lbl = item.validationLabel
        if not lbl.isVisible() do
            return

        let metrics = .themeMetrics()
        let color   = .validationTextColor(item.validation)
        let font    = lbl.font().regular
        let size    = metrics.embInfo_DotSize
        var centerY = lbl.position.vertCenter()
        if font do
            centerY = lbl.position.y + lbl.textPadding.y + font.height * 0.5

        painter.setParams(.Antialiased)
        painter.fillCircle(lbl.position.x + size * 0.5, centerY, size * 0.5, color)

        // A failure rings its editor the way a field in error is ringed anywhere else.
        if item.validation == .Error
        {
            let editor = .valueEditor(item.line)
            if editor
            {
                let rect = editor.rectRelativeTo(item.line)
                painter.drawRoundRect(rect, metrics.corner_Control, metrics.corner_Control, color, metrics.focusRing_Size)
            }
        }
    }

    // Returns the first window of `parent` that takes the keyboard — the editor of a row — or `null`.
    mtd valueEditor(parent: *Wnd)->*Wnd?
    {
        for child in parent.children
        {
            if child.isLocallyVisible() and child.focusPolicy != .None and child.focusPolicy != .Inner do
                return child
            let inner = .valueEditor(child)
            if inner do
                return inner
        }

        return null
    }

    // Applies the ink of the state to the message label. Split out so it can be re-run on a
    // theme switch: a label's text colour is a plain field, not a style.
    mtd applyValidationVisual(item: *PropertiesItem)
    {
        if item.validationLabel == null or item.validation == .None do
            return
        let lbl = item.validationLabel
        lbl.setIcon({})
        lbl.setTextColor(.validationTextColor(item.validation))
        .syncValidationTextOffset(lbl)
    }

    // Applies an information notice to a note row from the CURRENT theme: the Arc information
    // glyph and the information ink on the Arc tint. Split out so it can be re-run on a theme
    // switch (see onThemeEvent): a label's icon and text colour are plain fields, not styles.
    mtd applyNoteVisual(item: *PropertiesItem)
    {
        if item.label == null do
            return
        let lbl = item.label
        lbl.setIcon(.theme().icon(.Information, .valBarIconSize))
        lbl.setIconColor(.themeColors().info)
        lbl.setTextColor(.themeColors().embInfo_InformationText)
    }

    // Leaves room for the dot before the words of a validation message.
    mtd syncValidationTextOffset(lbl: *Label)
    {
        let metrics = .themeMetrics()
        lbl.setTextPadding(Math.Vector4{metrics.embInfo_DotSize + metrics.embInfo_DotGap, 0, 0, 0})
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
                .syncValidationTextOffset(lbl)
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

        if not visible do
            return false

        // List rows use the same content width as labels and editors: the useful row width
        // minus its internal margins. Do not infer this from child widgets, since custom editors
        // can be narrower than the row while messages still need the row wrap width.
        let w = .listContentWidth()
        lbl.maxSize.x      = w
        lbl.position.width = w
        .syncValidationTextOffset(lbl)
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
            if item.validationLabel != null and item.validationLabel.isVisible() do
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

        // The message stands under the editor on the row's own ground, its dot painted by
        // paintValidationBar in the room the text padding leaves.
        with let lbl = Label.create(item.line, "", Math.Rectangle{0, 0, .position.width, 0})
        {
            .updateFlags(.WordWrap | .AutoHeight)
            .setTextAlignment(.Left, .Top)
            .margin.y = me.valBarGap
            .margin.w = me.valBarGap
            if me.isGridLike() do
                .margin.z = me.rightMargin
        }

        .syncValidationTextOffset(lbl)

        item.assignValidationLabel(lbl)
    }
}

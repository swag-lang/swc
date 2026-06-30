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
    // Theme color for a validation state (reuses the embedded-info palette).
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

    // Recompute the validation state of every item (called on build and after a change).
    mtd updateValidation()
    {
        foreach it in .items do
            .updateItemValidation(it)
    }

    // Ask the notify interface(s) along the item's parent chain for a validation result;
    // the most severe one wins. Items with no notify interface keep whatever was set
    // manually through setItemValidation.
    mtd updateItemValidation(item: *PropertiesItem)
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
            return

        if item.validation != result.state or item.validationMsg != result.message
        {
            item.validation    = result.state
            item.validationMsg = result.message
            if item.line do
                item.line.invalidate()
        }
    }

    // Set the validation of an item directly (for validation not driven by a struct).
    mtd setItemValidation(item: *PropertiesItem, state: PropValidation, message: string = null)
    {
        if item.validation == state and item.validationMsg == message do
            return
        item.validation    = state
        item.validationMsg = message
        if item.line do
            item.line.invalidate()
    }

    // Draw the validation accent bar and badge for a row, in its line's client space.
    mtd paintValidationMarker(painter: *Painter, item: *PropertiesItem, r: Math.Rectangle)
    {
        if item.validation == .None do
            return

        let col = .validationColor(item.validation)

        // Accent bar down the left edge of the row.
        let bar = Math.Rectangle{r.x + 1, r.y + 3, 3, Math.max(r.height - 6, 1.0)}
        painter.fillRoundRect(bar, 1.5, 1.5, col)

        // Round badge with a glyph at the right edge, aligned with the name row.
        const Radius = 8'f32
        let cx = r.right() - Radius - 6
        let cy = item.label ? item.label.position.vertCenter() : r.y + Radius + 6
        painter.fillCircle(cx, cy, Radius, col)

        let glyph = item.validation == .Info ? "i" : "!"
        let font  = .getTheme().createDefaultFont(13, .Bold)
        painter.drawStringCenter(cx, cy, glyph, font, Argb.White)
    }
}

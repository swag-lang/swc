#global public
using Core, Pixel

// Grid/Condensed layout of the property control: mode predicates, the resizable label column,
// and the condensed-cell adaptations. Split out of properties.swg so the geometry lives in one
// place. See also properties.paint.swg (which draws the column separator) and the two-pass
// resize loop in propertiesview.swg.
impl Properties
{
    // True for the grid-family modes (Grid and Condensed). They share the same
    // column-based layout, expand/collapse behavior and column separator; only
    // their metrics (row height, margins, control size) differ.
    mtd isGridLike()->bool
    {
        return .kind == .Grid or .kind == .Condensed
    }

    // In condensed mode the value editors fill the whole value cell (both axes):
    // the grid lines already provide the visual structure, so the editor stays
    // flat and edge-to-edge instead of floating as a smaller bordered box.
    mtd adaptCondensedControl(wnd: *Wnd)
    {
        if .kind != .Condensed do
            return
        wnd.dockStyle = .Center
        wnd.maxSize.x = 0
    }

    // Flatten an edit box for the condensed cell look: no background/border at
    // rest (only when invalid), with a small horizontal padding so the text does
    // not touch the column separator.
    mtd flattenCondensedEdit(ed: *EditBox)
    {
        if .kind != .Condensed do
            return
        ed.setForm(.Transparent)
        ed.setAllPaddings(Math.Vector4{8, 0, 8, 0})
    }

    // Set the grid mode column size
    mtd setColumnSize(size: s32)
    {
        if !.isGridLike() do
            return

        .gridColumnSizeReq = size
        .gridColumnSize    = .clampColumnSize(size)
        .syncColumnLabels()
        .applyLayout()
        .invalidate()
    }

    mtd refreshGridColumnLayout()
    {
        if !.isGridLike() do
            return

        .gridColumnSize = .clampColumnSize(.gridColumnSizeReq)
        .syncColumnLabels()
    }
}

moduleprivate impl Properties
{
    mtd clampColumnSize(size: s32)->s32
    {
        let maxSize = cast(s32) .position.width - .gridMarginColumn - .leftMargin - .rightMargin
        if maxSize < .gridMarginColumn do
            return Math.max(size, .gridMarginColumn)
        return Math.clamp(size, .gridMarginColumn, maxSize)
    }

    mtd isGridHeader(item: *PropertiesItem)->bool
    {
        return .isGridLike() and item.flags.has(.Section | .Category)
    }

    mtd getGridHeaderLabelWidth(item: *PropertiesItem)->f32
    {
        var width = .edView.position.width
        if width <= 0 do
            width = .position.width
        if width <= 0 do
            width = item.line.position.width
        return Math.max(width - item.line.margin.x - item.line.margin.z - item.label.margin.x - item.label.margin.z, 1.0)
    }

    mtd syncColumnLabel(item: *PropertiesItem)
    {
        if !item.label do
            return

        if .isGridHeader(item)
        {
            item.label.margin.z      = 0
            item.label.paddingText.x = .leftMargin
            item.label.position.width = .getGridHeaderLabelWidth(item)
        }
        else do
            item.label.position.width = .gridColumnSize
    }

    mtd syncColumnLabels()
    {
        foreach item in .items do
            .syncColumnLabel(item)
    }

    mtd getColumnX()->f32
    {
        return .gridColumnSize + .gridMarginColumn * 0.5
    }
}

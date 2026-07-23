#global public

using Core, Pixel

// Layout geometry of the property control: grid/condensed column metrics, list useful/content
// widths, and the condensed-cell adaptations. Split out of properties.swg so the geometry lives
// in one place. See also properties.paint.swg and the two-pass resize loop in propertiesview.swg.
impl Properties
{
    // The window into which a row's trailing action widgets are placed. Grid docks them on the row
    // cell; list places them on the name label in local content coordinates. Null for rows with no
    // label in list mode.
    mtd rowActionArea(item: *PropertiesItem)->#null *Wnd
    {
        return .isGridLike() ? item.line : cast(#null *Wnd) item.label
    }
}

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

internal impl Properties
{
    // List/Panel geometry: rows, labels and descriptions span the whole control, so the
    // useful row width (selection/hot/hit-test) tracks the live view width; sizeEditValue
    // is only the build-time fallback, before the first layout has sized the view. The
    // value editors keep their own cap (sizeEditValue / the EditSize attribute), so only
    // the texts stretch — the look of an editor's settings page.
    mtd listUsefulWidth()->f32
    {
        Debug.assert(!.isGridLike())
        var width = cast(f32) .sizeEditValue
        if .edView and .edView.position.width > 0 do
            width = .edView.position.width
        return Math.max(width, cast(f32) (.leftMargin + .rightMargin) + 1.0)
    }

    mtd listContentWidthFromUseful(width: f32)->f32
    {
        Debug.assert(!.isGridLike())
        return Math.max(width - .leftMargin - .rightMargin, 1.0)
    }

    mtd listContentWidth()->f32
    {
        return .listContentWidthFromUseful(.listUsefulWidth())
    }

    mtd setListContentPadding(wnd: #null *Wnd)
    {
        if .isGridLike() or !wnd do
            return
        wnd.padding.x = .leftMargin
        wnd.padding.z = .rightMargin
    }

    // Right edge (in row-content coordinates) of the revert/action column: anchored to
    // the value column (sizeEditValue), not to the full row width, so the arrows stay
    // lined up with the editors whatever the control width.
    mtd listActionRight()->f32
    {
        return .listContentWidthFromUseful(cast(f32) .sizeEditValue) - PropRevertGap
    }

    mtd positionListActionButton(item: *PropertiesItem, btn: #null *IconButton)
    {
        if .isGridLike() or !btn or !#isset(item.label) do
            return

        btn.position.x = Math.round(.listActionRight() - btn.position.width)
        btn.position.y = Math.round((item.label.position.height - btn.position.height) * 0.5)
    }

    mtd clampColumnSize(size: s32)->s32
    {
        let maxSize = cast(s32) .position.width - .gridMarginColumn - .leftMargin - .rightMargin
        if maxSize < .gridMarginColumn do
            return Math.max(size, .gridMarginColumn)
        return Math.clamp(size, .gridMarginColumn, maxSize)
    }

    mtd isGridHeader(item: *PropertiesItem)->bool
    {
        return .isGridLike() and item.flags.has(.Section | .Category | .Header)
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

    // Horizontal indent (px) of a data row's name label + disclosure triangle. Nesting depth is
    // carried by indentation (the primary hierarchy cue) rather than by a per-level background
    // tint. Headers (section/category) span the full width and are never indented. Depth 0 is a
    // top-level field (level 1); every nested struct/array level adds one gridIndentSize step.
    // Data-column depth of a row: 0 for a top-level field (level 1), +1 per nested struct/array.
    mtd itemDepth(item: *PropertiesItem)->u32
    {
        return item.level > 0 ? item.level - 1 : 0'u32
    }

    mtd itemIndent(item: *PropertiesItem)->f32
    {
        if !.isGridLike() do
            return 0

        // Headers (section/category/subgroup/decorator) indent by their own level: a top-level
        // header is at 0, a nested subgroup one step in — so its band label lines up with the
        // (level-1)-based indent of the fields it groups.
        if .isGridHeader(item) do
            return cast(f32) item.level * cast(f32) .gridIndentSize
        return cast(f32) .itemDepth(item) * cast(f32) .gridIndentSize
    }

    // Does the given data-column depth show any disclosure triangle? An ancestor depth always does
    // (a parent has children), so in practice only the deepest, all-leaf levels come back false.
    // Recomputed by computeLevelMarks on every structural change.
    mtd levelReservesMark(depth: u32)->bool
    {
        return depth < .gridLevelHasMark.count ? .gridLevelHasMark[depth] : false
    }

    // Width of the disclosure-triangle slot in front of a data row's label. Full leftMargin when
    // the row's depth has any expandable item (so leaf rows stay aligned with their expandable
    // siblings); shrunk when the whole depth is mark-less, reclaiming that horizontal room so a
    // group of pure-leaf fields tucks in closer under its parent instead of leaving an empty slot.
    mtd itemLabelGutter(item: *PropertiesItem)->f32
    {
        if !.isGridLike() or .isGridHeader(item) do
            return cast(f32) .leftMargin
        return .levelReservesMark(.itemDepth(item)) ? cast(f32) .leftMargin : cast(f32) .leftMargin * 0.5
    }

    // Recompute, per data-column depth, whether any row at that depth is expandable. Drives
    // itemLabelGutter so mark-less depths don't reserve triangle room. Cheap (one pass, tiny
    // depths), so it just runs on every structural update.
    mtd computeLevelMarks()
    {
        .gridLevelHasMark.clear()
        if !.isGridLike() do
            return
        for item in .items
        {
            if .isGridHeader(notnull item) or !item.numChilds do
                continue
            let depth = .itemDepth(notnull item)
            while .gridLevelHasMark.count <= depth do
                .gridLevelHasMark.add(false)
            .gridLevelHasMark[depth] = true
        }
    }

    mtd syncColumnLabel(item: *PropertiesItem)
    {
        if !#isset(item.label) do
            return

        // Note rows own their layout (a full-width info bar with custom paddings), so leave them be.
        if item.flags.has(.Note) do
            return

        if .isGridHeader(item)
        {
            item.label.margin.z       = 0
            item.label.paddingText.x  = cast(f32) .leftMargin + .itemIndent(item)
            item.label.position.width = .getGridHeaderLabelWidth(item)
        }
        else
        {
            item.label.paddingText.x  = .itemIndent(item) + .itemLabelGutter(item)
            item.label.position.width = .gridColumnSize
        }
    }

    mtd syncColumnLabels()
    {
        for item in .items do
            .syncColumnLabel(notnull item)
    }

    mtd getColumnX()->f32
    {
        return .gridColumnSize + .gridMarginColumn * 0.5
    }
}

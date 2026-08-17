#global public

using Core, Pixel

// Rendering of the property control: the per-row background/focus/hot chrome, the live column
// resize rule, and the disclosure icon. The control-level onPaint (separator-color
// animation) is in properties.swg with the other IWnd events; the inline validation bar this
// draws lives in validation.swg (paintValidationBar).
internal impl Properties
{
    mtd disclosureIconPosition(item: *PropertiesItem, r: Math.Rectangle, icon: Icon)->Math.Point
    {
        const OpticalTextCenterY = -2'f32

        let iconX       = r.x + .itemIndent(item) + Math.max(.leftMargin - icon.sizeX, 0.0) * 0.5
        let iconCenterY = @isset(item.label) ? item.label.position.vertCenter() : r.vertCenter()
        return {iconX, iconCenterY - icon.sizeY * 0.5 + OpticalTextCenterY}
    }

    mtd paintBackItem(painter: *Painter, item: *PropertiesItem, wndItem: *Wnd)
    {
        // Spacer decorator: a pure vertical gap — no background, border or content.
        if item.flags.has(.Spacer) do
            return

        var colBkBk, colBk, colBorder: Color

        let colors = .wnd.themeColors()
        if item == .selItem
        {
            colBk     = colors.prop_FocusBk
            colBorder = colors.prop_FocusBorder
        }
        elif .hotItem == item and .hotItem!.line.isEnabled()
        {
            colBk     = colors.prop_HotBk
            colBorder = colors.prop_HotBorder
        }

        item.aniFocusBk.apply(wndItem, colBk)
        item.aniFocusBorder.apply(wndItem, colBorder)

        var r = wndItem.clientRect()
        r.moveTop(wndItem.children.front().position.y)

        // Row chrome stays inside the row window. Painting through the surrounding layout
        // margins lets two independently animated rows overwrite each other at their shared edge.
        let rowRect = r
        if .isGridLike()
        {
            r.x     = 0
            r.width = .edView.position.width - 1
        }
        else
        {
            // The line is the list row's useful rectangle. Children carry the internal content
            // margins, so paint, hit-test, wrapping and action placement share one width.
            r.x     = 0
            r.width = .listUsefulWidth() - 1
        }

        // HelpBox note decorator: a soft info bar spanning the row. The styled label (built with the
        // info icon + text color) paints on top; no grid border, separator or disclosure.
        if item.flags.has(.Note)
        {
            var bar = r
            bar.inflate(-3)
            painter.fillRect(bar, colors.embInfo_InformationBk)
            return
        }

        // When a validation bar grows the grid row, the row chrome (background, border, focus
        // box) wraps the whole thing so the bar reads as part of the row. The column separator
        // is the exception: it must stop at the value cell, since the bar spans full width.
        var valueCellBottom = r.bottom()
        if .isGridLike() and @isset(item.validationLabel) and item.validationLabel.isVisible() do
            valueCellBottom = item.validationLabel.position.y - .valBarPaddingY

        // Background. Group headers (section/category) get a band; data rows stay transparent —
        // nesting depth is carried by the label indent, not a per-level tint (which turns muddy
        // past a couple of levels). The hovered branch is marked by the guide bar drawn below.
        if .isGridLike() and item.flags.has(.Section) do
            colBkBk = colors.prop_SectionBk
        elif .isGridLike() and item.flags.has(.Category | .Header) do
            colBkBk = colors.prop_CategBk
        painter.fillRect(r, colBkBk)

        // Hot and focus ground. It spans the row instead of floating as a rounded card: the
        // property values are the content, and the row state is only a quiet wash behind them.
        painter.fillRect(r, item.aniFocusBk.cur())

        // The column boundary is visible only while it is being targeted. Extend that live rule
        // through the layout margins so adjacent row segments meet without clipped ends.
        if .isGridLike() and !item.flags.has(.NoSeparator) and (.cursorSet or .resizingColumn)
        {
            let top  = r.y - wndItem.margin.y
            let bot  = valueCellBottom + wndItem.margin.w
            let x    = .columnPosition() - item.line.position.x
            let rect = Math.Rectangle{x - 1, top, 2, Math.max(bot - top, 1.0)}
            painter.fillRect(rect, .aniBar.cur())
        }

        // The selected row is a short accent mark in a reserved edge lane, not another box.
        let focusRail = Math.Rectangle{r.x, r.y + 5, 2, Math.max(r.height - 10, 4.0)}
        painter.fillRect(focusRail, item.aniFocusBorder.cur())

        // List rows: a field whose value differs from its declared default gets a small neutral
        // square in the reserved edge lane. Selection owns the accent rail; giving both states
        // the same rail made a changed value read as selected. Grid keeps its revert-arrow column.
        if !.isGridLike() and item.isModified and .revertButtonsVisible
        {
            const MarkerSize = 4'f32
            let marker = Math.Rectangle{rowRect.x + 4, Math.round(rowRect.vertCenter() - MarkerSize * 0.5), MarkerSize, MarkerSize}
            painter.fillRect(marker, colors.label_TextFaint)
        }

        // Validation feedback: an inline colored message bar stacked under the value cell,
        // in both list and grid modes.
        .paintValidationBar(painter, item)

        // Expand/Collapse icon
        if .isGridLike() and item.numChilds
        {
            let expand    = .theme().icon(item.flags.has(.Expanded) ? .ChevronDown : .ChevronRight, .themeMetrics().chevron_Size)
            let iconColor = item.line.isDisabled() ? colors.label_DisabledIcon : colors.label_Icon
            let iconPos   = .disclosureIconPosition(item, r, expand)
            expand.paint(painter, iconPos.x, iconPos.y, iconColor)
        }
    }
}

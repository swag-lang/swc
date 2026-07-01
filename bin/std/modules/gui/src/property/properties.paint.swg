#global public
using Core, Pixel

// Rendering of the property control: the per-row background/focus/hot chrome, the grid borders
// and column separator, the disclosure icon. The control-level onPaintEvent (separator-color
// animation) is in properties.swg with the other IWnd events; the inline validation bar this
// draws lives in validation.swg (paintValidationBar).
moduleprivate impl Properties
{
    mtd getDisclosureIconPosition(item: *PropertiesItem, r: Math.Rectangle, icon: Icon)->Math.Point
    {
        const OpticalTextCenterY = -2'f32

        let iconX       = r.x + Math.max(.leftMargin - icon.sizeX, 0.0) * 0.5
        let iconCenterY = item.label ? item.label.position.vertCenter() : r.vertCenter()
        return {iconX, iconCenterY - icon.sizeY * 0.5 + OpticalTextCenterY}
    }

    mtd paintBackItem(painter: *Painter, item: *PropertiesItem, wndItem: *Wnd)
    {
        var colBkBk, colBk, colBorder: Color

        let colors = .wnd.getThemeColors()
        if item == .selItem
        {
            colBk     = colors.prop_FocusBk
            colBorder = colors.prop_FocusBorder
        }
        elif .hotItem == item and .hotItem.line.isEnabled()
        {
            colBk     = colors.prop_HotBk
            colBorder = colors.prop_HotBorder
        }

        item.aniFocusBk.apply(wndItem, colBk)
        item.aniFocusBorder.apply(wndItem, colBorder)

        var r = wndItem.getClientRect()
        r.moveTop(wndItem.childs.front().position.y)
        r.inflate(item.extendFocus)
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

        // When a validation bar grows the grid row, the row chrome (background, border, focus
        // box) wraps the whole thing so the bar reads as part of the row. The column separator
        // is the exception: it must stop at the value cell, since the bar spans full width.
        var valueCellBottom = r.bottom()
        if .isGridLike() and item.validationLabel and item.validationLabel.isVisible() do
            valueCellBottom = item.validationLabel.position.y - .valBarPaddingY

        // Background
        if .isGridLike() and item.flags.has(.Section) do
            colBkBk = colors.prop_SectionBk
        elif .isGridLike() and item.flags.has(.Category) do
            colBkBk = colors.prop_CategBk
        elif .isGridLike() and item.level > 1 do
            colBkBk = colors.prop_Bk1
        painter.fillRect(r, colBkBk)

        // Hot and focus box background
        {
            var r1 = r
            r1.inflate(-2)
            painter.fillRoundRect(r1, 4, 4, item.aniFocusBk.cur())
        }

        // In grid mode, display borders and column separator
        if .isGridLike()
        {
            var r1 = r
            r1.height += 1
            painter.drawRect(r1, colors.prop_GridBorder)

            if !item.flags.has(.NoSeparator)
            {
                let x    = .getColumnX() - item.line.position.x
                let size = .cursorSet ? 4 : 1
                let rect = Math.Rectangle{x - size * 0.5, r1.y, size, valueCellBottom - r1.y}
                painter.fillRect(rect, .aniBar.cur())
            }
        }

        // Hot and focus border
        {
            var r1 = r
            r1.inflate(-2)
            painter.drawRoundRect(r1, 4, 4, item.aniFocusBorder.cur())
        }

        // Validation feedback: an inline colored message bar stacked under the value cell,
        // in both list and grid modes.
        .paintValidationBar(painter, item)

        // Expand/Collapse icon
        if .isGridLike() and item.numChilds
        {
            let expand = .getTheme().getIcon24(item.flags.has(.Expanded) ? .Expanded : .Collapsed)
            let iconColor = item.line.isDisabled() ? colors.label_DisabledIcon : colors.label_Icon
            let iconPos = .getDisclosureIconPosition(item, r, expand)
            expand.paint(painter, iconPos.x, iconPos.y, iconColor)
        }
    }
}

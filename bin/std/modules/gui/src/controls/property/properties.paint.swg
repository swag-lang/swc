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
        let iconCenterY = (item.label != null) ? item.label.position.vertCenter() : r.vertCenter()
        return Math.Point{iconX, iconCenterY - icon.sizeY * 0.5 + OpticalTextCenterY}
    }

    mtd paintBackItem(painter: *Painter, item: *PropertiesItem, wndItem: *Wnd)
    {
        // Spacer decorator: a pure vertical gap — no background, border or content.
        if item.flags.has(.Spacer) do
            return

        var colBkBk, colBk: Color

        let theme   = .wnd.theme()
        let colors  = .wnd.themeColors()
        let metrics = .wnd.themeMetrics()
        if .rowGrounds and item == .selItem
        {
            colBk = colors.prop_FocusBk
        }
        elif .rowGrounds and .hotItem == item and .hotItem!.line.isEnabled()
        {
            colBk = colors.prop_HotBk
        }

        item.aniFocusBk.apply(wndItem, colBk)

        var r = wndItem.clientRect()

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
        if .isGridLike() and item.validationLabel != null and item.validationLabel.isVisible() do
            valueCellBottom = item.validationLabel.position.y - .valBarGap

        // Background. Group headers (section/category) get a band; data rows stay transparent —
        // nesting depth is carried by the label indent, not a per-level tint (which turns muddy
        // past a couple of levels). The hovered branch is marked by the guide bar drawn below.
        if .isGridLike() and item.flags.has(.Section) do
            colBkBk = colors.prop_SectionBk
        elif .isGridLike() and item.flags.has(.Category | .Header) do
            colBkBk = colors.prop_CategBk
        painter.fillRect(r, colBkBk)

        // Inset the hot and focus ground so it leaves space around the row's content and edges.
        var stateRect = r
        stateRect.inflate(-metrics.property_ControlInset, -metrics.property_ControlInset)
        theme.drawSubRect(painter, stateRect, &theme.rects.selectionBox_Bk, item.aniFocusBk.cur())

        // A search marks what it found in the name, on the highlight ground, under the words.
        if not .stringFilter.isEmpty() do
            .paintNameMatch(painter, item)

        // The column boundary is visible only while it is being targeted. Extend that live rule
        // through the layout margins so adjacent row segments meet without clipped ends.
        if .isGridLike() and not item.flags.has(.NoSeparator) and (.cursorSet or .resizingColumn)
        {
            let top  = r.y - wndItem.margin.y
            let bot  = valueCellBottom + wndItem.margin.w
            let x    = .columnPosition() - item.line.position.x
            let rect = Math.Rectangle{x - 1, top, 2, Math.max(bot - top, 1.0)}
            painter.fillRect(rect, .aniBar.cur())
        }

        // A field whose value differs from its declared default carries a small Arc dot right
        // after its name, in every kind: it says "changed" where the eye reads the name, and the
        // faint revert glyph at the end of the row (or the context menu) restores it.
        if item.isModified and .revertButtonsVisible do
            .paintNameMark(painter, item, modified: true)

        // A read-only value is shown, not offered: a faint padlock after its name says so.
        if item.label != null and item.data and .isItemReadOnly(item) do
            .paintNameMark(painter, item, modified: false)

        // A section label in a panel is followed by one hairline to the end of the row: the
        // label and the line already say where a group starts, so no band stands behind it.
        if .kind == .Panel and .sectionRules and item.flags.has(.Category) and item.label != null
        {
            // The words are tracked out, so their run is wider than the face alone measures it.
            let label    = item.label
            let font     = unwrap label.font().regular
            let tracking = metrics.sectionLabel_LetterSpacing * cast(f32, label.text().count)
            let width    = Painter.measureString(label.text(), font).width + tracking + label.textPadding.x
            let left     = label.position.x + width + metrics.dialog_BtnPadding
            let y        = Math.round(label.position.vertCenter())
            if left < r.right() do
                painter.fillRect(Math.Rectangle{left, y, r.right() - left, metrics.separator_HairlineSize}, colors.line)
        }

        // Condensed rows read as a table: one hairline under each field row.
        if .kind == .Condensed and not item.flags.has(.Section | .Category | .Header | .Note | .Spacer)
        {
            let y = rowRect.bottom() + wndItem.margin.w - metrics.separator_HairlineSize
            painter.fillRect(Math.Rectangle{r.x, y, r.width, metrics.separator_HairlineSize}, colors.line)
        }

        // Validation feedback: a dot in the tone and the message in the tone under the value
        // cell, with a critical ring around the editor of a failure.
        .paintValidationBar(painter, item)

        // Expand/Collapse: a small faint chevron before a section label. The title of a whole
        // structure needs none: it is the grid's own heading.
        if .isGridLike() and item.numChilds and not item.flags.has(.Section)
        {
            let expand    = .theme().icon(item.flags.has(.Expanded) ? .ChevronDown : .ChevronRight, .themeMetrics().chevron_Size)
            let iconColor = item.line.isDisabled() ? colors.label_DisabledIcon : colors.faintText
            let iconPos   = .disclosureIconPosition(item, r, expand)
            expand.paint(painter, iconPos.x, iconPos.y, iconColor)
        }
    }

    // Returns the byte offset of the text filter in the name of `item`, or `Swag.U64.Max`.
    mtd nameMatch(item: *PropertiesItem)->u64
    {
        if item.label == null do
            return Swag.U64.Max
        let plain = RichString.plainText(item.label.text())
        return Utf8.indexOf(plain.toSlice(), .stringFilter, comparisonType: Utf8.ComparisonType.Latin1NoCase)
    }

    // Lays the highlight ground under the characters of the name of `item` the text filter found.
    mtd paintNameMatch(painter: *Painter, item: *PropertiesItem)
    {
        let start = .nameMatch(item)
        if start == Swag.U64.Max do
            return
        let label = item.label
        let font  = label.font().regular
        if not font or not label.isLocallyVisible() do
            return

        // The first line of the name, as the marks after it: a list name wraps from the top, a
        // grid name is centred.
        let plain  = RichString.plainText(label.text())
        let count  = Math.min(.stringFilter.length, plain.length - start)
        let before = Painter.measureString(Swag.makeString(plain.buffer, start), font).width
        let after  = Painter.measureString(Swag.makeString(plain.buffer, start + count), font).width
        let left   = label.position.x + label.textPadding.x
        var top    = label.position.vertCenter() - font.height * 0.5
        if not .isGridLike() do
            top = label.position.y + label.textPadding.y
        if before >= label.position.width do
            return
        let right = Math.min(left + after, label.position.right())
        painter.fillRect(Math.Rectangle{Math.round(left + before), Math.round(top), Math.round(right - left - before), font.height}, .themeColors().highlight)
    }

    // Draws a mark right after the name of `item`: the Arc dot of a value changed from its default
    // when `modified`, otherwise the faint padlock of a read-only value.
    mtd paintNameMark(painter: *Painter, item: *PropertiesItem, modified: bool)
    {
        // A self-labelled control of a panel carries its own words: the mark follows them.
        if .kind == .Panel and modified and .paintSelfLabelMark(painter, item) do
            return

        // A row with no name at all, such as one flag of an enumeration, never assigned the label:
        // it is compared before it is read.
        if item.label == null do
            return
        let label = item.label
        if label.text().count == 0 or
           not label.isLocallyVisible() or
           label.position.width <= 0 do
            return
        let font = label.font().regular
        if not font do
            return

        // The first line of the name: a list name wraps from the top, a grid name is centred.
        let metrics = .themeMetrics()
        let size    = metrics.property_ModifiedMarkSize
        let width   = Painter.measureString(RichString.plainText(label.text()), font).width
        let x       = label.position.x + label.textPadding.x + Math.min(width, label.position.width) + size
        var centerY = label.position.vertCenter()
        if not .isGridLike() do
            centerY = label.position.y + label.textPadding.y + font.height * 0.5

        if modified
        {
            painter.setParams(.Antialiased)
            painter.fillCircle(x + size * 0.5, centerY, size * 0.5, .themeColors().arc)
            return
        }

        let lock = .theme().icon(.Lock, metrics.iconText_Margin + size)
        lock.paint(painter, x, centerY - lock.sizeY * 0.5, .themeColors().faintText)
    }

    // Paints the changed mark after the words of the self-labelled control of a panel row: the
    // name of a slider or of a field, or the caption of a check button. Reports false when the
    // row has no such control.
    mtd paintSelfLabelMark(painter: *Painter, item: *PropertiesItem)->bool
    {
        var words: *Label?
        if item.sliderBox != null
        {
            words = item.sliderBox.label
        }
        elif item.editBox != null and item.editBox.parent
        {
            let parent = item.editBox.parent
            if parent is EditCtrl as ctrl do
                words = ctrl.label
        }
        elif item.comboBox != null and item.comboBox.parent
        {
            let parent = item.comboBox.parent
            if parent is ComboCtrl as ctrl do
                words = ctrl.label
        }

        let metrics = .themeMetrics()
        let size    = metrics.property_ModifiedMarkSize
        var right, centerY: f32
        if words
        {
            let font = words.font().regular
            if not font or not words.isLocallyVisible() do
                return false
            let rect  = words.rectRelativeTo(item.line)
            let width = Painter.measureString(RichString.plainText(words.text()), font).width
            right   = rect.x + words.textPadding.x + Math.min(width, rect.width)
            centerY = rect.vertCenter()
        }
        elif item.checkBox != null
        {
            let check = item.checkBox
            let font  = check.font().regular
            if not font do
                return false
            let rect  = check.rectRelativeTo(item.line)
            let width = Painter.measureString(RichString.plainText(check.name.raw), font).width
            right   = rect.x + metrics.btnCheck_Size + metrics.btnCheck_Padding + width
            centerY = rect.vertCenter()
        }
        else
        {
            return false
        }

        painter.setParams(.Antialiased)
        painter.fillCircle(right + size * 1.5, centerY, size * 0.5, .themeColors().arc)
        return true
    }
}

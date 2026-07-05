impl Properties
{
    mtd refreshBool(item: *PropertiesItem)
    {
        if item.checkBox
        {
            // Multi-selection: a disagreeing bool shows as the indeterminate (mixed) mark.
            if .fieldIsMixed(item) do
                item.checkBox.checked = .Undefined
            else do
                item.checkBox.checked = dref cast(*bool) item.data ? .Checked : .UnChecked
            item.checkBox.invalidate()
        }
    }

    mtd validateBool(item: *PropertiesItem)
    {
        var data = cast(*bool) item.data
        if item.checkBox do
            dref data = item.checkBox.checked == .Checked ? true : false
        .hasChanged(item)
    }

    mtd constructBool(value: Swag.TypeValue, data: *u8, parentItem: *PropertiesItem)
    {
        let dispDesc = Reflection.getAttributeValue(value, Properties.Description, "desc")
        let item     = .addItem(value, data, parentItem, flags: AddItemFlags.Name)

        var editWidth  = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
        if !.isGridLike() do
            editWidth = .listContentWidthFromUseful(editWidth)
        let lineHeight = .kind == .Condensed ? PropCondensedControlHeight : .getThemeMetrics().btnPush_Height
        let line       = Wnd.create'Wnd(item.line, {0, 0, editWidth, lineHeight})
        line.maxSize.x = editWidth

        // Grid rows are single-line: center the editor vertically in the cell. List
        // rows stack the editor under the name label (the row is a StackLayoutCtrl),
        // so dock-centering would fight the stack and overlap the label — anchor the
        // width instead and let the stack own the vertical placement.
        if .isGridLike() do
            line.dockStyle = .CenterKeepSizeVert
        else
        {
            line.anchorStyle = .X
        }

        if !item.label
        {
            line.margin.y = .listNameMarginBefore
            line.margin.w = .listNameMarginAfter
        }

        with let ed = CheckButton.create(line, "", {0, 0, lineHeight, 0})
        {
            .dockStyle = .Left
        }

        if .kind == .List
        {
            with let label = Label.create(line, "", {lineHeight, 0, Math.max(editWidth - lineHeight, 1.0)})
            {
                .dockStyle = .Center
                .labelFlags |= .WordWrap | .AutoHeight
                .horzAlignmentText = .Left
                .setText(dispDesc == null ? "" : cast(string) dispDesc)
            }

            item.sigResize += func|label, line, lineHeight|(item)
            {
                // The check box is a symmetric square centered on the row, but a centered
                // text line reads slightly high because the descender space below the
                // baseline is mostly empty. Nudge the text down by half the font descent
                // so its visual center lines up with the box. Deriving the amount from the
                // font metrics keeps it correct at any font size; the equal +top/-bottom
                // padding translates the text rect without clipping wrapped lines.
                let font = label.getFont().regular
                if font do
                    label.paddingText = {0, -font.descent * 0.5, 0, font.descent * 0.5}

                label.autoHeight()
                line.position.height = Math.max(lineHeight, label.position.height)
                line.preferredSize.y = line.position.height
            }
        }

        item.checkBox = ed
        ed.sigChanged += func|prop = me, item|(ed)
        {
            prop.validateBool(item)
        }

        .refreshBool(item)
    }
}

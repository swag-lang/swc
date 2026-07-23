impl Properties
{
    mtd refreshBool(item: *PropertiesItem)
    {
        if #isset(item.checkBox)
        {
            // Multi-selection: a disagreeing bool shows as the indeterminate (mixed) mark.
            if .fieldIsMixed(item) do
                item.checkBox.checked = .Undefined
            else do
                item.checkBox.checked = dref cast(#null *bool) item.data ? .Checked : .UnChecked
            item.checkBox.invalidate()
        }
        elif #isset(item.comboBox)
        {
            // Multi-selection: clear the selection when the instances disagree.
            if .fieldIsMixed(item) do
                item.comboBox.selectItem(Swag.U32.Max)
            else do
                item.comboBox.selectItem(dref cast(#null *bool) item.data ? 1 : 0)
        }
    }

    mtd validateBool(item: *PropertiesItem)
    {
        var data = cast(#null *bool) item.data
        if #isset(item.checkBox) do
            dref data = item.checkBox.checked == .Checked ? true : false
        elif #isset(item.comboBox)
        {
            // A deselected combo means "mixed" was just shown: nothing to write.
            let sel = item.comboBox.selectedIdx
            if sel > 1 do
                return
            dref data = sel == 1
        }

        .hasChanged(item)
    }

    // Bool shown as a two-entries combo (the BoolCombo attribute): 'off' labels false,
    // 'on' labels true.
    mtd constructBoolCombo(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)

        if .kind == .Panel
        {
            with let ctrl = ComboCtrl.create(item.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .X
                .comboSize   = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", 0)
            }

            item.comboBox = ctrl.combo
        }
        else
        {
            var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
            if !.isGridLike() do
                editWidth = .listContentWidthFromUseful(editWidth)
            with let ed = ComboBox.create(item.line, kind: .CheckBox)
            {
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = editWidth
                if me.kind == .Condensed do
                    .comboBoxFlags.add(.Flat)
            }

            me.adaptCondensedControl(ed)
            item.comboBox = ed
        }

        item.comboBox.addItem(cast(string) (notnull Reflection.getAttributeValue(value, .BoolCombo, "off")))
        item.comboBox.addItem(cast(string) (notnull Reflection.getAttributeValue(value, .BoolCombo, "on")))

        .refreshBool(item)
        item.comboBox.sigChanged += func|prop = me, item|(ed, n)
        {
            prop.validateBool(item)
        }
    }

    mtd constructBool(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        if Reflection.hasAttribute(value, .BoolCombo)
        {
            .constructBoolCombo(value, data, parentItem)
            return
        }

        // Panel row: a self-labeled check button
        if .kind == .Panel
        {
            let itemP = .addItem(value, data, parentItem)
            with let ed = CheckButton.create(notnull itemP.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .X
            }

            itemP.checkBox = ed
            ed.sigChanged += func|prop = me, itemP|(ed)
            {
                prop.validateBool(itemP)
            }

            .refreshBool(itemP)
            return
        }

        let dispDesc = Reflection.getAttributeValue(value, Properties.Description, "desc")
        let item     = .addItem(value, data, parentItem, flags: AddItemFlags.Name)

        var editWidth  = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
        if !.isGridLike() do
            editWidth = .listContentWidthFromUseful(editWidth)
        let lineHeight = .kind == .Condensed ? PropCondensedControlHeight : .getThemeMetrics().btnPush_Height
        let line       = Wnd.create'Wnd(item.line, {0, 0, editWidth, lineHeight})
        // Grid cell: the check line is capped to the value column. List rows let it span
        // the whole row so the side description wraps over the full control width.
        if .isGridLike() do
            line.maxSize.x = editWidth

        // Grid rows are single-line: center the editor vertically in the cell. List
        // rows stack the check line under the name label and stretch it over the row
        // width (the side description wraps over the whole control).
        if .isGridLike() do
            line.dockStyle = .CenterKeepSizeVert
        else do
            line.layoutSpec.alignX = .Stretch

        if !#isset(item.label)
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
                .setText(dispDesc == null ? "" : cast(string) (dispDesc))
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

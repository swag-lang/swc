internal impl Properties
{
    mtd refreshBool(item: *PropertiesItem)
    {
        if item.checkBox != null
        {
            // Multi-selection: a disagreeing bool shows as the indeterminate (mixed) mark.
            if .fieldIsMixed(item) do
                item.checkBox.setState(.Indeterminate)
            else do
                item.checkBox.setState(cast(const *bool, unwrap item.data)[] ? .Checked : .Unchecked)
            item.checkBox.invalidate()
        }
        elif item.comboBox != null
        {
            // Multi-selection: clear the selection when the instances disagree.
            if .fieldIsMixed(item) do
                item.comboBox.clearSelection(notify: false)
            else do
                item.comboBox.setSelectedIndex(cast(const *bool, unwrap item.data)[] ? 1 : 0, notify: false)
        }
    }

    mtd validateBool(item: *PropertiesItem)
    {
        var data = cast(*bool, unwrap item.data)
        if item.checkBox != null
        {
            data[] = item.checkBox.isChecked()
        }
        elif item.comboBox != null
        {
            // A deselected combo means "mixed" was just shown: nothing to write.
            let sel = item.comboBox.selectedIndex
            if sel > 1 do
                return
            data[] = sel == 1
        }

        .commitItemChange(item)
    }

    // Shows a choice of at most three entries as segments in the Panel and Grid rows, which have
    // the width for them: every entry is then on screen and one click away.
    mtd segmentSmallChoice(combo: *ComboBox)
    {
        if (.kind == .Panel or .kind == .Grid) and combo.items.count <= MaxSegmentedEntries do
            combo.updateFlags(.Segmented)
    }

    // Bool shown as a two-entries combo (the BoolCombo attribute): 'off' labels false,
    // 'on' labels true.
    mtd constructBoolCombo(value: Swag.TypeValue, data: *u8?, parentItem: *PropertiesItem?)
    {
        let item = .addItem(value, data, parentItem)

        if .kind == .Panel
        {
            if item.label != null do
                item.label.hide()
            with let ctrl = ComboCtrl.create(item.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .Right
                .setLayoutMetrics(.labelWidth, cast(f32, Reflection.attributeValue(value, me.EditSize, "size", 0)))
            }

            item.assignComboBox(ctrl.combo)
        }
        else
        {
            var editWidth = cast(f32, Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth))
            if not .isGridLike() do
                editWidth = .listContentWidthFromUseful(editWidth)
            with let ed = ComboBox.create(item.line)
            {
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = editWidth
                if me.kind == .Condensed do
                    .updateFlags(.Flat)
            }

            me.adaptCondensedControl(ed)
            item.assignComboBox(ed)
        }

        item.comboBox.addItem(attributeText(Reflection.attributeValue(value, .BoolCombo, "off")))
        item.comboBox.addItem(attributeText(Reflection.attributeValue(value, .BoolCombo, "on")))

        .segmentSmallChoice(item.comboBox)

        .refreshBool(item)
        item.comboBox.sigChanged += func|prop = me, item|(_, _) { prop.validateBool(item) }
    }

    mtd constructBool(value: Swag.TypeValue, data: *u8?, parentItem: *PropertiesItem?)
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
            if itemP.label != null do
                itemP.label.hide()
            with let ed = CheckButton.create(itemP.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .Right
                .toolTip     = itemP.description
            }

            itemP.assignCheckBox(ed)
            ed.sigChanged += func|prop = me, itemP|(_) { prop.validateBool(itemP) }

            .refreshBool(itemP)
            return
        }

        let item = .addItem(value, data, parentItem, flags: PropertiesAddItemFlags.Name)

        var editWidth = cast(f32, Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth))
        if not .isGridLike() do
            editWidth = .listContentWidthFromUseful(editWidth)
        let metrics    = .themeMetrics()
        let lineHeight = .kind == .Condensed ? PropCondensedControlHeight : metrics.btnPush_Height
        let line       = Wnd.create'Wnd(item.line, Math.Rectangle{0, 0, editWidth, lineHeight})

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

        if item.label == null
        {
            line.margin.y = .listNameMarginBefore
            line.margin.w = .listNameMarginAfter
        }

        let checkWidth = .kind == .List ? metrics.btnCheck_Size + metrics.btnCheck_Padding : lineHeight
        with let ed    = CheckButton.create(line, "", Math.Rectangle{0, 0, checkWidth, 0})
        {
            .dockStyle = .Left
        }

        if .kind == .List
        {
            with let label = Label.create(line, "", Math.Rectangle{checkWidth, 0, Math.max(editWidth - checkWidth, 1.0)})
            {
                .dockStyle = .Center
                .updateFlags(.WordWrap | .AutoHeight)
                .setTextAlignment(.Left, .OpticalCenter)
                .setText(item.description.toString())
                me.styleListDescription(label)
            }

            item.sigResize += func|label, line, lineHeight|(_)
            {
                label.updateAutomaticHeight()
                line.position.height = Math.max(lineHeight, label.position.height)
                line.preferredSize.y = line.position.height
            }
        }

        item.assignCheckBox(ed)
        ed.sigChanged += func|prop = me, item|(_) { prop.validateBool(item) }

        .refreshBool(item)
    }
}

// The most entries a choice of the grid shows as segments rather than as a list.
private const MaxSegmentedEntries = 3

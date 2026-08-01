// System font families listed by the FontName editor, enumerated once per process.
internal var g_PropSysFonts: Array'SystemFontFamilyInfo

internal impl Properties
{
    mtd validateDynamicString(item: *PropertiesItem)
    {
        var data = notnull cast(#null *String) item.data
        if @isset(item.editBox) do
            dref data = item.editBox.text()
        .commitItemChange(item)
    }

    // A String field carrying the FontName attribute: a combo of the system font
    // families. The first entry is the theme's default font and stores an empty name.
    mtd refreshFontName(item: *PropertiesItem)
    {
        if !@isset(item.comboBox) do
            return

        if .fieldIsMixed(item)
        {
            item.comboBox.clearSelection(notify: false)
            return
        }

        let cur = notnull cast(#null *String) item.data
        var sel = 0'u32
        for &fnt, [idx] in g_PropSysFonts
        {
            if dref cur == fnt.name do
                sel = cast(u32) idx + 1
        }

        item.comboBox.setSelectedIndex(sel, notify: false)
    }

    mtd validateFontName(item: *PropertiesItem)
    {
        let sel = item.comboBox.selectedIndex
        if sel == Swag.U32.Max do
            return

        var data = notnull cast(#null *String) item.data
        if sel == 0 do
            data.clear()
        else do
            dref data = g_PropSysFonts[sel - 1].name

        .commitItemChange(item)
    }

    mtd constructFontName(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)

        if g_PropSysFonts.isEmpty() do
            g_PropSysFonts = FontFamily.enumerateSystemFonts()

        var combo: #null *ComboBox
        if .kind == .Panel
        {
            with let ctrl = ComboCtrl.create(item.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .Right
                .setLayoutMetrics(.labelWidth, cast(f32) Reflection.attributeValue(value, me.EditSize, "size", 0))
            }

            combo = ctrl.combo
        }
        else
        {
            var editWidth = cast(f32) Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth)
            if !.isGridLike() do
                editWidth = .listContentWidthFromUseful(editWidth)
            with combo = ComboBox.create(item.line)
            {
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = editWidth
                if me.kind == .Condensed do
                    .updateFlags(.Flat)
            }

            me.adaptCondensedControl(combo)
        }

        let combon = notnull combo
        item.assignComboBox(combon)
        combon.addItem(.theme().res.defaultTypeFaceR.familyName())
        combon.addSeparator()
        for &fnt in g_PropSysFonts do
            combon.addItem(fnt.name)

        .refreshFontName(item)
        combon.sigChanged += func|prop = me, item|(ed, n) { prop.validateFontName(item) }
    }

    mtd constructDynamicString(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        if Reflection.hasAttribute(value, .FontName)
        {
            .constructFontName(value, data, parentItem)
            return
        }

        let item      = .addItem(value, data, parentItem)
        var editWidth = cast(f32) Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth)
        if !me.isGridLike() do
            editWidth = me.listContentWidthFromUseful(editWidth)
        with let ed = EditBox.create(item.line, dref notnull cast(#null *String) data)
        {
            if me.kind == .Panel
            {
                .anchorStyle = .Right
                .setPlaceholder(itemDisplayName(value).toString())
            }
            elif me.isGridLike() do
                .dockStyle = .CenterKeepSizeVert
            else do
                .preferredSize.x = editWidth

            if me.kind != .Panel do
                .maxSize.x = editWidth

            .sigFocusLost += func|prop = me, item|(ed) { prop.validateDynamicString(item); }
        }

        me.adaptCondensedControl(ed)
        me.flattenCondensedEdit(ed)
        item.assignEditBox(ed)

        // The MultiLine attribute adds a '...' button opening a multi-line edition dialog
        if Reflection.hasAttribute(value, .MultiLine)
        {
            ed.setTrailingMargin(24)
            with let btn = IconButton.create(ed, .theme().icon24(.More, 20), {0, 0, 20, 20})
            {
                .dockStyle  = .Right
                .sigPressed += func|prop = me, item, ed|(btn)
                {
                    with let dlg = EditDlg.createMultiLine(notnull prop.surface)
                    {
                        .setText(ed.text())
                        let richEdit = notnull .richEdit
                        richEdit.selectAll()
                    }

                    if dlg.doModal() != Dialog.BtnOk do
                        return
                    ed.setText(dlg.text())
                    prop.validateDynamicString(item)
                }
            }
        }
    }

    mtd constructStaticString(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item      = .addItem(value, data, parentItem)
        var editWidth = cast(f32) Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth)
        if !me.isGridLike() do
            editWidth = me.listContentWidthFromUseful(editWidth)

        with let ed = EditBox.create(item.line, dref notnull cast(#null *string) data)
        {
            .maxSize.x = editWidth
            if me.isGridLike() do
                .dockStyle = .CenterKeepSizeVert
            else do
                .preferredSize.x = editWidth
            .updateFlags(.ReadOnly, .ReleaseFocusOnEnterOrEscape)
        }

        me.adaptCondensedControl(ed)
        me.flattenCondensedEdit(ed)
        item.assignEditBox(ed)
    }
}

// System font families listed by the FontName editor, enumerated once per process.
internal var g_PropSysFonts: Array'FontFamilyEnumerate

impl Properties
{
    mtd validateDynamicString(item: *PropertiesItem)
    {
        var data = cast(#null *String) item.data
        if item.editBox do
            dref data = item.editBox.getText()
        .hasChanged(item)
    }

    // A String field carrying the FontName attribute: a combo of the system font
    // families. The first entry is the theme's default font and stores an empty name.
    mtd refreshFontName(item: *PropertiesItem)
    {
        if !item.comboBox do
            return

        if .fieldIsMixed(item)
        {
            item.comboBox.selectItem(Swag.U32.Max)
            return
        }

        let cur = cast(#null *String) item.data
        var sel = 0'u32
        for &fnt, idx in g_PropSysFonts
        {
            if dref cur == fnt.name do
                sel = cast(u32) idx + 1
        }

        item.comboBox.selectItem(sel)
    }

    mtd validateFontName(item: *PropertiesItem)
    {
        let sel = item.comboBox.selectedIdx
        if sel == Swag.U32.Max do
            return

        var data = cast(#null *String) item.data
        if sel == 0 do
            data.clear()
        else do
            dref data = g_PropSysFonts[sel - 1].name

        .hasChanged(item)
    }

    mtd constructFontName(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)

        if g_PropSysFonts.isEmpty() do
            g_PropSysFonts = FontFamily.enumerateFromOs()

        var combo: #null *ComboBox
        if .kind == .Panel
        {
            with let ctrl = ComboCtrl.create(assume item.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .X
                .comboSize   = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", 0)
            }

            combo = ctrl.combo
        }
        else
        {
            var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
            if !.isGridLike() do
                editWidth = .listContentWidthFromUseful(editWidth)
            with combo = ComboBox.create(assume item.line, kind: .CheckBox)
            {
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = editWidth
                if me.kind == .Condensed do
                    .comboBoxFlags.add(.Flat)
            }

            me.adaptCondensedControl(assume combo)
        }

        item.comboBox = combo
        combo.addItem(.getTheme().res.defaultTypeFaceR.getFamilyName())
        combo.addSeparator()
        for &fnt in g_PropSysFonts do
            combo.addItem(fnt.name)

        .refreshFontName(item)
        combo.sigChanged += func|prop = me, item|(ed, n)
        {
            prop.validateFontName(item)
        }
    }

    mtd constructDynamicString(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        if Reflection.hasAttribute(value, .FontName)
        {
            .constructFontName(value, data, parentItem)
            return
        }

        let item = .addItem(value, data, parentItem)
        var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
        if !me.isGridLike() do
            editWidth = me.listContentWidthFromUseful(editWidth)
        with let ed = EditBox.create(assume item.line, dref cast(#null *String) data)
        {
            if me.kind == .Panel
            {
                .anchorStyle = .X
                .setNote(itemDisplayName(value).toString())
            }
            elif me.isGridLike() do
                .dockStyle = .CenterKeepSizeVert
            else do
                .preferredSize.x = editWidth

            if me.kind != .Panel do
                .maxSize.x = editWidth

            .sigLoseFocus += func|prop = me, item|(ed) { prop.validateDynamicString(item); }
        }

        me.adaptCondensedControl(ed)
        me.flattenCondensedEdit(ed)
        item.editBox = ed

        // The MultiLine attribute adds a '...' button opening a multi-line edition dialog
        if Reflection.hasAttribute(value, .MultiLine)
        {
            ed.rightMargin = 24
            with let btn = IconButton.create(ed, .getTheme().getIcon24(.More, 20), {0, 0, 20, 20})
            {
                .dockStyle = .Right
                .sigPressed += func|prop = me, item, ed|(btn)
                {
                    with let dlg = EditDlg.createMultiLine(assume prop.surface)
                    {
                        .setText(ed.text)
                        .richEdit.selectAll()
                    }

                    if dlg.doModal() != Dialog.BtnOk do
                        return
                    ed.setText(dlg.getText())
                    prop.validateDynamicString(item)
                }
            }
        }
    }

    mtd constructStaticString(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)
        var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
        if !me.isGridLike() do
            editWidth = me.listContentWidthFromUseful(editWidth)

        with let ed = EditBox.create(assume item.line, dref cast(#null *string) data)
        {
            .maxSize.x = editWidth
            if me.isGridLike() do
                .dockStyle = .CenterKeepSizeVert
            else do
                .preferredSize.x = editWidth
            .editBoxFlags = .ReadOnly
        }

        me.adaptCondensedControl(ed)
        me.flattenCondensedEdit(ed)
        item.editBox = ed
    }
}
